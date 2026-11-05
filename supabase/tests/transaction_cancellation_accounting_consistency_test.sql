begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(27);

insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('00000000-0000-0000-0000-000000000000','99700000-0000-4000-8000-000000000001','authenticated','authenticated','coh-owner@example.test','hash',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','99700000-0000-4000-8000-000000000002','authenticated','authenticated','coh-reader@example.test','hash',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','99700000-0000-4000-8000-000000000003','authenticated','authenticated','coh-outsider@example.test','hash',now(),'{}','{}',now(),now());
update public.application_user_authorizations set status='active',status_changed_at=now()
where user_id in ('99700000-0000-4000-8000-000000000001','99700000-0000-4000-8000-000000000002','99700000-0000-4000-8000-000000000003');
insert into public.protected_persons(id,owner_id,first_name,last_name) values
('99700000-0000-4000-8100-000000000001','99700000-0000-4000-8000-000000000001','Cohérence','Transactions');
insert into public.protected_person_access(id,protected_person_id,user_id,role,invited_by) values
('99700000-0000-4000-8900-000000000001','99700000-0000-4000-8100-000000000001','99700000-0000-4000-8000-000000000002','read_only','99700000-0000-4000-8000-000000000001');
insert into public.financial_accounts(id,protected_person_id,account_type,institution_name,account_name,initial_balance,initial_balance_date) values
('99700000-0000-4000-8200-000000000001','99700000-0000-4000-8100-000000000001','checking','Locale','Cohérence',100,'2026-01-01');
insert into public.transactions(id,financial_account_id,transaction_date,transaction_type,label,amount) values
('99700000-0000-4000-8300-000000000001','99700000-0000-4000-8200-000000000001','2026-01-05','income','Recette',10),
('99700000-0000-4000-8300-000000000002','99700000-0000-4000-8200-000000000001','2026-01-08','expense','À annuler',20),
('99700000-0000-4000-8300-000000000003','99700000-0000-4000-8200-000000000001','2026-01-10','expense','À corriger',5),
('99700000-0000-4000-8300-000000000004','99700000-0000-4000-8200-000000000001','2026-01-12','expense','À annuler en brouillon',7);
insert into public.bank_statements(id,financial_account_id,statement_start_date,statement_end_date,statement_balance,storage_path,created_by) values
('99700000-0000-4000-8400-000000000001','99700000-0000-4000-8200-000000000001','2026-01-01','2026-01-31',78,'coh-historical','99700000-0000-4000-8000-000000000001'),
('99700000-0000-4000-8400-000000000002','99700000-0000-4000-8200-000000000001','2026-02-01','2026-02-28',104,'coh-next','99700000-0000-4000-8000-000000000001');
insert into public.bank_reconciliations(id,bank_statement_id,created_by) values
('99700000-0000-4000-8500-000000000001','99700000-0000-4000-8400-000000000001','99700000-0000-4000-8000-000000000001'),
('99700000-0000-4000-8500-000000000002','99700000-0000-4000-8400-000000000002','99700000-0000-4000-8000-000000000001');

select extensions.has_table('public','transaction_banking_impact_acknowledgements','la table de reconnaissance existe');
select extensions.ok(not has_table_privilege('authenticated','public.transaction_banking_impact_acknowledgements','INSERT'),'aucune insertion directe n est accordée');
select extensions.ok(has_function_privilege('authenticated','public.acknowledge_transaction_banking_impact(uuid,uuid,text)','EXECUTE'),'la RPC de reconnaissance est exposée');

set local "request.jwt.claim.sub"='99700000-0000-4000-8000-000000000001';
set local "request.jwt.claims"='{"sub":"99700000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;
select public.validate_bank_reconciliation('99700000-0000-4000-8500-000000000001');
select public.activate_complete_bank_reconciliation('99700000-0000-4000-8500-000000000002');
select public.add_bank_reconciliation_outstanding_transaction('99700000-0000-4000-8500-000000000002','99700000-0000-4000-8300-000000000004');
select public.cancel_financial_transaction('99700000-0000-4000-8100-000000000001','99700000-0000-4000-8300-000000000002',1,'Annulation après rapprochement','99700000-0000-4000-8600-000000000001');
select public.cancel_financial_transaction('99700000-0000-4000-8100-000000000001','99700000-0000-4000-8300-000000000004',1,'Annulation en brouillon','99700000-0000-4000-8600-000000000002');
select public.correct_financial_transaction('99700000-0000-4000-8100-000000000001','99700000-0000-4000-8300-000000000003',1,'99700000-0000-4000-8200-000000000001','2026-01-10','expense','Corrigée',6,null,null,null,null,'Montant corrigé','99700000-0000-4000-8600-000000000003');

select extensions.is((select calculated_balance from public.bank_reconciliations where id='99700000-0000-4000-8500-000000000001'),78::numeric,'le rapprochement validé conserve son snapshot');
select extensions.is((select calculated_balance from public.get_bank_reconciliation_detailed_summary('99700000-0000-4000-8500-000000000002')),104::numeric,'le brouillon exclut les deux annulations et applique la correction');
select extensions.is((select count(*) from public.list_bank_reconciliation_candidate_transactions('99700000-0000-4000-8500-000000000002') where transaction_id in ('99700000-0000-4000-8300-000000000002','99700000-0000-4000-8300-000000000004')),0::bigint,'les annulations ne sont plus candidates');
select extensions.throws_ok($$ select public.add_bank_reconciliation_outstanding_transaction('99700000-0000-4000-8500-000000000002','99700000-0000-4000-8300-000000000002') $$,'55000','Une opération annulée ne peut pas être ajoutée au rapprochement.','une annulation ne peut pas être ajoutée directement');
select extensions.is((select count(*) from public.list_transaction_banking_impacts_for_reconciliation('99700000-0000-4000-8500-000000000002')),4::bigint,'annulations et correction produisent quatre impacts à reconnaître');
select extensions.is((select count(*) from public.list_transaction_banking_impacts_for_reconciliation('99700000-0000-4000-8500-000000000002') where impact_kind='apply_current'),1::bigint,'la correction conserve son impact courant');
select extensions.is((select count(*) from public.list_transaction_banking_impacts_for_reconciliation('99700000-0000-4000-8500-000000000002') where historical_reconciliation_id='99700000-0000-4000-8500-000000000001'),4::bigint,'chaque impact identifie le rapprochement historique');
select extensions.throws_ok($$ select public.validate_bank_reconciliation('99700000-0000-4000-8500-000000000002') $$,'55000','Le brouillon contient une opération annulée ou indisponible. Révisez le rapprochement avant de le valider.','la validation refuse la ligne annulée du brouillon');
select extensions.is((select status::text from public.bank_reconciliations where id='99700000-0000-4000-8500-000000000002'),'draft','le brouillon refusé reste intact');
select extensions.is((select count(*) from public.bank_reconciliation_outstanding_transactions where bank_reconciliation_id='99700000-0000-4000-8500-000000000002'),1::bigint,'aucune ligne n est supprimée silencieusement');
select public.remove_bank_reconciliation_outstanding_transaction('99700000-0000-4000-8500-000000000002','99700000-0000-4000-8300-000000000004');
select extensions.throws_ok($$ select public.validate_bank_reconciliation('99700000-0000-4000-8500-000000000002') $$,'55000','Chaque impact bancaire doit être reconnu et justifié avant la validation.','les impacts restent bloquants lorsque le rapprochement est équilibré');
select extensions.is((select status::text from public.bank_reconciliations where id='99700000-0000-4000-8500-000000000002'),'draft','le refus pour impacts conserve le brouillon');

reset role;
set local "request.jwt.claim.sub"='99700000-0000-4000-8000-000000000002';
set local "request.jwt.claims"='{"sub":"99700000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;
select extensions.is((select count(*) from public.list_transaction_banking_impacts_for_reconciliation('99700000-0000-4000-8500-000000000002')),4::bigint,'le lecteur peut consulter les impacts');
select extensions.throws_ok($$ select public.acknowledge_transaction_banking_impact('99700000-0000-4000-8500-000000000002',(select impact_id from public.list_transaction_banking_impacts_for_reconciliation('99700000-0000-4000-8500-000000000002') limit 1),'Lecture interdite') $$,'42501','Rapprochement ou impact introuvable.','le lecteur ne peut pas reconnaître un impact');
reset role;
set local "request.jwt.claim.sub"='99700000-0000-4000-8000-000000000003';
set local "request.jwt.claims"='{"sub":"99700000-0000-4000-8000-000000000003","role":"authenticated"}';
set local role authenticated;
select extensions.is((select count(*) from public.list_transaction_banking_impacts_for_reconciliation('99700000-0000-4000-8500-000000000002')),0::bigint,'un utilisateur extérieur ne voit aucun impact');
reset role;
set local "request.jwt.claim.sub"='99700000-0000-4000-8000-000000000001';
set local "request.jwt.claims"='{"sub":"99700000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;
select public.acknowledge_transaction_banking_impact('99700000-0000-4000-8500-000000000002',impact_id,'Impact vérifié sur le relevé suivant')
from public.list_transaction_banking_impacts_for_reconciliation('99700000-0000-4000-8500-000000000002');
select extensions.is((select count(*) from public.transaction_banking_impact_acknowledgements where bank_reconciliation_id='99700000-0000-4000-8500-000000000002'),4::bigint,'chaque impact reçoit une reconnaissance distincte');
select extensions.is((select count(*) from public.list_transaction_banking_impacts_for_reconciliation('99700000-0000-4000-8500-000000000002') where acknowledgement_state='acknowledged'),4::bigint,'la lecture expose l état reconnu');
select extensions.lives_ok($$ select public.acknowledge_transaction_banking_impact('99700000-0000-4000-8500-000000000002',(select impact_id from public.list_transaction_banking_impacts_for_reconciliation('99700000-0000-4000-8500-000000000002') limit 1),'Impact vérifié sur le relevé suivant') $$,'un rejeu identique est idempotent');
select extensions.throws_ok($$ select public.acknowledge_transaction_banking_impact('99700000-0000-4000-8500-000000000002',(select impact_id from public.list_transaction_banking_impacts_for_reconciliation('99700000-0000-4000-8500-000000000002') limit 1),'Justification divergente') $$,'23505','Cet impact a déjà reçu une autre reconnaissance.','une reconnaissance divergente est refusée');
reset role;
select extensions.throws_ok($$ update public.transaction_banking_impact_acknowledgements set justification='Altération' where bank_reconciliation_id='99700000-0000-4000-8500-000000000002' $$,'42501','Un historique financier est immuable.','les reconnaissances sont immuables');
set local role authenticated;
select extensions.lives_ok($$ select public.validate_bank_reconciliation('99700000-0000-4000-8500-000000000002') $$,'la validation réussit après retrait et reconnaissance');
select extensions.is((select calculated_balance from public.bank_reconciliations where id='99700000-0000-4000-8500-000000000002'),104::numeric,'le nouveau snapshot contient seulement les opérations actives');
select extensions.is((select calculated_balance from public.bank_reconciliations where id='99700000-0000-4000-8500-000000000001'),78::numeric,'le premier rapprochement reste inchangé après la validation suivante');
select extensions.is((select count(*) from public.transaction_banking_impacts where protected_person_id='99700000-0000-4000-8100-000000000001'),4::bigint,'les impacts sources restent immuables et conservés');

select * from extensions.finish();
rollback;
