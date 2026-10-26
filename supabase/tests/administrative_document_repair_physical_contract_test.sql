begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

select extensions.has_function(
  'public', 'get_administrative_document_repair_authorization',
  array['uuid','uuid'],
  'la tentative administrative peut être relue sans accès direct aux tables'
);
select extensions.has_function(
  'public', 'mark_administrative_document_repair_backup_restored',
  array['uuid','uuid','uuid','uuid','text','uuid','bigint','bigint'],
  'la restauration physique dispose d’une transition SQL spécialisée'
);
select extensions.has_function(
  'public', 'authorize_administrative_document_repair_backup_cleanup',
  array['uuid','uuid','uuid','uuid','text','uuid','bigint','bigint'],
  'le nettoyage exige un descripteur spécialisé'
);
select extensions.has_function(
  'public', 'complete_administrative_document_repair_backup_cleanup',
  array['uuid','uuid','uuid','uuid','text','uuid','bigint','bigint'],
  'le nettoyage physique doit être finalisé explicitement'
);

select extensions.ok(
  has_function_privilege(
    'authenticated',
    'public.get_administrative_document_repair_authorization(uuid,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.get_administrative_document_repair_authorization(uuid,uuid)',
    'EXECUTE'
  ),
  'seul l’administrateur authentifié relit sa tentative'
);
select extensions.ok(
  has_function_privilege(
    'service_role',
    'public.mark_administrative_document_repair_backup_restored(uuid,uuid,uuid,uuid,text,uuid,bigint,bigint)',
    'EXECUTE'
  )
  and has_function_privilege(
    'service_role',
    'public.authorize_administrative_document_repair_backup_cleanup(uuid,uuid,uuid,uuid,text,uuid,bigint,bigint)',
    'EXECUTE'
  )
  and has_function_privilege(
    'service_role',
    'public.complete_administrative_document_repair_backup_cleanup(uuid,uuid,uuid,uuid,text,uuid,bigint,bigint)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.mark_administrative_document_repair_backup_restored(uuid,uuid,uuid,uuid,text,uuid,bigint,bigint)',
    'EXECUTE'
  ),
  'les transitions physiques sont réservées au moteur privilégié'
);
select extensions.ok(
  (
    select bool_and(procedure.prosecdef
      and procedure.proconfig = array['search_path=""'])
    from pg_proc procedure
    where procedure.oid in (
      'public.get_administrative_document_repair_authorization(uuid,uuid)'::regprocedure,
      'public.mark_administrative_document_repair_backup_restored(uuid,uuid,uuid,uuid,text,uuid,bigint,bigint)'::regprocedure,
      'public.authorize_administrative_document_repair_backup_cleanup(uuid,uuid,uuid,uuid,text,uuid,bigint,bigint)'::regprocedure,
      'public.complete_administrative_document_repair_backup_cleanup(uuid,uuid,uuid,uuid,text,uuid,bigint,bigint)'::regprocedure
    )
  ),
  'les nouvelles RPC sont SECURITY DEFINER avec search_path fermé'
);
select extensions.ok(
  not has_table_privilege(
    'service_role', 'public.document_repair_authorizations', 'SELECT'
  )
  and not has_table_privilege(
    'service_role', 'public.document_repair_items', 'UPDATE'
  )
  and not has_table_privilege(
    'authenticated', 'public.document_operation_backups', 'UPDATE'
  ),
  'aucun accès direct aux registres techniques n’est ajouté'
);

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select extensions.throws_ok(
  $$select public.mark_administrative_document_repair_backup_restored(
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222',
    '33333333-3333-4333-8333-333333333333',
    '44444444-4444-4444-8444-444444444444',
    repeat('a',64),
    '55555555-5555-4555-8555-555555555555',0,0
  )$$,
  'P4R01', 'Contexte technique de réparation non autorisé.',
  'service_role seul ne peut jamais inventer une restauration'
);
select extensions.throws_ok(
  $$select public.authorize_administrative_document_repair_backup_cleanup(
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222',
    '33333333-3333-4333-8333-333333333333',
    '44444444-4444-4444-8444-444444444444',
    repeat('a',64),
    '55555555-5555-4555-8555-555555555555',0,0
  )$$,
  'P4R01', 'Contexte technique de réparation non autorisé.',
  'service_role seul ne peut jamais autoriser un nettoyage arbitraire'
);
reset role;

select * from extensions.finish();
rollback;
