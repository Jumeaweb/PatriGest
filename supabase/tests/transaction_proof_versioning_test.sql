begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(37);

select extensions.has_table('public','transaction_proof_documents','les identites documentaires existent');
select extensions.has_table('public','transaction_proof_versions','les versions physiques existent');
select extensions.has_table('public','transaction_proof_replacement_retirements','le contrat de retrait securise existe');
select extensions.has_column('public','proof_reference_assignments','id','les episodes de depense ont une identite');
select extensions.has_column('public','transaction_proof_versions','availability_status','une version peut etre signalee indisponible');
select extensions.ok(not has_table_privilege('authenticated','public.transaction_proof_versions','INSERT'),
  'les versions ne sont pas inscriptibles directement');
select extensions.ok(has_table_privilege('authenticated','public.transaction_proof_versions','SELECT'),
  'les versions sont consultables sous RLS');
select extensions.ok(position('transaction_proof_versions' in pg_get_functiondef(
  'public.get_administrative_document_inventory(integer,text,text,text)'::regprocedure))>0,
  'l inventaire administratif reconnait les versions conservees');
select extensions.ok((select is_canonical from public.resolve_canonical_document_storage_path(
  'transaction-proofs',
  'protected-persons/97000000-0000-4000-8100-000000000001/transactions/97000000-0000-4000-8500-000000000001/proofs/97000000-0000-4000-8800-000000000001/versions/97000000-0000-4000-8900-000000000001'
)),'le resolveur reconnait le chemin versionne canonique');
select extensions.is((select count(*) from pg_policies
  where schemaname='storage' and tablename='objects'
    and policyname in ('transaction_proofs_insert_manage','transaction_proofs_update_manage','transaction_proofs_delete_manage')
    and (coalesce(qual,'')||coalesce(with_check,'')) ilike '%cancelled_at IS NULL%'),3::bigint,
  'les trois mutations Storage legacy refusent les transactions annulees');
select extensions.ok(position('cancelled_at' in pg_get_functiondef(
  'public.begin_transaction_proof_document_operation(uuid,uuid,text,uuid)'::regprocedure))>0,
  'la reservation durable refuse aussi une transaction annulee');

insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('00000000-0000-0000-0000-000000000000','97000000-0000-4000-8000-000000000001','authenticated','authenticated','proof-owner@example.test','test',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','97000000-0000-4000-8000-000000000002','authenticated','authenticated','proof-reader@example.test','test',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','97000000-0000-4000-8000-000000000003','authenticated','authenticated','proof-outsider@example.test','test',now(),'{}','{}',now(),now());

update public.application_user_authorizations set status='active',status_changed_at=now()
where user_id::text like '97000000-0000-4000-8000-00000000000%';
update public.profiles set first_name='Alice',last_name='Preuve'
where id='97000000-0000-4000-8000-000000000001';

insert into public.protected_persons(id,owner_id,first_name,last_name) values
('97000000-0000-4000-8100-000000000001','97000000-0000-4000-8000-000000000001','Dossier','Preuves');
insert into public.protected_person_access(id,protected_person_id,user_id,role,invited_by) values
('97000000-0000-4000-8200-000000000001','97000000-0000-4000-8100-000000000001',
 '97000000-0000-4000-8000-000000000002','read_only','97000000-0000-4000-8000-000000000001');
insert into public.financial_accounts(id,protected_person_id,account_type,institution_name,
  account_name,initial_balance,initial_balance_date,status) values
('97000000-0000-4000-8300-000000000001','97000000-0000-4000-8100-000000000001',
 'checking','Banque','Compte',0,'2026-01-01','active');

set local role authenticated;
select set_config('request.jwt.claim.sub','97000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"97000000-0000-4000-8000-000000000001","role":"authenticated"}',true);

select extensions.is((public.create_financial_transaction(
  '97000000-0000-4000-8100-000000000001','97000000-0000-4000-8300-000000000001',
  '2026-10-01','expense','Conversions justificatif',25,null,null,null,null,
  '97000000-0000-4000-8600-000000000001')->>'revision')::bigint,1::bigint,
  'la depense A est creee');

insert into public.transaction_documents(id,transaction_id,storage_path,file_name,mime_type,file_size,created_by)
select '97000000-0000-4000-8700-000000000001',id,
  'protected-persons/97000000-0000-4000-8100-000000000001/transactions/'||id||'/proof',
  'preuve-a.pdf','application/pdf',100,'97000000-0000-4000-8000-000000000001'
from public.transactions where label='Conversions justificatif';

select extensions.is((public.correct_financial_transaction(
  '97000000-0000-4000-8100-000000000001',(select id from public.transactions where label='Conversions justificatif'),1,
  '97000000-0000-4000-8300-000000000001','2026-10-01','income','Conversions justificatif',25,
  null,null,null,null,'Conversion A','97000000-0000-4000-8600-000000000002')->>'revision')::bigint,
  2::bigint,'depense A vers recette conserve le document');

reset role;
select extensions.is((select count(*) from public.transaction_proof_documents where lifecycle_status='historical'),1::bigint,
  'le justificatif A devient historique');
select extensions.is((select count(*) from public.transaction_proof_versions where path_kind='legacy'),1::bigint,
  'le chemin legacy est conserve comme version');
select extensions.is((select count(*) from public.transaction_document_history),1::bigint,
  'le detachement A est audite');
select extensions.ok((select ended_at is not null from public.proof_reference_assignments
  where transaction_id=(select id from public.transactions where label='Conversions justificatif')),
  'l episode A est cloture');

set local role authenticated;
select set_config('request.jwt.claim.sub','97000000-0000-4000-8000-000000000001',true);
select extensions.is((public.correct_financial_transaction(
  '97000000-0000-4000-8100-000000000001',(select id from public.transactions where label='Conversions justificatif'),2,
  '97000000-0000-4000-8300-000000000001','2026-10-01','expense','Conversions justificatif',25,
  null,null,null,null,'Nouvel episode B','97000000-0000-4000-8600-000000000003')->>'revision')::bigint,
  3::bigint,'recette vers depense cree l episode B');

reset role;
select extensions.is((select count(distinct proof_reference) from public.proof_reference_assignments
  where transaction_id=(select id from public.transactions where label='Conversions justificatif')),2::bigint,
  'les references A et B sont distinctes');

insert into public.transaction_proof_documents(id,protected_person_id,transaction_id,
  expense_reference_assignment_id,proof_reference,lifecycle_status,created_by)
select '97000000-0000-4000-8800-000000000001','97000000-0000-4000-8100-000000000001',transaction.id,
  assignment.id,assignment.proof_reference,'current','97000000-0000-4000-8000-000000000001'
from public.transactions transaction join public.proof_reference_assignments assignment
  on assignment.transaction_id=transaction.id and assignment.ended_at is null
where transaction.label='Conversions justificatif';
insert into public.transaction_proof_versions(id,proof_document_id,version_number,storage_path,path_kind,
  lifecycle_state,availability_status,file_name,mime_type,file_size,created_by)
values('97000000-0000-4000-8900-000000000001','97000000-0000-4000-8800-000000000001',1,
  public.build_transaction_proof_version_path('97000000-0000-4000-8100-000000000001',
    (select id from public.transactions where label='Conversions justificatif'),
    '97000000-0000-4000-8800-000000000001','97000000-0000-4000-8900-000000000001'),
  'versioned','current','missing','preuve-b.pdf','application/pdf',120,'97000000-0000-4000-8000-000000000001');

set local role authenticated;
select set_config('request.jwt.claim.sub','97000000-0000-4000-8000-000000000001',true);
select extensions.is((public.correct_financial_transaction(
  '97000000-0000-4000-8100-000000000001',(select id from public.transactions where label='Conversions justificatif'),3,
  '97000000-0000-4000-8300-000000000001','2026-10-01','income','Conversions justificatif',25,
  null,null,null,null,'Conversion B','97000000-0000-4000-8600-000000000004')->>'revision')::bigint,
  4::bigint,'depense B vers recette conserve sa version propre');

reset role;
select extensions.is((select count(*) from public.transaction_document_history),2::bigint,
  'les deux detachements sont conserves sans collision');
select extensions.is((select count(distinct storage_path) from public.transaction_proof_versions),2::bigint,
  'les chemins physiques A et B sont distincts');
select extensions.ok((select availability_status='missing' from public.transaction_proof_versions
  where id='97000000-0000-4000-8900-000000000001'),
  'un document historique manquant reste visible comme indisponible');

set local role authenticated;
select set_config('request.jwt.claim.sub','97000000-0000-4000-8000-000000000001',true);
select public.correct_financial_transaction(
  '97000000-0000-4000-8100-000000000001',(select id from public.transactions where label='Conversions justificatif'),4,
  '97000000-0000-4000-8300-000000000001','2026-10-01','expense','Conversions justificatif',25,
  null,null,null,null,'Episode sans document','97000000-0000-4000-8600-000000000005');
select public.correct_financial_transaction(
  '97000000-0000-4000-8100-000000000001',(select id from public.transactions where label='Conversions justificatif'),5,
  '97000000-0000-4000-8300-000000000001','2026-10-01','income','Conversions justificatif',25,
  null,null,null,null,'Fin episode sans document','97000000-0000-4000-8600-000000000006');
select public.correct_financial_transaction(
  '97000000-0000-4000-8100-000000000001',(select id from public.transactions where label='Conversions justificatif'),6,
  '97000000-0000-4000-8300-000000000001','2026-10-01','expense','Conversions justificatif',25,
  null,null,null,null,'Episode D','97000000-0000-4000-8600-000000000007');

reset role;
select extensions.is((select count(distinct proof_reference) from public.proof_reference_assignments
  where transaction_id=(select id from public.transactions where label='Conversions justificatif')),4::bigint,
  'les conversions nombreuses ne reutilisent aucune reference');

set local role authenticated;
select set_config('request.jwt.claim.sub','97000000-0000-4000-8000-000000000001',true);
select extensions.throws_ok($$insert into public.transaction_documents(
  transaction_id,storage_path,file_name,mime_type,file_size,created_by)
select id,'protected-persons/97000000-0000-4000-8100-000000000001/transactions/'||id||'/proof',
  'reutilisation.pdf','application/pdf',99,'97000000-0000-4000-8000-000000000001'
from public.transactions where label='Conversions justificatif'$$,'42501',null,
  'un chemin historique legacy ne peut pas etre reutilise');

reset role;
insert into public.document_operations(id,protected_person_id,initiated_by,initiator_subject_id,
  workflow,business_entity_type,business_entity_id,client_request_id,state,target_signature)
select '97000000-0000-4000-8a00-000000000001','97000000-0000-4000-8100-000000000001',
  '97000000-0000-4000-8000-000000000001','97000000-0000-4000-8000-000000000001',
  'transaction_proof_create','transaction',id,'97000000-0000-4000-8b00-000000000001','reserved','[]'::jsonb
from public.transactions where label='Conversions justificatif';
set local role authenticated;
select set_config('request.jwt.claim.sub','97000000-0000-4000-8000-000000000001',true);
select extensions.throws_ok($$select public.correct_financial_transaction(
  '97000000-0000-4000-8100-000000000001',(select id from public.transactions where label='Conversions justificatif'),7,
  '97000000-0000-4000-8300-000000000001','2026-10-01','income','Conversions justificatif',25,
  null,null,null,null,'Conflit upload','97000000-0000-4000-8600-000000000008')$$,
  '55000','Une opération documentaire est déjà en cours pour cette transaction.',
  'une reservation active bloque la conversion');

reset role;
delete from public.document_operations where id='97000000-0000-4000-8a00-000000000001';
insert into public.transaction_documents(id,transaction_id,storage_path,file_name,mime_type,file_size,created_by)
select '97000000-0000-4000-8700-000000000002',id,
  'protected-persons/97000000-0000-4000-8100-000000000001/transactions/'||id||
  '/proofs/97000000-0000-4000-8800-000000000002/versions/97000000-0000-4000-8900-000000000002',
  'preuve-courante.pdf','application/pdf',50,'97000000-0000-4000-8000-000000000001'
from public.transactions where label='Conversions justificatif';
set local role authenticated;
select set_config('request.jwt.claim.sub','97000000-0000-4000-8000-000000000001',true);
select extensions.is((public.cancel_financial_transaction(
  '97000000-0000-4000-8100-000000000001',(select id from public.transactions where label='Conversions justificatif'),7,
  'Annulation conserve les historiques','97000000-0000-4000-8600-000000000009')->>'revision')::bigint,
  8::bigint,'l annulation reste possible hors operation documentaire');
select extensions.throws_ok($$insert into public.transaction_documents(
  transaction_id,storage_path,file_name,mime_type,file_size,created_by)
select id,'chemin-test','interdit.pdf','application/pdf',10,'97000000-0000-4000-8000-000000000001'
from public.transactions where label='Conversions justificatif'$$,'55000',
  'Une opération annulée ne peut plus recevoir, remplacer ou supprimer de justificatif.',
  'une transaction annulee refuse un nouveau justificatif');
select extensions.lives_ok($$update public.transaction_documents set file_name='modifie.pdf'
  where id='97000000-0000-4000-8700-000000000002'$$,
  'la RLS traite sans erreur une tentative de remplacement interdite');
select extensions.is((select file_name from public.transaction_documents
  where id='97000000-0000-4000-8700-000000000002'),'preuve-courante.pdf',
  'une transaction annulee refuse le remplacement du justificatif');
select extensions.throws_ok($$delete from public.transaction_documents
  where id='97000000-0000-4000-8700-000000000002'$$,'42501',null,
  'une transaction annulee refuse la suppression du justificatif');

select set_config('request.jwt.claim.sub','97000000-0000-4000-8000-000000000002',true);
select extensions.is((select count(*) from public.transaction_proof_versions),2::bigint,
  'le lecteur du dossier consulte les versions historiques');
select set_config('request.jwt.claim.sub','97000000-0000-4000-8000-000000000003',true);
select extensions.is((select count(*) from public.transaction_proof_versions),0::bigint,
  'un utilisateur exterieur ne consulte aucune version');

reset role;
insert into public.platform_administrators(user_id)
values('97000000-0000-4000-8000-000000000003');
insert into storage.objects(id,bucket_id,name,owner_id,metadata,version)
select '97000000-0000-4000-8c00-000000000001','transaction-proofs',storage_path,
  '97000000-0000-4000-8000-000000000001','{}'::jsonb,'version-test'
from public.transaction_proof_versions where id='97000000-0000-4000-8900-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub','97000000-0000-4000-8000-000000000003',true);
select extensions.ok(not exists(
  select 1 from jsonb_array_elements(public.get_administrative_document_inventory(
    100,null,'transaction_proof','catalog_object_without_business_reference'
  )->'items') item
  where item->>'inventoryKey'='transaction_proof:catalog_object_without_business_reference:97000000-0000-4000-8c00-000000000001'
),'une version historique cataloguee n est pas classee comme objet orphelin');

reset role;
select extensions.ok((select count(*)=2 from public.transaction_proof_versions),
  'l annulation ne purge aucun document historique');
select extensions.is((select count(*) from public.proof_reference_assignments
  where transaction_id=(select id from public.transactions where label='Conversions justificatif')),4::bigint,
  'les episodes restent traces apres annulation');
select extensions.ok((select count(*)=0 from public.transaction_proof_replacement_retirements),
  'aucune suppression physique n est activee par ce lot');

select * from extensions.finish();
rollback;
