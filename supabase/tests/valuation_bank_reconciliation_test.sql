begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(28);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', '99700000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'valuation-owner@example.test', 'hash', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '99700000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'valuation-reader@example.test', 'hash', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

update public.application_user_authorizations set status='active', status_changed_at=now()
where user_id in ('99700000-0000-4000-8000-000000000001','99700000-0000-4000-8000-000000000002');

insert into public.protected_persons (id, owner_id, first_name, last_name)
values ('99700000-0000-4000-8100-000000000001','99700000-0000-4000-8000-000000000001','Dossier','Valorisation');
update public.application_user_authorizations
set registration_intent = 'collaborator',
    account_mode = 'collaborator'
where user_id in (
  '99700000-0000-4000-8000-000000000002'
);

insert into public.protected_person_access (protected_person_id,user_id,role,invited_by)
values ('99700000-0000-4000-8100-000000000001','99700000-0000-4000-8000-000000000002','read_only','99700000-0000-4000-8000-000000000001');

insert into public.financial_accounts (
  id,protected_person_id,account_type,institution_name,account_name,initial_balance,initial_balance_date,status
) values
  ('99700000-0000-4000-8200-000000000001','99700000-0000-4000-8100-000000000001','life_insurance','Mutavie','Assurance-vie',230,'2016-10-31','active'),
  ('99700000-0000-4000-8200-000000000002','99700000-0000-4000-8100-000000000001','other_investment','Placement','Autre placement',100,'2016-01-01','active'),
  ('99700000-0000-4000-8200-000000000003','99700000-0000-4000-8100-000000000001','securities_account','Titres','Compte-titres',100,'2016-01-01','active'),
  ('99700000-0000-4000-8200-000000000004','99700000-0000-4000-8100-000000000001','checking','Banque','Compte courant',100,'2016-01-01','active');

insert into public.account_valuations (id,financial_account_id,valuation_date,value,comment) values
  ('99700000-0000-4000-8300-000000000001','99700000-0000-4000-8200-000000000001','2016-10-31',230,'Fixture Mutavie'),
  ('99700000-0000-4000-8300-000000000002','99700000-0000-4000-8200-000000000001','2016-12-31',230.40,'Fixture Mutavie'),
  ('99700000-0000-4000-8300-000000000003','99700000-0000-4000-8200-000000000001','2017-12-31',232.71,'Fixture Mutavie'),
  ('99700000-0000-4000-8300-000000000004','99700000-0000-4000-8200-000000000001','2018-12-31',235.53,'Fixture Mutavie'),
  ('99700000-0000-4000-8300-000000000005','99700000-0000-4000-8200-000000000001','2019-01-01',240,'Valorisation future'),
  ('99700000-0000-4000-8300-000000000006','99700000-0000-4000-8200-000000000002','2018-12-31',150,'Autre placement'),
  ('99700000-0000-4000-8300-000000000007','99700000-0000-4000-8200-000000000003','2018-12-31',175,'Compte-titres'),
  ('99700000-0000-4000-8300-000000000008','99700000-0000-4000-8200-000000000003','2019-12-31',0,'Valorisation nulle');

insert into public.transactions (id,financial_account_id,transaction_date,transaction_type,label,amount) values
  ('99700000-0000-4000-8350-000000000002','99700000-0000-4000-8200-000000000004','2018-01-01','income','Recette classique',20);

insert into public.bank_statements (id,financial_account_id,statement_end_date,statement_balance,storage_path,created_by) values
  ('99700000-0000-4000-8400-000000000001','99700000-0000-4000-8200-000000000001','2016-10-31',230,'valuation-2016-10','99700000-0000-4000-8000-000000000001'),
  ('99700000-0000-4000-8400-000000000002','99700000-0000-4000-8200-000000000001','2016-12-31',230.40,'valuation-2016-12','99700000-0000-4000-8000-000000000001'),
  ('99700000-0000-4000-8400-000000000003','99700000-0000-4000-8200-000000000001','2017-12-31',232.71,'valuation-2017-12','99700000-0000-4000-8000-000000000001'),
  ('99700000-0000-4000-8400-000000000004','99700000-0000-4000-8200-000000000001','2018-12-31',235.53,'valuation-2018-12','99700000-0000-4000-8000-000000000001'),
  ('99700000-0000-4000-8400-000000000005','99700000-0000-4000-8200-000000000001','2018-06-30',234,'valuation-missing','99700000-0000-4000-8000-000000000001'),
  ('99700000-0000-4000-8400-000000000006','99700000-0000-4000-8200-000000000001','2019-01-01',241,'valuation-difference','99700000-0000-4000-8000-000000000001'),
  ('99700000-0000-4000-8400-000000000007','99700000-0000-4000-8200-000000000002','2018-12-31',150,'other-investment','99700000-0000-4000-8000-000000000001'),
  ('99700000-0000-4000-8400-000000000008','99700000-0000-4000-8200-000000000003','2018-12-31',175,'securities','99700000-0000-4000-8000-000000000001'),
  ('99700000-0000-4000-8400-000000000009','99700000-0000-4000-8200-000000000004','2018-12-31',120,'checking','99700000-0000-4000-8000-000000000001'),
  ('99700000-0000-4000-8400-000000000010','99700000-0000-4000-8200-000000000003','2019-12-31',0,'securities-zero','99700000-0000-4000-8000-000000000001'),
  ('99700000-0000-4000-8400-000000000011','99700000-0000-4000-8200-000000000004','2017-12-31',100,'legacy-history','99700000-0000-4000-8000-000000000001');

insert into public.bank_reconciliations (id,bank_statement_id,created_by) values
  ('99700000-0000-4000-8500-000000000001','99700000-0000-4000-8400-000000000001','99700000-0000-4000-8000-000000000001'),
  ('99700000-0000-4000-8500-000000000002','99700000-0000-4000-8400-000000000002','99700000-0000-4000-8000-000000000001'),
  ('99700000-0000-4000-8500-000000000003','99700000-0000-4000-8400-000000000003','99700000-0000-4000-8000-000000000001'),
  ('99700000-0000-4000-8500-000000000004','99700000-0000-4000-8400-000000000004','99700000-0000-4000-8000-000000000001'),
  ('99700000-0000-4000-8500-000000000005','99700000-0000-4000-8400-000000000005','99700000-0000-4000-8000-000000000001'),
  ('99700000-0000-4000-8500-000000000006','99700000-0000-4000-8400-000000000006','99700000-0000-4000-8000-000000000001'),
  ('99700000-0000-4000-8500-000000000007','99700000-0000-4000-8400-000000000007','99700000-0000-4000-8000-000000000001'),
  ('99700000-0000-4000-8500-000000000008','99700000-0000-4000-8400-000000000008','99700000-0000-4000-8000-000000000001'),
  ('99700000-0000-4000-8500-000000000009','99700000-0000-4000-8400-000000000009','99700000-0000-4000-8000-000000000001'),
  ('99700000-0000-4000-8500-000000000010','99700000-0000-4000-8400-000000000010','99700000-0000-4000-8000-000000000001');

set local session_replication_role = replica;
insert into public.bank_reconciliations (
  id,bank_statement_id,status,calculated_balance,difference,created_by,validated_at,validated_by
) values (
  '99700000-0000-4000-8500-000000000011','99700000-0000-4000-8400-000000000011','validated',
  100,0,'99700000-0000-4000-8000-000000000001',now(),'99700000-0000-4000-8000-000000000001'
);
set local session_replication_role = origin;

select extensions.ok(public.is_valuation_financial_account_type('life_insurance'),'assurance-vie valorisée');
select extensions.ok(public.is_valuation_financial_account_type('other_investment'),'autre placement valorisé');
select extensions.ok(public.is_valuation_financial_account_type('securities_account'),'compte-titres valorisé');
select extensions.ok(not public.is_valuation_financial_account_type('checking'),'compte courant classique');

set local "request.jwt.claim.sub"='99700000-0000-4000-8000-000000000001';
set local "request.jwt.claims"='{"sub":"99700000-0000-4000-8000-000000000001","role":"authenticated"}';
set local role authenticated;

select public.create_internal_transfer_v2('99700000-0000-4000-8100-000000000001','99700000-0000-4000-8200-000000000002','99700000-0000-4000-8200-000000000001','2017-12-30',1,'Avant valorisation',null,'99700000-0000-4000-8600-000000000001');
select public.create_internal_transfer_v2('99700000-0000-4000-8100-000000000001','99700000-0000-4000-8200-000000000002','99700000-0000-4000-8200-000000000001','2017-12-31',1,'Même date',null,'99700000-0000-4000-8600-000000000002');
select public.create_internal_transfer_v2('99700000-0000-4000-8100-000000000001','99700000-0000-4000-8200-000000000002','99700000-0000-4000-8200-000000000001','2018-01-01',1,'Après valorisation',null,'99700000-0000-4000-8600-000000000003');

select extensions.lives_ok($$select public.validate_bank_reconciliation('99700000-0000-4000-8500-000000000001')$$,'valorisation initiale exacte validée');
select extensions.lives_ok($$select public.validate_bank_reconciliation('99700000-0000-4000-8500-000000000002')$$,'Mutavie 2016 exacte validée');
select extensions.lives_ok($$select public.validate_bank_reconciliation('99700000-0000-4000-8500-000000000003')$$,'Mutavie 2017 exacte validée');
select extensions.lives_ok($$select public.validate_bank_reconciliation('99700000-0000-4000-8500-000000000004')$$,'Mutavie 2018 exacte validée');
select extensions.results_eq(
  $$select control_basis,reference_date,reference_value,source_valuation_id,difference from public.bank_reconciliations where id='99700000-0000-4000-8500-000000000004'$$,
  $$values ('valuation'::text,'2018-12-31'::date,235.53::numeric,'99700000-0000-4000-8300-000000000004'::uuid,0::numeric)$$,
  'la source exacte et les montants sont figés');
select extensions.throws_ok(
  $$select public.validate_bank_reconciliation('99700000-0000-4000-8500-000000000005')$$,
  '55000','Aucune valorisation n''est enregistrée au 30/06/2018. Ajoutez une valorisation à cette date pour contrôler ce relevé.',
  'les valorisations antérieure et future ne remplacent pas la date exacte');
select extensions.throws_ok(
  $$select public.validate_bank_reconciliation('99700000-0000-4000-8500-000000000006')$$,
  '55000','L''écart de valorisation doit être nul avant la validation.',
  'un écart de valorisation non nul est refusé');
select extensions.results_eq(
  $$select status::text,control_basis,calculated_balance from public.bank_reconciliations where id='99700000-0000-4000-8500-000000000006'$$,
  $$values ('draft'::text,null::text,null::numeric)$$,
  'le refus laisse le brouillon intact');
select extensions.lives_ok($$select public.validate_bank_reconciliation('99700000-0000-4000-8500-000000000007')$$,'autre placement contrôlé par valorisation');
select extensions.lives_ok($$select public.validate_bank_reconciliation('99700000-0000-4000-8500-000000000008')$$,'compte-titres contrôlé par valorisation');
select extensions.lives_ok($$select public.validate_bank_reconciliation('99700000-0000-4000-8500-000000000010')$$,'une valorisation exacte égale à zéro est valide');
select extensions.throws_ok(
  $$select public.activate_complete_bank_reconciliation('99700000-0000-4000-8500-000000000005')$$,
  '55000','Les comptes valorisés ne permettent pas le rapprochement détaillé.',
  'le rapprochement détaillé est interdit');
select extensions.lives_ok($$select public.validate_bank_reconciliation('99700000-0000-4000-8500-000000000009')$$,'le contrôle classique reste opérationnel');
select extensions.results_eq(
  $$select control_basis,reference_value,difference from public.bank_reconciliations where id='99700000-0000-4000-8500-000000000009'$$,
  $$values ('transactions'::text,120::numeric,0::numeric)$$,
  'le contrôle classique fige le solde transactionnel');
select extensions.throws_ok(
  $$select public.validate_bank_reconciliation('99700000-0000-4000-8500-000000000004')$$,
  'P0001','Seul un rapprochement en brouillon peut être validé.',
  'une validation répétée est refusée');
select extensions.results_eq(
  $$select control_basis,reference_date,reference_value,source_valuation_id from public.bank_reconciliations where id='99700000-0000-4000-8500-000000000011'$$,
  $$values (null::text,null::date,null::numeric,null::uuid)$$,
  'un rapprochement historique reste lisible sans source inventée');
select extensions.throws_ok(
  $$update public.account_valuations set value=236 where id='99700000-0000-4000-8300-000000000004'$$,
  '55000','Cette valorisation est utilisée par un rapprochement validé et ne peut plus être modifiée ou supprimée.',
  'une valorisation utilisée ne peut plus être modifiée');
select extensions.throws_ok(
  $$delete from public.account_valuations where id='99700000-0000-4000-8300-000000000004'$$,
  '55000','Cette valorisation est utilisée par un rapprochement validé et ne peut plus être modifiée ou supprimée.',
  'une valorisation utilisée ne peut plus être supprimée');
select extensions.lives_ok(
  $$update public.account_valuations set comment='Correction autorisée' where id='99700000-0000-4000-8300-000000000005'$$,
  'une valorisation non utilisée reste modifiable');
select extensions.results_eq(
  $$select reference_value,source_valuation_id from public.bank_reconciliations where id='99700000-0000-4000-8500-000000000004'$$,
  $$values (235.53::numeric,'99700000-0000-4000-8300-000000000004'::uuid)$$,
  'une modification étrangère ne réécrit pas la référence figée');
select extensions.ok(has_function_privilege('authenticated','public.validate_bank_reconciliation(uuid)','EXECUTE'),'authenticated conserve la validation sécurisée');
select extensions.ok(not has_function_privilege('anon','public.validate_bank_reconciliation(uuid)','EXECUTE'),'anon ne peut pas valider');

reset role;
set local "request.jwt.claim.sub"='99700000-0000-4000-8000-000000000002';
set local "request.jwt.claims"='{"sub":"99700000-0000-4000-8000-000000000002","role":"authenticated"}';
set local role authenticated;
select extensions.throws_ok(
  $$select public.validate_bank_reconciliation('99700000-0000-4000-8500-000000000005')$$,
  'P0001','Rapprochement introuvable.',
  'un lecteur ne peut pas valider');
select extensions.results_eq(
  $$select status::text from public.bank_reconciliations where id='99700000-0000-4000-8500-000000000001'$$,
  $$values ('validated'::text)$$,
  'un rapprochement validé reste consultable en lecture seule');

select * from extensions.finish();
rollback;
