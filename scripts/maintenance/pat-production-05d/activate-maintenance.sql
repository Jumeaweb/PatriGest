\set ON_ERROR_STOP on

begin;

select pg_advisory_xact_lock(
  hashtextextended('patrigest:production-maintenance', 0)
);

do $activation_preconditions$
declare
  missing_roles text;
begin
  if current_user <> 'postgres' then
    raise exception using
      errcode = '42501',
      message = 'maintenance activation must run as postgres';
  end if;

  select string_agg(required_role, ', ' order by required_role)
  into missing_roles
  from unnest(array['anon', 'authenticated', 'service_role']) required_role
  where not exists (
    select 1
    from pg_roles
    where rolname = required_role
  );

  if missing_roles is not null then
    raise exception 'required PostgreSQL roles are missing: %', missing_roles;
  end if;

  if to_regclass('storage.objects') is null then
    raise exception 'required table storage.objects is missing';
  end if;

  if to_regnamespace('patrigest_maintenance') is not null then
    raise exception 'patrigest_maintenance already exists; inspect the current maintenance state';
  end if;

  if exists (
    select 1
    from pg_trigger
    where tgrelid = 'storage.objects'::regclass
      and tgname = 'patrigest_reject_storage_object_mutation'
      and not tgisinternal
  ) then
    raise exception 'temporary Storage maintenance trigger already exists';
  end if;
end;
$activation_preconditions$;

create schema patrigest_maintenance authorization postgres;
revoke all on schema patrigest_maintenance from public;

create table patrigest_maintenance.schema_acl_snapshot (
  schema_name text not null,
  grantor_name text not null,
  grantee_name text not null,
  privilege_type text not null check (privilege_type in ('USAGE', 'CREATE')),
  is_grantable boolean not null,
  primary key (
    schema_name,
    grantor_name,
    grantee_name,
    privilege_type
  )
);

create table patrigest_maintenance.role_state_snapshot (
  role_name text primary key,
  had_effective_usage boolean not null,
  had_effective_create boolean not null
);

create table patrigest_maintenance.activation_state (
  singleton boolean primary key default true check (singleton),
  activated_at timestamptz not null default clock_timestamp(),
  activated_by text not null default current_user,
  database_name text not null default current_database(),
  server_address text,
  server_port integer,
  membership_fingerprint text not null,
  acl_fingerprint text not null
);

insert into patrigest_maintenance.schema_acl_snapshot (
  schema_name,
  grantor_name,
  grantee_name,
  privilege_type,
  is_grantable
)
select
  namespace.nspname,
  grantor.rolname,
  case
    when expanded.grantee = 0 then 'PUBLIC'
    else grantee.rolname
  end,
  expanded.privilege_type,
  expanded.is_grantable
from pg_namespace namespace
cross join lateral aclexplode(
  coalesce(
    namespace.nspacl,
    acldefault('n', namespace.nspowner)
  )
) expanded
join pg_roles grantor on grantor.oid = expanded.grantor
left join pg_roles grantee on grantee.oid = expanded.grantee
where namespace.nspname = 'public'
  and (
    expanded.grantee = 0
    or grantee.rolname in ('anon', 'authenticated', 'service_role')
  );

insert into patrigest_maintenance.role_state_snapshot (
  role_name,
  had_effective_usage,
  had_effective_create
)
select
  role_name,
  has_schema_privilege(role_name, 'public', 'USAGE'),
  has_schema_privilege(role_name, 'public', 'CREATE')
from unnest(array['anon', 'authenticated', 'service_role']) role_name;

insert into patrigest_maintenance.activation_state (
  server_address,
  server_port,
  membership_fingerprint,
  acl_fingerprint
)
select
  inet_server_addr()::text,
  inet_server_port(),
  (
    select md5(coalesce(string_agg(
      member.rolname || '>' || parent.rolname || ':' || membership.admin_option::text,
      ',' order by member.rolname, parent.rolname, membership.admin_option
    ), ''))
    from pg_auth_members membership
    join pg_roles member on member.oid = membership.member
    join pg_roles parent on parent.oid = membership.roleid
    where member.rolname in ('anon', 'authenticated', 'service_role')
       or parent.rolname in ('anon', 'authenticated', 'service_role')
  ),
  (
    select md5(coalesce(string_agg(
      schema_name || ':' || grantor_name || '>' || grantee_name || ':'
        || privilege_type || ':' || is_grantable::text,
      ',' order by schema_name, grantor_name, grantee_name, privilege_type
    ), ''))
    from patrigest_maintenance.schema_acl_snapshot
  );

do $revoke_captured_acl$
declare
  captured_acl jsonb;
  captured_grant jsonb;
  grantee_sql text;
begin
  select jsonb_agg(
    jsonb_build_object(
      'grantor', grantor_name,
      'grantee', grantee_name,
      'privilege', privilege_type
    )
    order by grantor_name, grantee_name, privilege_type
  )
  into captured_acl
  from patrigest_maintenance.schema_acl_snapshot;

  for captured_grant in
    select value
    from jsonb_array_elements(coalesce(captured_acl, '[]'::jsonb))
  loop
    grantee_sql := case
      when captured_grant->>'grantee' = 'PUBLIC' then 'PUBLIC'
      else quote_ident(captured_grant->>'grantee')
    end;

    execute format('set local role %I', captured_grant->>'grantor');
    execute format(
      'revoke %s on schema public from %s',
      captured_grant->>'privilege',
      grantee_sql
    );
    reset role;
  end loop;
exception
  when others then
    reset role;
    raise;
end;
$revoke_captured_acl$;

create function patrigest_maintenance.reject_storage_object_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog
as $function$
begin
  raise exception using
    errcode = '55000',
    message = 'Storage mutations are temporarily disabled for maintenance';
end;
$function$;

revoke all on function patrigest_maintenance.reject_storage_object_mutation()
from public, anon, authenticated, service_role;

create trigger patrigest_reject_storage_object_mutation
before insert or update or delete on storage.objects
for each statement
execute function patrigest_maintenance.reject_storage_object_mutation();

do $activation_postconditions$
declare
  role_name text;
begin
  foreach role_name in array array['anon', 'authenticated', 'service_role']
  loop
    if has_schema_privilege(role_name, 'public', 'USAGE')
      or has_schema_privilege(role_name, 'public', 'CREATE') then
      raise exception 'role % retains an effective privilege on schema public', role_name;
    end if;
  end loop;

  if has_schema_privilege('public', 'public', 'USAGE')
    or has_schema_privilege('public', 'public', 'CREATE') then
    raise exception 'PUBLIC retains an effective privilege on schema public';
  end if;

  if not exists (
    select 1
    from pg_trigger
    where tgrelid = 'storage.objects'::regclass
      and tgname = 'patrigest_reject_storage_object_mutation'
      and tgenabled = 'O'
      and not tgisinternal
  ) then
    raise exception 'temporary Storage maintenance trigger is not enabled';
  end if;
end;
$activation_postconditions$;

commit;

select
  'active' as maintenance_state,
  activated_at,
  database_name,
  server_address,
  server_port
from patrigest_maintenance.activation_state;
