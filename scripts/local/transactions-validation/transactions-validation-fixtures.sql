begin;

insert into auth.users(
  instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  confirmation_token,recovery_token,email_change_token_new,email_change,
  email_change_token_current,reauthentication_token,raw_app_meta_data,
  raw_user_meta_data,created_at,updated_at
) values
('00000000-0000-0000-0000-000000000000','97000000-0000-4000-8000-000000000001','authenticated','authenticated','transactions-validation-owner@example.test',extensions.crypt('__LOCAL_PASSWORD__',extensions.gen_salt('bf')),now(),'','','','','','','{"provider":"email","providers":["email"]}','{"first_name":"Olivia","last_name":"Validation"}',now(),now()),
('00000000-0000-0000-0000-000000000000','97000000-0000-4000-8000-000000000002','authenticated','authenticated','transactions-validation-manager@example.test',extensions.crypt('__LOCAL_PASSWORD__',extensions.gen_salt('bf')),now(),'','','','','','','{"provider":"email","providers":["email"]}','{"first_name":"Marc","last_name":"Validation"}',now(),now()),
('00000000-0000-0000-0000-000000000000','97000000-0000-4000-8000-000000000003','authenticated','authenticated','transactions-validation-reader@example.test',extensions.crypt('__LOCAL_PASSWORD__',extensions.gen_salt('bf')),now(),'','','','','','','{"provider":"email","providers":["email"]}','{"first_name":"Léa","last_name":"Validation"}',now(),now());

insert into auth.identities(provider_id,user_id,identity_data,provider,last_sign_in_at,created_at,updated_at,id) values
('transactions-validation-owner@example.test','97000000-0000-4000-8000-000000000001','{"sub":"97000000-0000-4000-8000-000000000001","email":"transactions-validation-owner@example.test"}','email',now(),now(),now(),'97000000-0000-4000-8900-000000000001'),
('transactions-validation-manager@example.test','97000000-0000-4000-8000-000000000002','{"sub":"97000000-0000-4000-8000-000000000002","email":"transactions-validation-manager@example.test"}','email',now(),now(),now(),'97000000-0000-4000-8900-000000000002'),
('transactions-validation-reader@example.test','97000000-0000-4000-8000-000000000003','{"sub":"97000000-0000-4000-8000-000000000003","email":"transactions-validation-reader@example.test"}','email',now(),now(),now(),'97000000-0000-4000-8900-000000000003');

update public.application_user_authorizations
set status='active',status_changed_at=now(),account_mode=case when user_id='97000000-0000-4000-8000-000000000001' then 'autonomous' else 'collaborator' end
where user_id in ('97000000-0000-4000-8000-000000000001','97000000-0000-4000-8000-000000000002','97000000-0000-4000-8000-000000000003');

insert into public.protected_persons(id,owner_id,first_name,last_name)
values('97000000-0000-4000-8100-000000000101','97000000-0000-4000-8000-000000000001','Camille','Démonstration');
insert into public.protected_person_access(id,protected_person_id,user_id,role,invited_by) values
('97000000-0000-4000-8200-000000000201','97000000-0000-4000-8100-000000000101','97000000-0000-4000-8000-000000000002','manager','97000000-0000-4000-8000-000000000001'),
('97000000-0000-4000-8200-000000000202','97000000-0000-4000-8100-000000000101','97000000-0000-4000-8000-000000000003','read_only','97000000-0000-4000-8000-000000000001');
insert into public.financial_accounts(id,protected_person_id,account_type,institution_name,account_name,initial_balance,initial_balance_date,opening_date,status)
values('97000000-0000-4000-8300-000000000301','97000000-0000-4000-8100-000000000101','checking','Banque fictive','Compte de validation',100,'2026-01-01','2026-01-01','active');
insert into public.management_periods(id,protected_person_id,start_date,end_date,status,closed_at)
values('97000000-0000-4000-8400-000000000401','97000000-0000-4000-8100-000000000101','2025-01-01','2025-12-31','closed',now());

set local role authenticated;
select set_config('request.jwt.claim.sub','97000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"97000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.create_financial_transaction('97000000-0000-4000-8100-000000000101','97000000-0000-4000-8300-000000000301','2026-10-01','income','Recette active',150,null,null,null,'Fixture locale','97000000-0000-4000-8600-000000000001');
select public.create_financial_transaction('97000000-0000-4000-8100-000000000101','97000000-0000-4000-8300-000000000301','2026-10-02','expense','Dépense avec justificatif',40,null,null,null,'Fixture locale','97000000-0000-4000-8600-000000000002');
select public.create_financial_transaction('97000000-0000-4000-8100-000000000101','97000000-0000-4000-8300-000000000301','2026-10-03','expense','Opération à annuler',15,null,null,null,'Fixture locale','97000000-0000-4000-8600-000000000003');
select public.create_financial_transaction('97000000-0000-4000-8100-000000000101','97000000-0000-4000-8300-000000000301','2026-10-04','expense','Opération à corriger',30,null,null,null,'Fixture locale','97000000-0000-4000-8600-000000000004');
select public.create_financial_transaction('97000000-0000-4000-8100-000000000101','97000000-0000-4000-8300-000000000301','2026-10-05','expense','Opération à convertir',12,null,null,null,'Fixture locale','97000000-0000-4000-8600-000000000005');
reset role;

insert into public.transaction_documents(id,transaction_id,storage_path,file_name,mime_type,file_size,created_by)
select '97000000-0000-4000-8700-000000000001',id,
  'protected-persons/97000000-0000-4000-8100-000000000101/transactions/'||id||'/proof',
  'justificatif-courant.pdf','application/pdf',69,'97000000-0000-4000-8000-000000000001'
from public.transactions where financial_account_id='97000000-0000-4000-8300-000000000301' and label='Dépense avec justificatif';
insert into public.transaction_documents(id,transaction_id,storage_path,file_name,mime_type,file_size,created_by)
select '97000000-0000-4000-8700-000000000002',id,
  'protected-persons/97000000-0000-4000-8100-000000000101/transactions/'||id||'/proof',
  'justificatif-historique.pdf','application/pdf',69,'97000000-0000-4000-8000-000000000001'
from public.transactions where financial_account_id='97000000-0000-4000-8300-000000000301' and label='Opération à convertir';

insert into public.bank_statements(id,financial_account_id,statement_start_date,statement_end_date,statement_balance,storage_path,original_file_name,mime_type,file_size,note,created_by)
values('97000000-0000-4000-8500-000000000501','97000000-0000-4000-8300-000000000301','2026-10-01','2026-10-15',153,
  'protected-persons/97000000-0000-4000-8100-000000000101/accounts/97000000-0000-4000-8300-000000000301/statements/97000000-0000-4000-8500-000000000501/statement',null,null,null,'Rapprochement historique fictif','97000000-0000-4000-8000-000000000001');
insert into public.bank_reconciliations(id,bank_statement_id,created_by)
values('97000000-0000-4000-8500-000000000601','97000000-0000-4000-8500-000000000501','97000000-0000-4000-8000-000000000001');

set local role authenticated;
select set_config('request.jwt.claim.sub','97000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"97000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.validate_bank_reconciliation('97000000-0000-4000-8500-000000000601');
select public.correct_financial_transaction('97000000-0000-4000-8100-000000000101',(select id from public.transactions where financial_account_id='97000000-0000-4000-8300-000000000301' and label='Opération à corriger'),1,'97000000-0000-4000-8300-000000000301','2026-10-04','expense','Opération corrigée',32,null,null,null,'Montant corrigé','Montant initial erroné','97000000-0000-4000-8600-000000000006');
select public.cancel_financial_transaction('97000000-0000-4000-8100-000000000101',(select id from public.transactions where financial_account_id='97000000-0000-4000-8300-000000000301' and label='Opération à annuler'),1,'Doublon fictif','97000000-0000-4000-8600-000000000007');
select public.correct_financial_transaction('97000000-0000-4000-8100-000000000101',(select id from public.transactions where financial_account_id='97000000-0000-4000-8300-000000000301' and label='Opération à convertir'),1,'97000000-0000-4000-8300-000000000301','2026-10-05','income','Opération convertie en recette',12,null,null,null,'Conversion fictive','Nature initiale erronée','97000000-0000-4000-8600-000000000008');
reset role;

insert into public.bank_statements(id,financial_account_id,statement_start_date,statement_end_date,statement_balance,storage_path,original_file_name,mime_type,file_size,note,created_by)
values('97000000-0000-4000-8500-000000000502','97000000-0000-4000-8300-000000000301','2026-10-16','2026-10-31',190,
  'protected-persons/97000000-0000-4000-8100-000000000101/accounts/97000000-0000-4000-8300-000000000301/statements/97000000-0000-4000-8500-000000000502/statement',null,null,null,'Rapprochement à valider avec impacts','97000000-0000-4000-8000-000000000001');
insert into public.bank_reconciliations(id,bank_statement_id,created_by)
values('97000000-0000-4000-8500-000000000602','97000000-0000-4000-8500-000000000502','97000000-0000-4000-8000-000000000001');

commit;
