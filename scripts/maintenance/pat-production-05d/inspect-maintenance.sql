\set ON_ERROR_STOP on

select
  case
    when to_regnamespace('patrigest_maintenance') is null then 'inactive'
    when to_regclass('patrigest_maintenance.activation_state') is not null
      and exists (
        select 1
        from pg_trigger
        where tgrelid = 'storage.objects'::regclass
          and tgname = 'patrigest_reject_storage_object_mutation'
          and tgenabled = 'O'
          and not tgisinternal
      ) then 'active'
    else 'inconsistent'
  end as maintenance_state;

select
  role_name,
  has_schema_privilege(role_name, 'public', 'USAGE') as effective_usage,
  has_schema_privilege(role_name, 'public', 'CREATE') as effective_create
from unnest(array['anon', 'authenticated', 'service_role']) role_name
order by role_name;

select
  has_schema_privilege('public', 'public', 'USAGE') as public_effective_usage,
  has_schema_privilege('public', 'public', 'CREATE') as public_effective_create;

select
  trigger_name,
  enabled
from (
  select
    trigger.tgname as trigger_name,
    trigger.tgenabled = 'O' as enabled
  from pg_trigger trigger
  where trigger.tgrelid = 'storage.objects'::regclass
    and trigger.tgname = 'patrigest_reject_storage_object_mutation'
    and not trigger.tgisinternal
) temporary_trigger;
