begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

-- Required server-side Data API reads remain available even when Supabase no
-- longer grants privileges automatically to roles on new public tables.
select extensions.ok(
  has_table_privilege('service_role', relation_name, 'SELECT'),
  format('service_role peut lire explicitement %s', relation_name)
)
from unnest(array[
  'public.account_requests',
  'public.application_user_authorizations',
  'public.bank_statements',
  'public.categories',
  'public.management_report_account_selections',
  'public.management_report_approvals',
  'public.management_report_difficulties',
  'public.management_report_documents',
  'public.management_report_transmissions',
  'public.management_reports',
  'public.platform_administrators',
  'public.profiles',
  'public.protected_person_access',
  'public.protected_person_invitations',
  'public.protected_persons',
  'public.transaction_documents'
]::text[]) as required_service_read(relation_name);

select extensions.ok(
  has_column_privilege(
    'service_role',
    'public.account_requests',
    'invitation_used_at',
    'UPDATE'
  ),
  'service_role peut marquer une invitation de demande de compte comme utilisée'
);

select extensions.is(
  (
    select array_agg(attribute.attname order by attribute.attname)
    from pg_catalog.pg_attribute as attribute
    join pg_catalog.pg_class as relation
      on relation.oid = attribute.attrelid
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'account_requests'
      and attribute.attnum > 0
      and not attribute.attisdropped
      and exists (
        select 1
        from aclexplode(attribute.attacl) as privilege
        join pg_catalog.pg_roles as grantee
          on grantee.oid = privilege.grantee
        where grantee.rolname = 'service_role'
          and privilege.privilege_type = 'UPDATE'
      )
  ),
  array['invitation_used_at']::name[],
  'le grant UPDATE explicite de service_role est limité à invitation_used_at'
);

-- These internal tables are intentionally reachable only through controlled
-- functions. The new grants must not reopen direct service-role access.
select extensions.ok(
  not has_table_privilege(
    'service_role',
    relation_name,
    'SELECT, INSERT, UPDATE, DELETE'
  ),
  format('service_role ne dispose d’aucun accès direct à %s', relation_name)
)
from unnest(array[
  'public.protected_person_share_limit_configuration',
  'public.subscription_plans',
  'public.subscription_features',
  'public.subscription_plan_features',
  'public.subscription_dossier_capacities',
  'public.account_subscriptions',
  'public.protected_person_archive_runtime_config',
  'public.document_operations',
  'public.document_operation_targets',
  'public.document_object_locks',
  'public.document_operation_events',
  'public.document_storage_guard_runtime_config',
  'public.document_operation_backups'
]::text[]) as internal_relation(relation_name);

-- Representative business privileges remain explicit for authenticated.
select extensions.ok(
  has_table_privilege('authenticated', 'public.profiles', 'SELECT')
  and has_table_privilege('authenticated', 'public.protected_persons', 'SELECT')
  and has_table_privilege('authenticated', 'public.categories', 'SELECT')
  and has_table_privilege('authenticated', 'public.bank_statements', 'SELECT')
  and has_table_privilege('authenticated', 'public.management_reports', 'SELECT')
  and has_table_privilege('authenticated', 'public.transaction_documents', 'SELECT'),
  'les lectures métier explicites de authenticated sont conservées'
);

select extensions.ok(
  has_any_column_privilege(
    'authenticated',
    'public.application_user_authorizations',
    'SELECT'
  )
  and has_any_column_privilege(
    'authenticated',
    'public.protected_person_invitations',
    'SELECT'
  ),
  'les lectures métier limitées par colonne de authenticated sont conservées'
);

select extensions.ok(
  has_table_privilege('anon', 'public.account_requests', 'INSERT'),
  'anon conserve le droit prévu de déposer une demande de compte'
);

select * from extensions.finish();
rollback;
