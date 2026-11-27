begin;
create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

create function pg_temp.bank_id(value text) returns uuid language sql immutable as $$
  select md5('stripe-02d-bank:' || value)::uuid
$$;

insert into auth.users(id,email,raw_user_meta_data)
values (pg_temp.bank_id('owner'),'staged-bank-owner@example.test','{}');
update public.application_user_authorizations set status='active',status_changed_at=now(),
  account_mode='autonomous',registration_intent='autonomous',autonomous_registration_status='active'
where user_id=pg_temp.bank_id('owner');
insert into public.protected_persons(id,owner_id,first_name,last_name)
values (pg_temp.bank_id('person'),pg_temp.bank_id('owner'),'Fixture','Statement');
insert into public.financial_accounts(id,protected_person_id,account_type,institution_name,account_name,initial_balance,initial_balance_date,status)
values (pg_temp.bank_id('account'),pg_temp.bank_id('person'),'checking','Fixture','Compte',0,'2026-01-01','active');

create function pg_temp.payload(label text) returns jsonb language sql immutable as $$
  select jsonb_build_object('startDate','2026-01-01','endDate','2026-01-31','balance',0,
    'fileName',label || '.pdf','sha256',repeat('a',64),'size',100)
$$;
create temp table staged_result(label text primary key, id uuid, storage_path text, state text);
grant all on staged_result to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub',pg_temp.bank_id('owner')::text,true);
insert into staged_result select 'new', edit.* from public.reserve_unreconciled_bank_statement_file(
  pg_temp.bank_id('person'),pg_temp.bank_id('account'),pg_temp.bank_id('statement'),null,pg_temp.bank_id('request'),pg_temp.payload('first')) edit;
select extensions.is((select count(*) from public.bank_statements where id=pg_temp.bank_id('statement')),0::bigint,
  'la réservation n’enregistre aucun relevé sans PDF publié');
select extensions.throws_ok($$select public.publish_unreconciled_bank_statement_file((select id from staged_result where label='new'))$$,
  '55000','Le PDF vérifié est absent.','un fichier non vérifié ne peut pas être publié');
insert into storage.objects(id,bucket_id,name,owner_id,metadata,version)
select pg_temp.bank_id('object'), 'bank-statements',storage_path,auth.uid()::text,
  '{"size":100,"mimetype":"application/pdf"}','one' from staged_result where label='new';
select extensions.is((select count(*) from storage.objects where bucket_id='bank-statements' and id=pg_temp.bank_id('object')),
  0::bigint,'le fichier candidat n’est pas lisible directement par son auteur');
select extensions.ok(not has_function_privilege('authenticated','public.verify_staged_bank_statement_file(uuid,uuid,text,text)','EXECUTE'),
  'la vérification d’empreinte est réservée au serveur');
reset role;

select extensions.ok(public.verify_staged_bank_statement_file((select id from staged_result where label='new'),
  pg_temp.bank_id('object'),'one',repeat('a',64)),'le serveur vérifie la version Storage exacte');
set local role authenticated;
select extensions.lives_ok($$select public.publish_unreconciled_bank_statement_file((select id from staged_result where label='new'))$$,
  'le dépôt vérifié crée le relevé');
select extensions.lives_ok($$select public.publish_unreconciled_bank_statement_file((select id from staged_result where label='new'))$$,
  'le rejeu d’une publication réussie est idempotent');
select extensions.is((select original_file_name from public.get_bank_statement_document_history(pg_temp.bank_id('statement')) where is_active),
  'first.pdf','la route peut résoudre le PDF publié via le catalogue');
select extensions.is((select storage_path from public.bank_statements where id=pg_temp.bank_id('statement')),
  (select storage_path from staged_result where label='new'), 'la projection historique résout aussi les nouveaux PDF');
insert into staged_result select 'replacement', edit.* from public.reserve_unreconciled_bank_statement_file(
  pg_temp.bank_id('person'),pg_temp.bank_id('account'),pg_temp.bank_id('statement'),
  (select updated_at from public.bank_statements where id=pg_temp.bank_id('statement')),
  pg_temp.bank_id('replace'),pg_temp.payload('second')) edit;
select extensions.throws_ok($$select public.reserve_unreconciled_bank_statement_file(
  pg_temp.bank_id('person'),pg_temp.bank_id('account'),pg_temp.bank_id('statement'),
  (select updated_at from public.bank_statements where id=pg_temp.bank_id('statement')),
  pg_temp.bank_id('concurrent'),pg_temp.payload('third'))$$,
  '40001','Un dépôt est déjà en cours pour ce relevé.','deux remplacements ne peuvent pas détenir une réservation simultanée');
select extensions.is((select original_file_name from public.get_bank_statement_document_history(pg_temp.bank_id('statement')) where is_active),
  'first.pdf','l’ancien PDF reste la version active pendant le remplacement');
insert into storage.objects(id,bucket_id,name,owner_id,metadata,version)
select pg_temp.bank_id('replacement-object'), 'bank-statements',storage_path,auth.uid()::text,
  '{"size":100,"mimetype":"application/pdf"}','two' from staged_result where label='replacement';
reset role;
select extensions.ok(public.verify_staged_bank_statement_file((select id from staged_result where label='replacement'),
  pg_temp.bank_id('replacement-object'),'two',repeat('a',64)),'le candidat de remplacement est vérifié');

insert into public.account_trials(user_id,terms_version,terms_accepted_at,started_at,ends_at,deletion_eligible_at)
values (pg_temp.bank_id('owner'),'fixture',now()-interval '30 days',now()-interval '30 days',now(),now()+interval '30 days');
update public.billing_runtime_config set commercial_access_enabled=true;
set local role authenticated;
select extensions.throws_ok($$select public.publish_unreconciled_bank_statement_file((select id from staged_result where label='replacement'))$$,
  '42501','Relevé introuvable ou accès refusé.','J30 refuse la publication avec la même identité');
select extensions.throws_ok($$select public.delete_unreconciled_bank_statement(pg_temp.bank_id('person'),pg_temp.bank_id('account'),pg_temp.bank_id('statement'))$$,
  '42501','Relevé introuvable ou accès refusé.','J30 refuse la suppression avec la même identité');
reset role;
select extensions.is((select count(*) from storage.objects where id=pg_temp.bank_id('object')),1::bigint,
  'l’ancien objet demeure physiquement présent à J30');
select extensions.is((select count(*) from public.bank_statement_file_retirements),0::bigint,
  'les refus n’inscrivent aucun ancien PDF au nettoyage');
update public.billing_runtime_config set commercial_access_enabled=false;
set local role authenticated;
select extensions.lives_ok($$select public.publish_unreconciled_bank_statement_file((select id from staged_result where label='replacement'))$$,
  'le rétablissement permet la publication du candidat');
select extensions.is((select active_revision from public.get_bank_statement_document_history(pg_temp.bank_id('statement')) where is_active),
  2::bigint,'le remplacement avance la révision active');
reset role;
select extensions.is(public.reconcile_unpublished_bank_statement_file((select id from staged_result where label='replacement')),
  'published','une réponse perdue ne fait pas retirer le PDF publié');
select extensions.is((select count(*) from public.list_retired_bank_statement_files(pg_temp.bank_id('statement'))),1::bigint,
  'seul l’ancien fichier non référencé peut être nettoyé');
select extensions.is((select count(*) from storage.objects where id in (pg_temp.bank_id('object'),pg_temp.bank_id('replacement-object'))),
  2::bigint,'la publication SQL ne supprime aucun octet');
set local role authenticated;
select extensions.lives_ok($$select public.delete_unreconciled_bank_statement(pg_temp.bank_id('person'),pg_temp.bank_id('account'),pg_temp.bank_id('statement'))$$,
  'le relevé non figé peut être supprimé');
select extensions.lives_ok($$select public.delete_unreconciled_bank_statement(pg_temp.bank_id('person'),pg_temp.bank_id('account'),pg_temp.bank_id('statement'))$$,
  'la suppression déjà confirmée peut être rejouée');
reset role;
select extensions.is((select count(*) from public.list_retired_bank_statement_files(pg_temp.bank_id('statement'))),2::bigint,
  'le nettoyage est enregistré pour chaque objet obsolète');
select extensions.is((select count(*) from public.bank_statements where id=pg_temp.bank_id('statement')),0::bigint,
  'la suppression métier reste physique en base');

set local role authenticated;
insert into public.bank_statements(id,financial_account_id,statement_end_date,statement_balance,storage_path,created_by)
values(pg_temp.bank_id('reconciled-statement'),pg_temp.bank_id('account'),'2026-02-28',0,
  'protected-persons/' || pg_temp.bank_id('person') || '/accounts/' || pg_temp.bank_id('account') ||
    '/statements/' || pg_temp.bank_id('reconciled-statement') || '/statement',auth.uid());
insert into public.bank_reconciliations(id,bank_statement_id,created_by)
values(pg_temp.bank_id('reconciliation'),pg_temp.bank_id('reconciled-statement'),auth.uid());
insert into staged_result select 'recon-race', edit.* from public.reserve_unreconciled_bank_statement_file(
  pg_temp.bank_id('person'),pg_temp.bank_id('account'),pg_temp.bank_id('reconciled-statement'),
  (select updated_at from public.bank_statements where id=pg_temp.bank_id('reconciled-statement')),
  pg_temp.bank_id('recon-race-request'),
  pg_temp.payload('third') || '{"startDate":"2026-02-01","endDate":"2026-02-28"}'::jsonb) edit;
select extensions.lives_ok($$select public.validate_bank_reconciliation(pg_temp.bank_id('reconciliation'))$$,
  'un rapprochement peut être validé pendant un dépôt non publié');
select extensions.throws_ok($$select public.publish_unreconciled_bank_statement_file((select id from staged_result where label='recon-race'))$$,
  '55000','Le document du relevé est figé.','la validation gagnante empêche la publication réservée');
select extensions.is((select status::text from public.bank_reconciliations where id=pg_temp.bank_id('reconciliation')),
  'validated','le dépôt concurrent ne modifie pas le rapprochement validé');
reset role;

select * from extensions.finish();
rollback;
