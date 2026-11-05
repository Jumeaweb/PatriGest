begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(60);

select extensions.has_column('public','transactions','revision','les transactions portent une revision');
select extensions.has_column('public','transactions','cancelled_at','les transactions portent une annulation logique');
select extensions.has_column('public','transfers','revision','les virements portent une revision');
select extensions.has_table('public','transaction_changes','le journal des transactions existe');
select extensions.has_table('public','transfer_changes','le journal des virements existe');
select extensions.has_table('public','transaction_document_history','l historique documentaire existe');
select extensions.has_table('public','transaction_banking_impacts','les impacts bancaires existent');
select extensions.has_table('public','financial_operation_requests','les demandes idempotentes existent');
select extensions.has_function('public','create_financial_transaction',array['uuid','uuid','date','text','text','numeric','uuid','uuid','text','text','uuid'],'la RPC de creation existe');
select extensions.has_function('public','correct_financial_transaction',array['uuid','uuid','bigint','uuid','date','text','text','numeric','uuid','uuid','text','text','text','uuid'],'la RPC de correction existe');
select extensions.has_function('public','cancel_financial_transaction',array['uuid','uuid','bigint','text','uuid'],'la RPC d annulation existe');
select extensions.has_function('public','create_internal_transfer_v2',array['uuid','uuid','uuid','date','numeric','text','text','uuid'],'la RPC idempotente de virement existe');
select extensions.has_function('public','correct_internal_transfer',array['uuid','uuid','bigint','uuid','uuid','date','numeric','text','text','text','uuid'],'la RPC de correction de virement existe');
select extensions.has_function('public','cancel_internal_transfer_v2',array['uuid','uuid','bigint','text','uuid'],'la RPC d annulation de virement existe');
select extensions.ok(has_function_privilege('authenticated','public.correct_financial_transaction(uuid,uuid,bigint,uuid,date,text,text,numeric,uuid,uuid,text,text,text,uuid)','EXECUTE'),'authenticated peut appeler la correction controlee');
select extensions.ok(not has_function_privilege('anon','public.correct_financial_transaction(uuid,uuid,bigint,uuid,date,text,text,numeric,uuid,uuid,text,text,text,uuid)','EXECUTE'),'anon ne peut pas appeler la correction');
select extensions.ok(not has_function_privilege('service_role','public.cancel_internal_transfer_v2(uuid,uuid,bigint,text,uuid)','EXECUTE'),'service_role ne constitue pas une autorisation metier');
select extensions.ok(not has_table_privilege('authenticated','public.transaction_changes','INSERT'),'le journal ne peut pas etre alimente directement');
select extensions.ok(not has_table_privilege('authenticated','public.financial_operation_requests','SELECT'),'les cles techniques ne sont pas exposees');
select extensions.ok((select relrowsecurity from pg_class where oid='public.transaction_changes'::regclass),'RLS protege le journal');

insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('00000000-0000-0000-0000-000000000000','96000000-0000-4000-8000-000000000001','authenticated','authenticated','tx-owner@example.test','test',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','96000000-0000-4000-8000-000000000002','authenticated','authenticated','tx-manager@example.test','test',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','96000000-0000-4000-8000-000000000003','authenticated','authenticated','tx-reader@example.test','test',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','96000000-0000-4000-8000-000000000004','authenticated','authenticated','tx-outsider@example.test','test',now(),'{}','{}',now(),now());

update public.application_user_authorizations set status='active',status_changed_at=now()
where user_id::text like '96000000-0000-4000-8000-00000000000%';
update public.profiles set first_name='Alice',last_name='Audit' where id='96000000-0000-4000-8000-000000000001';

insert into public.protected_persons(id,owner_id,first_name,last_name) values
('96000000-0000-4000-8100-000000000001','96000000-0000-4000-8000-000000000001','Dossier','Transactions'),
('96000000-0000-4000-8100-000000000002','96000000-0000-4000-8000-000000000001','Dossier','Archive');
insert into public.protected_person_access(id,protected_person_id,user_id,role,invited_by) values
('96000000-0000-4000-8200-000000000001','96000000-0000-4000-8100-000000000001','96000000-0000-4000-8000-000000000002','manager','96000000-0000-4000-8000-000000000001'),
('96000000-0000-4000-8200-000000000002','96000000-0000-4000-8100-000000000001','96000000-0000-4000-8000-000000000003','read_only','96000000-0000-4000-8000-000000000001');

insert into public.financial_accounts(id,protected_person_id,account_type,institution_name,account_name,initial_balance,initial_balance_date,status) values
('96000000-0000-4000-8300-000000000001','96000000-0000-4000-8100-000000000001','checking','Banque','Compte A',0,'2024-01-01','active'),
('96000000-0000-4000-8300-000000000002','96000000-0000-4000-8100-000000000001','checking','Banque','Compte B',0,'2024-01-01','active'),
('96000000-0000-4000-8300-000000000003','96000000-0000-4000-8100-000000000002','checking','Banque','Compte archive',0,'2024-01-01','active');

insert into public.management_reports(id,protected_person_id,report_year,period_start,period_end,status,generated_at,created_by) values
('96000000-0000-4000-8500-000000000001','96000000-0000-4000-8100-000000000001',2026,'2026-01-01','2026-12-31','generated',now(),'96000000-0000-4000-8000-000000000001');

insert into public.transactions(id,financial_account_id,transaction_date,transaction_type,label,amount)
values
('96000000-0000-4000-8800-000000000002','96000000-0000-4000-8300-000000000001','2024-06-15','expense','Historique clos',25),
('96000000-0000-4000-8800-000000000003','96000000-0000-4000-8300-000000000001','2026-06-15','income','Historique ouvert',25);
insert into public.transfers(id,protected_person_id,source_account_id,destination_account_id,transfer_date,amount,label)
values('96000000-0000-4000-8900-000000000001','96000000-0000-4000-8100-000000000001','96000000-0000-4000-8300-000000000001','96000000-0000-4000-8300-000000000002','2024-07-01',30,'Virement clos');
insert into public.transactions(id,financial_account_id,transaction_date,transaction_type,label,amount,transfer_id) values
('96000000-0000-4000-8a00-000000000001','96000000-0000-4000-8300-000000000001','2024-07-01','transfer_out','Virement clos',30,'96000000-0000-4000-8900-000000000001'),
('96000000-0000-4000-8a00-000000000002','96000000-0000-4000-8300-000000000002','2024-07-01','transfer_in','Virement clos',30,'96000000-0000-4000-8900-000000000001');
insert into public.management_periods(id,protected_person_id,start_date,end_date,status,closed_at) values
('96000000-0000-4000-8400-000000000001','96000000-0000-4000-8100-000000000001','2024-01-01','2024-12-31','closed',now());

set local role authenticated;
select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"96000000-0000-4000-8000-000000000001","role":"authenticated"}',true);

select extensions.is((public.create_financial_transaction(
  '96000000-0000-4000-8100-000000000001','96000000-0000-4000-8300-000000000001','2026-09-01','expense','Achat',100,null,null,null,'Note','96000000-0000-4000-8600-000000000001'
)->>'revision')::bigint,1::bigint,'une transaction ordinaire est creee');
select extensions.is((public.create_financial_transaction(
  '96000000-0000-4000-8100-000000000001','96000000-0000-4000-8300-000000000001','2026-09-01','expense','Achat',100,null,null,null,'Note','96000000-0000-4000-8600-000000000001'
)->>'replayed')::boolean,true,'le rejeu identique ne duplique pas la transaction');
select extensions.is((select count(*) from public.transactions where label='Achat'),1::bigint,'une seule ligne existe apres rejeu');
select extensions.throws_ok($$select public.create_financial_transaction(
  '96000000-0000-4000-8100-000000000001','96000000-0000-4000-8300-000000000001','2026-09-01','expense','Autre',100,null,null,null,null,'96000000-0000-4000-8600-000000000001')$$,'23505','Cette clé d’idempotence correspond à une autre demande.','un rejeu divergent est refuse');
select extensions.throws_ok($$select public.create_financial_transaction(
  '96000000-0000-4000-8100-000000000001','96000000-0000-4000-8300-000000000001',current_date+1,'expense','Future',10,null,null,null,null,'96000000-0000-4000-8600-000000000002')$$,'22007','La date d’une opération réelle ne peut pas être future.','une date future est refusee');
select extensions.throws_ok($$select public.create_financial_transaction(
  '96000000-0000-4000-8100-000000000001','96000000-0000-4000-8300-000000000001','2024-06-01','expense','Close',10,null,null,null,null,'96000000-0000-4000-8600-000000000003')$$,'P0001','Cette date appartient à un exercice clôturé.','un exercice cloture est protege');
select extensions.throws_ok($$select public.correct_financial_transaction(
  '96000000-0000-4000-8100-000000000001','96000000-0000-4000-8800-000000000002',1,
  '96000000-0000-4000-8300-000000000001','2024-06-15','expense','Historique clos corrigé',25,null,null,null,null,'Catégorie corrigée','96000000-0000-4000-8600-000000000014')$$,
  'P0001','Cette opération appartient à un exercice clôturé.','une correction même non bancaire est interdite dans un exercice clos');
select extensions.throws_ok($$select public.cancel_financial_transaction(
  '96000000-0000-4000-8100-000000000001','96000000-0000-4000-8800-000000000002',1,'Annulation interdite','96000000-0000-4000-8600-000000000015')$$,
  'P0001','Cette opération appartient à un exercice clôturé.','une annulation est interdite dans un exercice clos');
select extensions.throws_ok($$select public.correct_financial_transaction(
  '96000000-0000-4000-8100-000000000001','96000000-0000-4000-8800-000000000003',1,
  '96000000-0000-4000-8300-000000000002','2024-06-15','expense','Déplacement interdit',100,null,null,null,null,'Déplacement antidaté','96000000-0000-4000-8600-000000000016')$$,
  'P0001','Cette date appartient à un exercice clôturé.','une opération ouverte ne peut pas être déplacée vers un exercice clos');
select extensions.throws_ok($$select public.create_internal_transfer_v2(
  '96000000-0000-4000-8100-000000000001','96000000-0000-4000-8300-000000000001','96000000-0000-4000-8300-000000000002','2024-08-01',20,'Virement rétroactif',null,'96000000-0000-4000-8600-000000000017')$$,
  'P0001','Cette date appartient à un exercice clôturé.','un virement ne peut pas être créé dans un exercice clos');
select extensions.throws_ok($$select public.correct_internal_transfer(
  '96000000-0000-4000-8100-000000000001','96000000-0000-4000-8900-000000000001',1,
  '96000000-0000-4000-8300-000000000001','96000000-0000-4000-8300-000000000002','2026-08-01',30,'Virement déplacé',null,'Déplacement hors clôture','96000000-0000-4000-8600-000000000018')$$,
  'P0001','Cette opération appartient à un exercice clôturé.','un virement clos ne peut pas être déplacé vers un exercice ouvert');
select extensions.throws_ok($$select public.cancel_internal_transfer_v2(
  '96000000-0000-4000-8100-000000000001','96000000-0000-4000-8900-000000000001',1,'Annulation interdite','96000000-0000-4000-8600-000000000019')$$,
  'P0001','Cette opération appartient à un exercice clôturé.','un virement clos ne peut pas être annulé');

insert into public.transaction_documents(id,transaction_id,storage_path,file_name,mime_type,file_size,created_by)
select '96000000-0000-4000-8700-000000000001',id,
  'protected-persons/96000000-0000-4000-8100-000000000001/transactions/'||id||'/proof','preuve.pdf','application/pdf',100,
  '96000000-0000-4000-8000-000000000001' from public.transactions where label='Achat';

select extensions.is((public.correct_financial_transaction(
  '96000000-0000-4000-8100-000000000001',(select id from public.transactions where label='Achat'),1,
  '96000000-0000-4000-8300-000000000001','2026-09-02','income','Remboursement',100,null,null,null,'Corrige','Type saisi par erreur','96000000-0000-4000-8600-000000000004'
)->>'revision')::bigint,2::bigint,'une depense est convertie en recette');
select extensions.is((select count(*) from public.transaction_changes),1::bigint,'la correction est auditee');
select extensions.is((select count(*) from public.transaction_documents),0::bigint,'le justificatif ne reste pas rattache a la recette');
select extensions.is((select count(*) from public.transaction_document_history),1::bigint,'les metadonnees documentaires sont conservees');
select extensions.is((select count(*) from public.transaction_banking_impacts),2::bigint,'la correction bancaire produit deux impacts');
select extensions.ok((select refresh_required_at is not null from public.management_reports where id='96000000-0000-4000-8500-000000000001'),'le projet concerne est invalide');
select extensions.throws_ok($$select public.correct_financial_transaction(
  '96000000-0000-4000-8100-000000000001',(select id from public.transactions where label='Remboursement'),1,
  '96000000-0000-4000-8300-000000000001','2026-09-02','income','Conflit',100,null,null,null,null,'Revision ancienne','96000000-0000-4000-8600-000000000005')$$,'40001','L’opération a été modifiée. Rechargez la page.','une revision obsolete est refusee');

select extensions.is((public.correct_financial_transaction(
  '96000000-0000-4000-8100-000000000001',(select id from public.transactions where label='Remboursement'),2,
  '96000000-0000-4000-8300-000000000001','2026-09-02','income','Libelle seul',100,null,null,null,'Commentaire','Libelle clarifie','96000000-0000-4000-8600-000000000006'
)->>'revision')::bigint,3::bigint,'une correction non bancaire est auditee');
select extensions.is((select count(*) from public.transaction_banking_impacts),2::bigint,'une correction de libelle ne cree pas d impact bancaire');
select extensions.is((public.cancel_financial_transaction(
  '96000000-0000-4000-8100-000000000001',(select id from public.transactions where label='Libelle seul'),3,'Operation en double','96000000-0000-4000-8600-000000000007'
)->>'revision')::bigint,4::bigint,'l annulation logique augmente la revision');
select extensions.ok((select cancelled_at is not null from public.transactions where label='Libelle seul'),'la transaction reste presente et annulee');
select extensions.is((select count(*) from public.transaction_banking_impacts),3::bigint,'l annulation produit un impact inverse');
select extensions.throws_ok($$update public.transactions set cancelled_at=null,cancelled_by=null where id=(select id from public.transactions where label='Libelle seul')$$,'42501','permission denied for table transactions','une annulation directe est interdite par les privileges SQL');
select extensions.throws_ok($$update public.transactions set transaction_type='expense' where id=(select id from public.transactions where label='Libelle seul')$$,'42501','permission denied for table transactions','une conversion directe est interdite par les privileges SQL');

select extensions.is((public.create_internal_transfer_v2(
  '96000000-0000-4000-8100-000000000001','96000000-0000-4000-8300-000000000001','96000000-0000-4000-8300-000000000002','2026-10-01',50,'Virement','Test','96000000-0000-4000-8600-000000000008'
)->>'revision')::bigint,1::bigint,'un virement et ses deux mouvements sont crees');
set constraints all immediate;
set constraints all deferred;
select extensions.is((select count(*) from public.transactions where transfer_id=(select id from public.transfers where label='Virement')),2::bigint,'le virement comporte exactement deux mouvements');
select extensions.is((public.create_internal_transfer_v2(
  '96000000-0000-4000-8100-000000000001','96000000-0000-4000-8300-000000000001','96000000-0000-4000-8300-000000000002','2026-10-01',50,'Virement','Test','96000000-0000-4000-8600-000000000008'
)->>'replayed')::boolean,true,'la creation du virement est idempotente');
select extensions.is((public.correct_internal_transfer(
  '96000000-0000-4000-8100-000000000001',(select id from public.transfers where label='Virement'),1,
  '96000000-0000-4000-8300-000000000001','96000000-0000-4000-8300-000000000002','2026-10-02',60,'Virement corrige','Test','Montant corrige','96000000-0000-4000-8600-000000000009'
)->>'revision')::bigint,2::bigint,'les deux mouvements sont corriges atomiquement');
set constraints all immediate;
set constraints all deferred;
select extensions.is((select count(*) from public.transactions where transfer_id=(select id from public.transfers where label='Virement corrige') and amount=60),2::bigint,'les deux montants suivent le virement');
select extensions.is((select count(*) from public.transfer_changes),1::bigint,'la correction du virement est auditee');
select extensions.is((select count(*) from public.transaction_banking_impacts where transfer_change_id is not null),4::bigint,'la correction du virement prepare quatre impacts');
select extensions.is((public.cancel_internal_transfer_v2(
  '96000000-0000-4000-8100-000000000001',(select id from public.transfers where label='Virement corrige'),2,'Virement saisi en double','96000000-0000-4000-8600-000000000010'
)->>'revision')::bigint,3::bigint,'le virement est annule logiquement');
set constraints all immediate;
set constraints all deferred;
select extensions.is((select count(*) from public.transactions where transfer_id=(select id from public.transfers where label='Virement corrige') and cancelled_at is not null),2::bigint,'les deux mouvements sont annules ensemble');

select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000003',true);
select extensions.throws_ok($$select public.create_financial_transaction(
  '96000000-0000-4000-8100-000000000001','96000000-0000-4000-8300-000000000001','2026-10-10','income','Lecteur',10,null,null,null,null,'96000000-0000-4000-8600-000000000011')$$,'42501','Dossier introuvable ou accès refusé.','un lecteur ne peut pas creer');
select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000004',true);
select extensions.throws_ok($$select public.cancel_financial_transaction(
  '96000000-0000-4000-8100-000000000001','96000000-0000-4000-8800-000000000001',1,'Interdit','96000000-0000-4000-8600-000000000012')$$,'42501','Dossier introuvable ou accès refusé.','un utilisateur exterieur est refuse');
select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000001',true);
reset role;
update public.protected_persons set status='archived',archived_at=clock_timestamp() where id='96000000-0000-4000-8100-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub','96000000-0000-4000-8000-000000000001',true);
select extensions.throws_ok($$select public.create_financial_transaction(
  '96000000-0000-4000-8100-000000000002','96000000-0000-4000-8300-000000000003','2026-10-10','income','Archive',10,null,null,null,null,'96000000-0000-4000-8600-000000000013')$$,'P4R01','Ce dossier est archivé. Restaurez-le avant toute modification.','un dossier archive reste en lecture seule');

select extensions.throws_ok($$update public.transaction_changes set reason='Alteration'$$,'42501','permission denied for table transaction_changes','un journal ne peut pas etre modifie directement');
reset role;
select extensions.throws_ok($$update public.transaction_changes set reason='Alteration'$$,'42501','Un historique financier est immuable.','le trigger protege aussi les ecritures privilegiees');

select * from extensions.finish();
rollback;
