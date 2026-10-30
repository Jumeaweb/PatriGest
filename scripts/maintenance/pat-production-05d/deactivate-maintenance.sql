\set ON_ERROR_STOP on

begin;

select pg_advisory_xact_lock(
  hashtextextended('patrigest:production-maintenance', 0)
);

do $deactivation_preconditions$
declare
  expected_membership_fingerprint text;
  current_membership_fingerprint text;
  unexpected_acl_count integer;
begin
  if current_user <> 'postgres' then
    raise exception using
      errcode = '42501',
      message = 'maintenance deactivation must run as postgres';
  end if;

  if to_regnamespace('patrigest_maintenance') is null
    or to_regclass('patrigest_maintenance.activation_state') is null
    or to_regclass('patrigest_maintenance.schema_acl_snapshot') is null then
    raise exception 'no complete PatriGest maintenance activation was found';
  end if;

  if (select count(*) from patrigest_maintenance.activation_state) <> 1 then
    raise exception 'maintenance activation state is missing or ambiguous';
  end if;

  if not exists (
    select 1
    from pg_trigger
    where tgrelid = 'storage.objects'::regclass
      and tgname = 'patrigest_reject_storage_object_mutation'
      and tgenabled = 'O'
      and not tgisinternal
  ) then
    raise exception 'temporary Storage maintenance trigger is missing or disabled';
  end if;

  select membership_fingerprint
  into expected_membership_fingerprint
  from patrigest_maintenance.activation_state;

  select md5(coalesce(string_agg(
    member.rolname || '>' || parent.rolname || ':' || membership.admin_option::text,
    ',' order by member.rolname, parent.rolname, membership.admin_option
  ), ''))
  into current_membership_fingerprint
  from pg_auth_members membership
  join pg_roles member on member.oid = membership.member
  join pg_roles parent on parent.oid = membership.roleid
  where member.rolname in ('anon', 'authenticated', 'service_role')
     or parent.rolname in ('anon', 'authenticated', 'service_role');

  if current_membership_fingerprint is distinct from expected_membership_fingerprint then
    raise exception 'role memberships changed during maintenance; automatic ACL restoration refused';
  end if;

  select count(*)
  into unexpected_acl_count
  from pg_namespace namespace
  cross join lateral aclexplode(
    coalesce(namespace.nspacl, acldefault('n', namespace.nspowner))
  ) expanded
  left join pg_roles grantee on grantee.oid = expanded.grantee
  where namespace.nspname = 'public'
    and (
      expanded.grantee = 0
      or grantee.rolname in ('anon', 'authenticated', 'service_role')
    );

  if unexpected_acl_count <> 0 then
    raise exception 'schema public ACL drift detected during maintenance; automatic restoration refused';
  end if;
end;
$deactivation_preconditions$;

do $restore_captured_acl$
declare
  captured_acl jsonb;
  captured_grant jsonb;
  grantee_sql text;
  grant_option_sql text;
begin
  select jsonb_agg(
    jsonb_build_object(
      'grantor', grantor_name,
      'grantee', grantee_name,
      'privilege', privilege_type,
      'grantable', is_grantable
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
    grant_option_sql := case
      when (captured_grant->>'grantable')::boolean then ' with grant option'
      else ''
    end;

    execute format('set local role %I', captured_grant->>'grantor');
    execute format(
      'grant %s on schema public to %s%s',
      captured_grant->>'privilege',
      grantee_sql,
      grant_option_sql
    );
    reset role;
  end loop;
exception
  when others then
    reset role;
    raise;
end;
$restore_captured_acl$;

do $restoration_postconditions$
declare
  acl_difference_count integer;
  role_snapshot record;
begin
  with restored_acl as (
    select
      namespace.nspname as schema_name,
      grantor.rolname as grantor_name,
      case
        when expanded.grantee = 0 then 'PUBLIC'
        else grantee.rolname
      end as grantee_name,
      expanded.privilege_type,
      expanded.is_grantable
    from pg_namespace namespace
    cross join lateral aclexplode(
      coalesce(namespace.nspacl, acldefault('n', namespace.nspowner))
    ) expanded
    join pg_roles grantor on grantor.oid = expanded.grantor
    left join pg_roles grantee on grantee.oid = expanded.grantee
    where namespace.nspname = 'public'
      and (
        expanded.grantee = 0
        or grantee.rolname in ('anon', 'authenticated', 'service_role')
      )
  ),
  acl_differences as (
    (
      select * from restored_acl
      except
      select * from patrigest_maintenance.schema_acl_snapshot
    )
    union all
    (
      select * from patrigest_maintenance.schema_acl_snapshot
      except
      select * from restored_acl
    )
  )
  select count(*)
  into acl_difference_count
  from acl_differences;

  if acl_difference_count <> 0 then
    raise exception 'restored schema public ACL does not match the activation snapshot';
  end if;

  for role_snapshot in
    select *
    from patrigest_maintenance.role_state_snapshot
  loop
    if has_schema_privilege(role_snapshot.role_name, 'public', 'USAGE')
        is distinct from role_snapshot.had_effective_usage
      or has_schema_privilege(role_snapshot.role_name, 'public', 'CREATE')
        is distinct from role_snapshot.had_effective_create then
      raise exception 'effective privileges were not restored for role %', role_snapshot.role_name;
    end if;
  end loop;
end;
$restoration_postconditions$;

drop trigger patrigest_reject_storage_object_mutation on storage.objects;
drop function patrigest_maintenance.reject_storage_object_mutation();
drop table patrigest_maintenance.role_state_snapshot;
drop table patrigest_maintenance.schema_acl_snapshot;
drop table patrigest_maintenance.activation_state;
drop schema patrigest_maintenance;

do $temporary_objects_removed$
begin
  if to_regnamespace('patrigest_maintenance') is not null then
    raise exception 'temporary maintenance schema was not removed';
  end if;

  if exists (
    select 1
    from pg_trigger
    where tgrelid = 'storage.objects'::regclass
      and tgname = 'patrigest_reject_storage_object_mutation'
      and not tgisinternal
  ) then
    raise exception 'temporary Storage maintenance trigger was not removed';
  end if;
end;
$temporary_objects_removed$;

commit;

select 'inactive' as maintenance_state;
