begin;

select extensions.plan(23);

select extensions.has_function(
  'public', 'final_management_report_snapshot_from_project', array['jsonb'],
  'la normalisation contrôlée du snapshot existe'
);
select extensions.has_function(
  'public', 'validate_final_management_report_snapshot', array[]::text[],
  'la garde des métadonnées finales existe'
);
select extensions.has_trigger(
  'public', 'management_report_documents',
  'management_report_documents_10_validate_final_snapshot',
  'la garde couvre le point commun aux finalisations historique et durable'
);
select extensions.ok(
  not has_function_privilege(
    'authenticated',
    'public.final_management_report_snapshot_from_project(jsonb)',
    'EXECUTE'
  ) and not has_function_privilege(
    'service_role',
    'public.final_management_report_snapshot_from_project(jsonb)',
    'EXECUTE'
  ),
  'la primitive de normalisation reste interne'
);
select extensions.is(
  (select count(*) from pg_policies
   where schemaname='public'
     and tablename='management_report_documents'
     and cmd in ('INSERT','UPDATE','ALL')),
  0::bigint,
  'aucune politique RLS n’autorise une insertion ou modification applicative directe'
);
select extensions.is(
  public.final_management_report_snapshot_from_project(
    '{"report":{"status":"generated"},"amount":100}'::jsonb
  ),
  '{"report":{"status":"finalized"},"amount":100}'::jsonb,
  'seul le statut documentaire est normalisé'
);
select extensions.is(
  public.final_management_report_snapshot_from_project(
    '{"report":{"status":"ready"},"amount":100}'::jsonb
  ),
  null::jsonb,
  'un snapshot qui n’est pas un projet généré est refusé'
);

insert into auth.users(
  instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at
) values
('00000000-0000-0000-0000-000000000000','99100000-0000-4000-8000-000000000001',
 'authenticated','authenticated','snapshot-owner@example.test','test',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','99100000-0000-4000-8000-000000000002',
 'authenticated','authenticated','snapshot-reader@example.test','test',now(),'{}','{}',now(),now());

update public.application_user_authorizations
set status='active',status_changed_at=now()
where user_id in (
  '99100000-0000-4000-8000-000000000001',
  '99100000-0000-4000-8000-000000000002'
);
update public.application_user_authorizations
set account_mode='autonomous'
where user_id='99100000-0000-4000-8000-000000000001';
insert into public.account_subscriptions(owner_id,status,started_at) values
('99100000-0000-4000-8000-000000000001','development',now());

insert into public.protected_persons(id,owner_id,first_name,last_name) values
('99100000-0000-4000-8100-000000000001',
 '99100000-0000-4000-8000-000000000001','Projet','Stable');
insert into public.protected_person_access(
  id,protected_person_id,user_id,role,invited_by
) values (
  '99100000-0000-4000-8900-000000000001',
  '99100000-0000-4000-8100-000000000001',
  '99100000-0000-4000-8000-000000000002','read_only',
  '99100000-0000-4000-8000-000000000001'
);

insert into public.management_reports(
  id,protected_person_id,report_year,period_start,period_end,status,generated_at,
  finalized_at,created_by
) values
('99100000-0000-4000-8600-000000000001','99100000-0000-4000-8100-000000000001',
 2026,'2026-01-01','2026-12-31','generated',now(),null,'99100000-0000-4000-8000-000000000001'),
('99100000-0000-4000-8600-000000000002','99100000-0000-4000-8100-000000000001',
 2027,'2027-01-01','2027-12-31','generated',now(),null,'99100000-0000-4000-8000-000000000001'),
('99100000-0000-4000-8600-000000000003','99100000-0000-4000-8100-000000000001',
 2028,'2028-01-01','2028-12-31','generated',now(),null,'99100000-0000-4000-8000-000000000001'),
('99100000-0000-4000-8600-000000000004','99100000-0000-4000-8100-000000000001',
 2029,'2029-01-01','2029-12-31','generated',now(),null,'99100000-0000-4000-8000-000000000001'),
('99100000-0000-4000-8600-000000000005','99100000-0000-4000-8100-000000000001',
 2030,'2030-01-01','2030-12-31','generated',now(),null,'99100000-0000-4000-8000-000000000001'),
('99100000-0000-4000-8600-000000000006','99100000-0000-4000-8100-000000000001',
 2031,'2031-01-01','2031-12-31','generated',now(),null,'99100000-0000-4000-8000-000000000001'),
('99100000-0000-4000-8600-000000000007','99100000-0000-4000-8100-000000000001',
 2032,'2032-01-01','2032-12-31','finalized',now(),now(),'99100000-0000-4000-8000-000000000001'),
('99100000-0000-4000-8600-000000000008','99100000-0000-4000-8100-000000000001',
 2033,'2033-01-01','2033-12-31','ready',null,null,'99100000-0000-4000-8000-000000000001');

insert into public.management_report_documents(
  id,management_report_id,document_type,storage_path,file_name,mime_type,file_size,
  preview_snapshot,snapshot_schema_version,generated_by
) values
('99100000-0000-4000-8700-000000000001','99100000-0000-4000-8600-000000000001',
 'management_report_draft',
 'protected-persons/99100000-0000-4000-8100-000000000001/management-reports/99100000-0000-4000-8600-000000000001/management-report-draft.pdf',
 'projet.pdf','application/pdf',100,
 '{"report":{"id":"99100000-0000-4000-8600-000000000001","protected_person_id":"99100000-0000-4000-8100-000000000001","report_year":"2026","period_start":"2026-01-01","period_end":"2026-12-31","status":"generated"},"person":{"id":"99100000-0000-4000-8100-000000000001"},"amount":100}',
 1,'99100000-0000-4000-8000-000000000001'),
('99100000-0000-4000-8700-000000000002','99100000-0000-4000-8600-000000000002',
 'management_report_draft',
 'protected-persons/99100000-0000-4000-8100-000000000001/management-reports/99100000-0000-4000-8600-000000000002/management-report-draft.pdf',
 'projet.pdf','application/pdf',100,
 '{"report":{"id":"99100000-0000-4000-8600-000000000002","protected_person_id":"99100000-0000-4000-8100-000000000001","report_year":"2027","period_start":"2027-01-01","period_end":"2027-12-31","status":"generated"},"person":{"id":"99100000-0000-4000-8100-000000000001"},"amount":100}',
 1,'99100000-0000-4000-8000-000000000001'),
('99100000-0000-4000-8700-000000000004','99100000-0000-4000-8600-000000000004',
 'management_report_draft',
 'protected-persons/99100000-0000-4000-8100-000000000001/management-reports/99100000-0000-4000-8600-000000000004/management-report-draft.pdf',
 'projet.pdf','application/pdf',100,
 '{"report":{"id":"99100000-0000-4000-8600-000000000004","protected_person_id":"99100000-0000-4000-8100-000000000001","report_year":"2029","period_start":"2029-01-01","period_end":"2029-12-31","status":"generated"},"person":{"id":"99100000-0000-4000-8100-000000000001"},"amount":100}',
 2,'99100000-0000-4000-8000-000000000001'),
('99100000-0000-4000-8700-000000000005','99100000-0000-4000-8600-000000000005',
 'management_report_draft',
 'protected-persons/99100000-0000-4000-8100-000000000001/management-reports/99100000-0000-4000-8600-000000000005/management-report-draft.pdf',
 'projet.pdf','application/pdf',100,
 '{"report":{"id":"99100000-0000-4000-8600-000000000005","protected_person_id":"99100000-0000-4000-8100-000000000001","report_year":"2030","period_start":"2030-01-01","period_end":"2030-12-31","status":"generated"},"person":{"id":"99100000-0000-4000-8100-000000000001"},"amount":100}',
 1,'99100000-0000-4000-8000-000000000001'),
('99100000-0000-4000-8700-000000000006','99100000-0000-4000-8600-000000000006',
 'management_report_draft',
 'protected-persons/99100000-0000-4000-8100-000000000001/management-reports/99100000-0000-4000-8600-000000000006/management-report-draft.pdf',
 'projet.pdf','application/pdf',100,
 '{"report":{"id":"99100000-0000-4000-8600-000000000006","protected_person_id":"99100000-0000-4000-8100-000000000001","report_year":"2031","period_start":"2031-01-01","period_end":"2031-12-31","status":"generated"},"person":{"id":"99100000-0000-4000-8100-000000000001"},"amount":100}',
 1,'99100000-0000-4000-8000-000000000001');

insert into storage.objects(id,bucket_id,name,owner,owner_id,metadata,version) values
('99100000-0000-4000-8800-000000000001','management-reports',
 'protected-persons/99100000-0000-4000-8100-000000000001/management-reports/99100000-0000-4000-8600-000000000001/management-report.pdf',
 '99100000-0000-4000-8000-000000000001','99100000-0000-4000-8000-000000000001',
 '{"size":100,"mimetype":"application/pdf"}','v1'),
('99100000-0000-4000-8800-000000000002','management-reports',
 'protected-persons/99100000-0000-4000-8100-000000000001/management-reports/99100000-0000-4000-8600-000000000002/management-report.pdf',
 '99100000-0000-4000-8000-000000000001','99100000-0000-4000-8000-000000000001',
 '{"size":100,"mimetype":"application/pdf"}','v1'),
('99100000-0000-4000-8800-000000000005','management-reports',
 'protected-persons/99100000-0000-4000-8100-000000000001/management-reports/99100000-0000-4000-8600-000000000005/management-report.pdf',
 '99100000-0000-4000-8000-000000000001','99100000-0000-4000-8000-000000000001',
 '{"size":100,"mimetype":"application/pdf"}','v1'),
('99100000-0000-4000-8800-000000000006','management-reports',
 'protected-persons/99100000-0000-4000-8100-000000000001/management-reports/99100000-0000-4000-8600-000000000006/management-report-draft.pdf',
 '99100000-0000-4000-8000-000000000001','99100000-0000-4000-8000-000000000001',
 '{"size":100,"mimetype":"application/pdf"}','v1');

set local role authenticated;
select set_config('request.jwt.claim.sub','99100000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99100000-0000-4000-8000-000000000001","role":"authenticated"}',true);

select extensions.lives_ok(
  $$select public.finalize_management_report(
    '99100000-0000-4000-8600-000000000001',
    'protected-persons/99100000-0000-4000-8100-000000000001/management-reports/99100000-0000-4000-8600-000000000001/management-report.pdf',
    'definitif.pdf','application/pdf',100,
    '{"report":{"id":"99100000-0000-4000-8600-000000000001","protected_person_id":"99100000-0000-4000-8100-000000000001","report_year":"2026","period_start":"2026-01-01","period_end":"2026-12-31","status":"finalized"},"person":{"id":"99100000-0000-4000-8100-000000000001"},"amount":100}',1
  )$$,
  'la RPC historique accepte le snapshot exact du projet'
);
select extensions.is(
  (select status::text from public.management_reports
   where id='99100000-0000-4000-8600-000000000001'),
  'finalized','le compte exact est finalisé'
);
select extensions.is(
  (select preview_snapshot ->> 'amount' from public.management_report_documents
   where management_report_id='99100000-0000-4000-8600-000000000001'
     and document_type='management_report'),
  '100','les données métier du projet sont conservées'
);

select extensions.throws_ok(
  $$select public.finalize_management_report(
    '99100000-0000-4000-8600-000000000002',
    'protected-persons/99100000-0000-4000-8100-000000000001/management-reports/99100000-0000-4000-8600-000000000002/management-report.pdf',
    'definitif.pdf','application/pdf',100,
    '{"report":{"id":"99100000-0000-4000-8600-000000000002","protected_person_id":"99100000-0000-4000-8100-000000000001","report_year":"2027","period_start":"2027-01-01","period_end":"2027-12-31","status":"finalized"},"person":{"id":"99100000-0000-4000-8100-000000000001"},"amount":999}',1
  )$$,
  '23514','Le snapshot définitif diffère du projet généré.',
  'la RPC historique refuse un snapshot divergent'
);
select extensions.is(
  (select status::text from public.management_reports
   where id='99100000-0000-4000-8600-000000000002'),
  'generated','un échec conserve le projet généré'
);
select extensions.is(
  (select count(*) from public.management_report_documents
   where management_report_id='99100000-0000-4000-8600-000000000002'
     and document_type='management_report'),
  0::bigint,'aucune métadonnée finale divergente n’est conservée'
);

reset role;

select extensions.throws_ok(
  $$insert into public.management_report_documents(
      management_report_id,document_type,storage_path,file_name,mime_type,file_size,
      preview_snapshot,snapshot_schema_version,generated_by
    ) values (
      '99100000-0000-4000-8600-000000000003','management_report','missing/final.pdf',
      'final.pdf','application/pdf',100,'{"report":{"status":"finalized"}}',1,
      '99100000-0000-4000-8000-000000000001'
    )$$,
  '23514','Le snapshot du projet est absent.',
  'un projet sans snapshot enregistré ne peut pas être finalisé'
);
select extensions.throws_ok(
  $$insert into public.management_report_documents(
      management_report_id,document_type,storage_path,file_name,mime_type,file_size,
      preview_snapshot,snapshot_schema_version,generated_by
    ) values (
      '99100000-0000-4000-8600-000000000004','management_report','incompatible/final.pdf',
      'final.pdf','application/pdf',100,
      '{"report":{"id":"99100000-0000-4000-8600-000000000004","status":"finalized"}}',2,
      '99100000-0000-4000-8000-000000000001'
    )$$,
  '23514','La version du snapshot du projet est incompatible.',
  'un snapshot de version incompatible est refusé'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','99100000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99100000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select set_config(
  'test.management_report_operation_id',
  public.begin_management_report_document_operation(
    '99100000-0000-4000-8100-000000000001',
    '99100000-0000-4000-8600-000000000006',
    'finalize','99100000-0000-4000-8400-000000000006'
  )::text,true
);
select public.start_document_operation(
  current_setting('test.management_report_operation_id')::uuid,1
);
reset role;
select set_config(
  'test.management_report_destination_target_id',
  (select target.id::text from public.document_operation_targets target
   where target.operation_id=current_setting('test.management_report_operation_id')::uuid
     and target.target_role='destination'),true
);
select set_config(
  'test.management_report_source_target_id',
  (select target.id::text from public.document_operation_targets target
   where target.operation_id=current_setting('test.management_report_operation_id')::uuid
     and target.target_role='source'),true
);
insert into storage.objects(id,bucket_id,name,owner,owner_id,metadata,version) values
('99100000-0000-4000-8800-000000000007','management-reports',
 'protected-persons/99100000-0000-4000-8100-000000000001/management-reports/99100000-0000-4000-8600-000000000006/management-report.pdf',
 '99100000-0000-4000-8000-000000000001','99100000-0000-4000-8000-000000000001',
 '{"size":100,"mimetype":"application/pdf"}','v1');
select set_config('storage.allow_delete_query','true',true);
delete from storage.objects where id='99100000-0000-4000-8800-000000000006';
set local role authenticated;
select set_config('request.jwt.claim.sub','99100000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"99100000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.record_document_operation_target_applied(
  current_setting('test.management_report_operation_id')::uuid,
  current_setting('test.management_report_destination_target_id')::uuid,2,0
);
select public.record_document_operation_target_applied(
  current_setting('test.management_report_operation_id')::uuid,
  current_setting('test.management_report_source_target_id')::uuid,3,0
);
select extensions.throws_ok(
  format(
    'select public.finalize_management_report_document_operation(%L,4,%L,%L,100,%L::jsonb,1)',
    current_setting('test.management_report_operation_id')::uuid,
    'definitif.pdf','application/pdf',
    '{"report":{"id":"99100000-0000-4000-8600-000000000006","protected_person_id":"99100000-0000-4000-8100-000000000001","report_year":"2031","period_start":"2031-01-01","period_end":"2031-12-31","status":"finalized"},"person":{"id":"99100000-0000-4000-8100-000000000001"},"amount":999}'
  ),
  '23514','Le snapshot définitif diffère du projet généré.',
  'la RPC durable refuse elle aussi un snapshot divergent'
);
reset role;
select extensions.is(
  (select status::text from public.management_reports
   where id='99100000-0000-4000-8600-000000000006'),
  'generated','le refus durable conserve le statut du projet'
);

select extensions.throws_ok(
  $$insert into public.management_report_documents(
      management_report_id,document_type,storage_path,file_name,mime_type,file_size,
      preview_snapshot,snapshot_schema_version,generated_by
    ) values (
      '99100000-0000-4000-8600-000000000007','management_report','historique/final.pdf',
      'historique.pdf','application/pdf',100,
      '{"report":{"status":"finalized"},"historical":true}',1,
      '99100000-0000-4000-8000-000000000001'
    )$$,
  '23514','Un document définitif ne peut être créé que depuis un projet généré.',
  'un rapport déjà finalisé ne permet aucune nouvelle insertion définitive'
);
select extensions.throws_ok(
  $$insert into public.management_report_documents(
      management_report_id,document_type,storage_path,file_name,mime_type,file_size,
      preview_snapshot,snapshot_schema_version,generated_by
    ) values (
      '99100000-0000-4000-8600-000000000008','management_report','ready/final.pdf',
      'ready.pdf','application/pdf',100,
      '{"report":{"status":"finalized"}}',1,
      '99100000-0000-4000-8000-000000000001'
    )$$,
  '23514','Un document définitif ne peut être créé que depuis un projet généré.',
  'un rapport prêt mais sans projet généré ne permet aucune insertion définitive'
);
select extensions.throws_ok(
  $$update public.management_report_documents
    set preview_snapshot=jsonb_set(preview_snapshot,'{amount}','999'::jsonb)
    where id='99100000-0000-4000-8700-000000000005'$$,
  'P0001','Un document de compte de gestion ne peut pas être modifié.',
  'le snapshot d’un document existant reste immuable'
);
select extensions.throws_ok(
  $$update public.management_report_documents
    set document_type='management_report'
    where id='99100000-0000-4000-8700-000000000005'$$,
  'P0001','Un document de compte de gestion ne peut pas être modifié.',
  'le type documentaire ne peut pas contourner la garde par update'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','99100000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"99100000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select extensions.throws_ok(
  $$select public.finalize_management_report(
    '99100000-0000-4000-8600-000000000005',
    'protected-persons/99100000-0000-4000-8100-000000000001/management-reports/99100000-0000-4000-8600-000000000005/management-report.pdf',
    'definitif.pdf','application/pdf',100,
    '{"report":{"id":"99100000-0000-4000-8600-000000000005","protected_person_id":"99100000-0000-4000-8100-000000000001","report_year":"2030","period_start":"2030-01-01","period_end":"2030-12-31","status":"finalized"},"person":{"id":"99100000-0000-4000-8100-000000000001"},"amount":100}',1
  )$$,
  'P0001','Compte de gestion introuvable ou accès refusé.',
  'un lecteur ne peut pas finaliser le projet'
);
reset role;

select extensions.is(
  (select count(*) from public.management_report_documents
   where management_report_id='99100000-0000-4000-8600-000000000005'
     and document_type='management_report'),
  0::bigint,'le refus du lecteur ne crée aucun document final'
);

select * from extensions.finish();
rollback;
