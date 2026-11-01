begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(51);

select extensions.has_column('public', 'debts', 'revision', 'la dette porte une revision technique');
select extensions.has_table('public', 'debt_status_changes', 'le journal des changements de statut existe');
select extensions.has_function(
  'public', 'settle_debt', array['uuid', 'uuid', 'bigint', 'date', 'text'],
  'la RPC de cloture explicite existe'
);
select extensions.ok(
  (select procedure.prosecdef
   from pg_proc procedure
   where procedure.oid = 'public.settle_debt(uuid,uuid,bigint,date,text)'::regprocedure),
  'la RPC est SECURITY DEFINER'
);
select extensions.ok(
  position('FOR UPDATE' in upper(pg_get_functiondef('public.settle_debt(uuid,uuid,bigint,date,text)'::regprocedure))) > 0,
  'la RPC verrouille la dette avant la transition'
);
select extensions.ok(
  has_function_privilege('authenticated', 'public.settle_debt(uuid,uuid,bigint,date,text)', 'EXECUTE'),
  'authenticated peut appeler la RPC controlee'
);
select extensions.ok(
  not has_function_privilege('anon', 'public.settle_debt(uuid,uuid,bigint,date,text)', 'EXECUTE'),
  'anon ne peut pas appeler la RPC'
);
select extensions.ok(
  not has_function_privilege('service_role', 'public.settle_debt(uuid,uuid,bigint,date,text)', 'EXECUTE'),
  'service_role ne constitue pas une autorisation metier directe'
);
select extensions.has_trigger('public', 'debts', 'debts_protect_lifecycle', 'le cycle de vie des dettes est protege');
select extensions.has_trigger('public', 'debt_balances', 'debt_balances_protect_lifecycle', 'les situations sont protegees apres cloture');
select extensions.has_trigger('public', 'debt_status_changes', 'debt_status_changes_immutable', 'le journal est immuable');
select extensions.ok(
  (select class.relrowsecurity
   from pg_class class
   where class.oid = 'public.debt_status_changes'::regclass),
  'RLS est activee sur le journal'
);
select extensions.ok(
  has_table_privilege('authenticated', 'public.debt_status_changes', 'SELECT'),
  'authenticated peut lire les traces autorisees'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.debt_status_changes', 'INSERT'),
  'authenticated ne peut pas creer directement une trace'
);
select extensions.ok(
  not exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid = 'public.debts'::regclass
      and constraint_row.contype = 'c'
      and pg_get_constraintdef(constraint_row.oid) ilike '%current_balance%'
      and pg_get_constraintdef(constraint_row.oid) ilike '%status%'
  ),
  'aucune contrainte retroactive ne bloque les dettes historiques incoherentes'
);

insert into auth.users(
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000','93000000-0000-4000-8000-000000000001','authenticated','authenticated','debt-owner@example.test','test',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','93000000-0000-4000-8000-000000000002','authenticated','authenticated','debt-manager@example.test','test',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','93000000-0000-4000-8000-000000000003','authenticated','authenticated','debt-reader@example.test','test',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','93000000-0000-4000-8000-000000000004','authenticated','authenticated','debt-outsider@example.test','test',now(),'{}','{}',now(),now());

update public.application_user_authorizations
set status = 'active', status_changed_at = now()
where user_id::text like '93000000-0000-4000-8000-00000000000%';

update public.profiles set first_name = 'Alice', last_name = 'Proprietaire'
where id = '93000000-0000-4000-8000-000000000001';
update public.profiles set first_name = 'Marc', last_name = 'Gestionnaire'
where id = '93000000-0000-4000-8000-000000000002';

insert into public.protected_persons(id, owner_id, first_name, last_name) values
  ('93000000-0000-4000-8100-000000000001','93000000-0000-4000-8000-000000000001','Dossier','Principal'),
  ('93000000-0000-4000-8100-000000000002','93000000-0000-4000-8000-000000000004','Dossier','Etranger'),
  ('93000000-0000-4000-8100-000000000003','93000000-0000-4000-8000-000000000001','Dossier','Archive');

insert into public.protected_person_access(id, protected_person_id, user_id, role, invited_by) values
  ('93000000-0000-4000-8200-000000000001','93000000-0000-4000-8100-000000000001','93000000-0000-4000-8000-000000000002','manager','93000000-0000-4000-8000-000000000001'),
  ('93000000-0000-4000-8200-000000000002','93000000-0000-4000-8100-000000000001','93000000-0000-4000-8000-000000000003','read_only','93000000-0000-4000-8000-000000000001');

insert into public.debts(
  id, protected_person_id, creditor, debt_type, designation, start_date, status
) values
  ('93000000-0000-4000-8300-000000000001','93000000-0000-4000-8100-000000000001','Banque A','bank_loan','Cloture valide','2026-01-01','active'),
  ('93000000-0000-4000-8300-000000000002','93000000-0000-4000-8100-000000000001','Banque B','bank_loan','Solde positif','2026-01-01','active'),
  ('93000000-0000-4000-8300-000000000003','93000000-0000-4000-8100-000000000001','Banque C','bank_loan','Situation posterieure','2026-01-01','active'),
  ('93000000-0000-4000-8300-000000000004','93000000-0000-4000-8100-000000000001','Banque D','bank_loan','Sans situation','2026-01-01','active'),
  ('93000000-0000-4000-8300-000000000005','93000000-0000-4000-8100-000000000001','Banque E','bank_loan','Sans date de debut',null,'active'),
  ('93000000-0000-4000-8300-000000000006','93000000-0000-4000-8100-000000000001','Banque F','bank_loan','Dette gestionnaire','2026-01-01','active'),
  ('93000000-0000-4000-8300-000000000007','93000000-0000-4000-8100-000000000001','Banque G','bank_loan','Dette lecteur','2026-01-01','active'),
  ('93000000-0000-4000-8300-000000000008','93000000-0000-4000-8100-000000000002','Banque H','bank_loan','Dette etrangere','2026-01-01','active'),
  ('93000000-0000-4000-8300-000000000009','93000000-0000-4000-8100-000000000003','Banque I','bank_loan','Dette archivee','2026-01-01','active'),
  ('93000000-0000-4000-8300-000000000010','93000000-0000-4000-8100-000000000001','Banque J','bank_loan','Exercice cloture','2024-01-01','active'),
  ('93000000-0000-4000-8300-000000000011','93000000-0000-4000-8100-000000000001','Banque K','bank_loan','Projet a invalider','2026-01-01','active'),
  ('93000000-0000-4000-8300-000000000012','93000000-0000-4000-8100-000000000001','Banque L','bank_loan','Revision concurrente','2026-01-01','active');

insert into public.debt_balances(id, debt_id, balance_date, remaining_balance) values
  ('93000000-0000-4000-8400-000000000001','93000000-0000-4000-8300-000000000001','2026-06-01',100),
  ('93000000-0000-4000-8400-000000000002','93000000-0000-4000-8300-000000000001','2026-09-01',0),
  ('93000000-0000-4000-8400-000000000003','93000000-0000-4000-8300-000000000002','2026-09-01',50),
  ('93000000-0000-4000-8400-000000000004','93000000-0000-4000-8300-000000000003','2026-08-01',0),
  ('93000000-0000-4000-8400-000000000005','93000000-0000-4000-8300-000000000003','2026-09-01',10),
  ('93000000-0000-4000-8400-000000000006','93000000-0000-4000-8300-000000000005','2026-09-01',0),
  ('93000000-0000-4000-8400-000000000007','93000000-0000-4000-8300-000000000006','2026-09-01',0),
  ('93000000-0000-4000-8400-000000000008','93000000-0000-4000-8300-000000000007','2026-09-01',0),
  ('93000000-0000-4000-8400-000000000009','93000000-0000-4000-8300-000000000008','2026-09-01',0),
  ('93000000-0000-4000-8400-000000000010','93000000-0000-4000-8300-000000000009','2026-09-01',0),
  ('93000000-0000-4000-8400-000000000011','93000000-0000-4000-8300-000000000010','2024-09-01',0),
  ('93000000-0000-4000-8400-000000000012','93000000-0000-4000-8300-000000000011','2026-09-01',0),
  ('93000000-0000-4000-8400-000000000013','93000000-0000-4000-8300-000000000012','2026-09-01',0);

insert into public.management_periods(
  id, protected_person_id, start_date, end_date, status, closed_at
) values (
  '93000000-0000-4000-8500-000000000001',
  '93000000-0000-4000-8100-000000000001',
  '2024-01-01', '2024-12-31', 'closed', now()
);

insert into public.management_reports(
  id, protected_person_id, report_year, period_start, period_end,
  status, generated_at, created_by
) values (
  '93000000-0000-4000-8600-000000000001',
  '93000000-0000-4000-8100-000000000001',
  2026, '2026-01-01', '2026-12-31', 'generated', now(),
  '93000000-0000-4000-8000-000000000001'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','93000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"93000000-0000-4000-8000-000000000001","role":"authenticated"}',true);

select extensions.is(
  (select status from public.debts where id = '93000000-0000-4000-8300-000000000001'),
  'active',
  'une situation nulle ne cloture pas automatiquement la dette'
);
select extensions.is(
  (select current_balance from public.debts where id = '93000000-0000-4000-8300-000000000001'),
  0.00::numeric,
  'la situation nulle reste le CRD courant avant cloture explicite'
);
select extensions.is(
  public.settle_debt(
    '93000000-0000-4000-8100-000000000001',
    '93000000-0000-4000-8300-000000000001',
    3, '2026-09-01', 'Dette integralement remboursee'
  ),
  4::bigint,
  'le proprietaire solde une dette coherente'
);
select extensions.is(
  (select status from public.debts where id = '93000000-0000-4000-8300-000000000001'),
  'settled',
  'la dette devient soldee'
);
select extensions.is(
  (select settled_at from public.debts where id = '93000000-0000-4000-8300-000000000001'),
  '2026-09-01'::date,
  'la date de cloture est conservee'
);
select extensions.is(
  (select count(*) from public.debt_balances where debt_id = '93000000-0000-4000-8300-000000000001'),
  2::bigint,
  'les situations historiques sont conservees'
);
select extensions.is(
  (select reason from public.debt_status_changes where debt_id = '93000000-0000-4000-8300-000000000001'),
  'Dette integralement remboursee',
  'le motif est audite'
);
select extensions.is(
  (select changed_by from public.debt_status_changes where debt_id = '93000000-0000-4000-8300-000000000001'),
  '93000000-0000-4000-8000-000000000001'::uuid,
  'l auteur authentifie est audite'
);
select extensions.is(
  (select balance_id from public.debt_status_changes where debt_id = '93000000-0000-4000-8300-000000000001'),
  '93000000-0000-4000-8400-000000000002'::uuid,
  'la situation nulle ayant permis la cloture est tracee'
);
select extensions.throws_ok(
  $$insert into public.debt_balances(debt_id, balance_date, remaining_balance) values('93000000-0000-4000-8300-000000000001','2026-10-01',0)$$,
  '23514', 'Une dette soldee ne peut plus recevoir de nouvelle situation.',
  'aucune situation ne peut etre ajoutee apres cloture'
);
select extensions.throws_ok(
  $$update public.debts set status='active', settled_at=null where id='93000000-0000-4000-8300-000000000001'$$,
  '42501', 'La cloture d''une dette doit utiliser le parcours dedie.',
  'la reouverture directe est interdite'
);
reset role;
select extensions.throws_ok(
  $$update public.debt_status_changes set reason='Alteration' where debt_id='93000000-0000-4000-8300-000000000001'$$,
  '23514', 'Une trace de changement de statut de dette est immuable.',
  'le journal ne peut pas etre modifie'
);
set local role authenticated;
select extensions.throws_ok(
  $$delete from public.debt_status_changes where debt_id='93000000-0000-4000-8300-000000000001'$$,
  '42501', 'permission denied for table debt_status_changes',
  'le journal ne peut pas etre supprime par un utilisateur'
);
select extensions.throws_ok(
  $$select public.settle_debt('93000000-0000-4000-8100-000000000001','93000000-0000-4000-8300-000000000002',2,'2026-09-01','CRD positif')$$,
  '23514', 'Une situation a 0 EUR doit exister a la date de cloture.',
  'un CRD positif ne permet pas la cloture'
);
select extensions.throws_ok(
  $$select public.settle_debt('93000000-0000-4000-8100-000000000001','93000000-0000-4000-8300-000000000004',1,'2026-09-01','Situation absente')$$,
  '23514', 'Une situation a 0 EUR doit exister a la date de cloture.',
  'l absence de situation nulle est refusee'
);
select extensions.throws_ok(
  $$select public.settle_debt('93000000-0000-4000-8100-000000000001','93000000-0000-4000-8300-000000000003',3,'2026-08-01','Date ancienne')$$,
  '23514', 'Une situation plus recente empeche la cloture a cette date.',
  'une situation plus recente interdit une cloture retroactive'
);
select extensions.throws_ok(
  $$select public.settle_debt('93000000-0000-4000-8100-000000000001','93000000-0000-4000-8300-000000000005',2,'2026-09-01','Sans debut')$$,
  '23514', 'La date de debut de la dette doit etre renseignee avant sa cloture.',
  'la date de debut est obligatoire pour encadrer la cloture'
);
select extensions.throws_ok(
  $$select public.settle_debt('93000000-0000-4000-8100-000000000001','93000000-0000-4000-8300-000000000011',2,'2025-12-31','Avant la dette')$$,
  '23514', 'La date de cloture doit etre comprise entre le debut de la dette et la date du jour.',
  'une date anterieure au debut est refusee'
);
select extensions.throws_ok(
  $$select public.settle_debt('93000000-0000-4000-8100-000000000001','93000000-0000-4000-8300-000000000011',2,current_date + 1,'Date future')$$,
  '23514', 'La date de cloture doit etre comprise entre le debut de la dette et la date du jour.',
  'une date future est refusee'
);
select extensions.throws_ok(
  $$select public.settle_debt('93000000-0000-4000-8100-000000000001','93000000-0000-4000-8300-000000000010',2,'2024-09-01','Exercice clos')$$,
  '23514', 'La dette ne peut pas etre soldee dans un exercice cloture.',
  'la cloture dans un exercice cloture est refusee'
);
select extensions.throws_ok(
  $$insert into public.debt_balances(debt_id, balance_date, remaining_balance) values('93000000-0000-4000-8300-000000000010','2024-10-01',0)$$,
  '23514', 'Cette situation appartient a un exercice cloture. Elle ne peut plus etre ajoutee ni modifiee.',
  'une situation ne peut pas etre ajoutee dans un exercice cloture'
);
select extensions.throws_ok(
  $$update public.debts set status='settled', settled_at='2026-09-01' where id='93000000-0000-4000-8300-000000000007'$$,
  '42501', 'La cloture d''une dette doit utiliser le parcours dedie.',
  'une modification directe du statut est interdite'
);
select extensions.throws_ok(
  $$update public.debts set settled_at='2026-09-01' where id='93000000-0000-4000-8300-000000000007'$$,
  '42501', 'La cloture d''une dette doit utiliser le parcours dedie.',
  'une modification directe de la date est interdite'
);
select extensions.throws_ok(
  $$insert into public.debts(protected_person_id,creditor,debt_type,designation,start_date,status,settled_at) values('93000000-0000-4000-8100-000000000001','Banque Z','bank_loan','Creation soldee','2026-01-01','settled','2026-09-01')$$,
  '23514', 'Une nouvelle dette doit etre creee active et sans date de cloture.',
  'une dette ne peut pas etre creee directement comme soldee'
);
select extensions.throws_ok(
  $$select public.settle_debt('93000000-0000-4000-8100-000000000001','93000000-0000-4000-8300-000000000012',1,'2026-09-01','Revision obsolete')$$,
  '40001', 'La dette a ete modifiee par une autre operation.',
  'une revision obsolete protege contre les modifications concurrentes'
);
select extensions.is(
  public.settle_debt(
    '93000000-0000-4000-8100-000000000001',
    '93000000-0000-4000-8300-000000000011',
    2, '2026-09-01', 'Cloture avec projet existant'
  ),
  3::bigint,
  'la dette du projet genere est soldee'
);
select extensions.ok(
  (select refresh_required_at is not null
   from public.management_reports
   where id = '93000000-0000-4000-8600-000000000001'),
  'la cloture invalide le projet de compte de gestion concerne'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','93000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"93000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select extensions.is(
  public.settle_debt(
    '93000000-0000-4000-8100-000000000001',
    '93000000-0000-4000-8300-000000000006',
    2, '2026-09-01', 'Cloture par le gestionnaire'
  ),
  3::bigint,
  'un gestionnaire autorise peut solder une dette'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','93000000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"93000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select extensions.throws_ok(
  $$select public.settle_debt('93000000-0000-4000-8100-000000000001','93000000-0000-4000-8300-000000000007',2,'2026-09-01','Tentative lecteur')$$,
  '42501', 'Droits insuffisants pour solder cette dette.',
  'un lecteur ne peut pas solder une dette'
);
select extensions.is(
  (select count(*) from public.debt_status_changes where debt_id = '93000000-0000-4000-8300-000000000001'),
  1::bigint,
  'un lecteur autorise peut consulter l historique du dossier'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','93000000-0000-4000-8000-000000000004',true);
select set_config('request.jwt.claims','{"sub":"93000000-0000-4000-8000-000000000004","role":"authenticated"}',true);
select extensions.throws_ok(
  $$select public.settle_debt('93000000-0000-4000-8100-000000000001','93000000-0000-4000-8300-000000000007',2,'2026-09-01','Tentative externe')$$,
  '42501', 'Droits insuffisants pour solder cette dette.',
  'un utilisateur exterieur ne peut pas solder une dette'
);
select extensions.is(
  (select count(*) from public.debt_status_changes),
  0::bigint,
  'RLS masque les traces des autres dossiers'
);

reset role;
select set_config('request.jwt.claim.sub','93000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"93000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
update public.protected_persons
set status = 'archived', archived_at = clock_timestamp()
where id = '93000000-0000-4000-8100-000000000003';
set local role authenticated;
select set_config('request.jwt.claim.sub','93000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"93000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select extensions.is(
  (select status from public.protected_persons where id = '93000000-0000-4000-8100-000000000003'),
  'archived',
  'le dossier de test est archive'
);
select extensions.throws_ok(
  $$select public.settle_debt('93000000-0000-4000-8100-000000000003','93000000-0000-4000-8300-000000000009',2,'2026-09-01','Tentative sur archive')$$,
  'P4R01', 'Ce dossier est archivé. Restaurez-le avant toute modification.',
  'un dossier archive bloque la cloture'
);
select extensions.throws_ok(
  $$select public.settle_debt('93000000-0000-4000-8100-000000000001','93000000-0000-4000-8300-000000000007',2,'2026-09-01','   ')$$,
  '23514', 'Le motif de la cloture est obligatoire.',
  'le motif est obligatoire'
);
select extensions.is(
  (select count(*) from public.debt_status_changes),
  3::bigint,
  'seules les trois clotures reussies ont cree une trace'
);

select * from extensions.finish();
rollback;
