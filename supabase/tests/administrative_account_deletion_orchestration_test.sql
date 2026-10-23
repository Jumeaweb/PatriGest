begin;
select plan(12);

select has_function(
  'public',
  'get_administrative_account_deletion_attempt',
  array['uuid','uuid'],
  'la RPC de reprise par tentative existe'
);

select has_function(
  'public',
  'list_administrative_account_storage_neutralization_operations',
  array['uuid'],
  'la RPC de reprise administrative existe'
);

select function_privs_are(
  'public',
  'list_administrative_account_storage_neutralization_operations',
  array['uuid'],
  'service_role',
  array['EXECUTE'],
  'service_role peut inventorier les neutralisations administratives'
);

select function_privs_are(
  'public',
  'get_administrative_account_deletion_attempt',
  array['uuid','uuid'],
  'authenticated',
  array['EXECUTE'],
  'authenticated peut demander la reprise, sous contrôle de la fonction'
);

select function_privs_are(
  'public',
  'get_administrative_account_deletion_attempt',
  array['uuid','uuid'],
  'service_role',
  array[]::text[],
  'service_role seul ne reçoit pas l autorisation métier de reprise'
);

select function_privs_are(
  'public',
  'list_administrative_account_storage_neutralization_operations',
  array['uuid'],
  'authenticated',
  array[]::text[],
  'authenticated ne peut pas appeler directement la RPC privilégiée'
);

select function_privs_are(
  'public',
  'list_administrative_account_storage_neutralization_operations',
  array['uuid'],
  'anon',
  array[]::text[],
  'anon ne peut pas appeler la RPC privilégiée'
);

select function_privs_are(
  'public',
  'list_administrative_account_storage_neutralization_operations',
  array['uuid'],
  'public',
  array[]::text[],
  'PUBLIC ne conserve aucun droit EXECUTE'
);

select is(
  (select prosecdef from pg_proc where oid =
    'public.list_administrative_account_storage_neutralization_operations(uuid)'::regprocedure),
  true,
  'la RPC utilise SECURITY DEFINER'
);

select is(
  (select prosecdef from pg_proc where oid =
    'public.get_administrative_account_deletion_attempt(uuid,uuid)'::regprocedure),
  true,
  'la reprise par tentative utilise SECURITY DEFINER'
);

select is(
  (select proconfig from pg_proc where oid =
    'public.list_administrative_account_storage_neutralization_operations(uuid)'::regprocedure),
  array['search_path=""'],
  'le search_path de la RPC est vide'
);

select is(
  (select proconfig from pg_proc where oid =
    'public.get_administrative_account_deletion_attempt(uuid,uuid)'::regprocedure),
  array['search_path=""'],
  'le search_path de la reprise par tentative est vide'
);

select * from finish();
rollback;
