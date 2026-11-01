begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(74);

select extensions.has_column('public', 'debt_balances', 'revision', 'les situations portent une revision');
select extensions.has_column('public', 'debt_balances', 'cancelled_at', 'la date d annulation existe');
select extensions.has_column('public', 'debt_balances', 'cancelled_by', 'l auteur de l annulation existe');
select extensions.has_column('public', 'debt_balances', 'cancellation_reason', 'le motif d annulation existe');
select extensions.has_table('public', 'debt_balance_changes', 'le journal des corrections existe');
select extensions.has_function(
  'public', 'correct_debt_balance',
  array['uuid', 'uuid', 'uuid', 'bigint', 'date', 'numeric', 'integer', 'text'],
  'la RPC de correction existe'
);
select extensions.has_function(
  'public', 'cancel_debt_balance',
  array['uuid', 'uuid', 'uuid', 'bigint', 'text'],
  'la RPC d annulation existe'
);
select extensions.ok(
  (select procedure.prosecdef
   from pg_proc procedure
   where procedure.oid = 'public.correct_debt_balance(uuid,uuid,uuid,bigint,date,numeric,integer,text)'::regprocedure),
  'la correction est SECURITY DEFINER'
);
select extensions.ok(
  (select procedure.prosecdef
   from pg_proc procedure
   where procedure.oid = 'public.cancel_debt_balance(uuid,uuid,uuid,bigint,text)'::regprocedure),
  'l annulation est SECURITY DEFINER'
);
select extensions.ok(
  position(
    'FOR UPDATE' in upper(pg_get_functiondef(
      'public.correct_debt_balance(uuid,uuid,uuid,bigint,date,numeric,integer,text)'::regprocedure
    ))
  ) > 0,
  'la correction verrouille les donnees avant la mutation'
);
select extensions.ok(
  position(
    'FOR UPDATE' in upper(pg_get_functiondef(
      'public.cancel_debt_balance(uuid,uuid,uuid,bigint,text)'::regprocedure
    ))
  ) > 0,
  'l annulation verrouille les donnees avant la mutation'
);
select extensions.ok(
  has_function_privilege(
    'authenticated',
    'public.correct_debt_balance(uuid,uuid,uuid,bigint,date,numeric,integer,text)',
    'EXECUTE'
  ),
  'authenticated peut appeler la correction controlee'
);
select extensions.ok(
  has_function_privilege(
    'authenticated',
    'public.cancel_debt_balance(uuid,uuid,uuid,bigint,text)',
    'EXECUTE'
  ),
  'authenticated peut appeler l annulation controlee'
);
select extensions.ok(
  not has_function_privilege(
    'anon',
    'public.correct_debt_balance(uuid,uuid,uuid,bigint,date,numeric,integer,text)',
    'EXECUTE'
  ),
  'anon ne peut pas corriger une situation'
);
select extensions.ok(
  not has_function_privilege(
    'service_role',
    'public.cancel_debt_balance(uuid,uuid,uuid,bigint,text)',
    'EXECUTE'
  ),
  'service_role ne constitue pas une autorisation metier'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.debt_balances', 'UPDATE'),
  'la modification directe des situations est retiree'
);
select extensions.ok(
  not has_table_privilege('service_role', 'public.debt_balances', 'UPDATE'),
  'service_role ne peut pas modifier directement les situations'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.debt_balances', 'DELETE'),
  'la suppression directe des situations est interdite'
);
select extensions.ok(
  (select class.relrowsecurity
   from pg_class class
   where class.oid = 'public.debt_balance_changes'::regclass),
  'RLS est activee sur le journal'
);
select extensions.ok(
  has_table_privilege('authenticated', 'public.debt_balance_changes', 'SELECT'),
  'les utilisateurs authentifies peuvent lire les traces autorisees'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.debt_balance_changes', 'INSERT'),
  'une trace ne peut pas etre inseree directement'
);
select extensions.ok(
  not has_table_privilege('authenticated', 'public.debt_balance_changes', 'UPDATE'),
  'une trace ne peut pas etre modifiee directement'
);
select extensions.has_trigger(
  'public', 'debt_balances', 'debt_balances_protect_audit_lifecycle',
  'le cycle de vie audite des situations est protege'
);
select extensions.has_trigger(
  'public', 'debt_balance_changes', 'debt_balance_changes_immutable',
  'le journal est immuable'
);

insert into auth.users(
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000','94000000-0000-4000-8000-000000000001','authenticated','authenticated','balance-owner@example.test','test',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','94000000-0000-4000-8000-000000000002','authenticated','authenticated','balance-manager@example.test','test',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','94000000-0000-4000-8000-000000000003','authenticated','authenticated','balance-reader@example.test','test',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','94000000-0000-4000-8000-000000000004','authenticated','authenticated','balance-outsider@example.test','test',now(),'{}','{}',now(),now());

update public.application_user_authorizations
set status = 'active', status_changed_at = now()
where user_id::text like '94000000-0000-4000-8000-00000000000%';

update public.profiles set first_name = 'Alice', last_name = 'Proprietaire'
where id = '94000000-0000-4000-8000-000000000001';
update public.profiles set first_name = 'Marc', last_name = 'Gestionnaire'
where id = '94000000-0000-4000-8000-000000000002';

insert into public.protected_persons(id, owner_id, first_name, last_name) values
  ('94000000-0000-4000-8100-000000000001','94000000-0000-4000-8000-000000000001','Dossier','Principal'),
  ('94000000-0000-4000-8100-000000000002','94000000-0000-4000-8000-000000000004','Dossier','Etranger'),
  ('94000000-0000-4000-8100-000000000003','94000000-0000-4000-8000-000000000001','Dossier','Archive');

insert into public.protected_person_access(
  id, protected_person_id, user_id, role, invited_by
) values
  ('94000000-0000-4000-8200-000000000001','94000000-0000-4000-8100-000000000001','94000000-0000-4000-8000-000000000002','manager','94000000-0000-4000-8000-000000000001'),
  ('94000000-0000-4000-8200-000000000002','94000000-0000-4000-8100-000000000001','94000000-0000-4000-8000-000000000003','read_only','94000000-0000-4000-8000-000000000001');

insert into public.debts(
  id, protected_person_id, creditor, debt_type, designation, start_date, status
) values
  ('94000000-0000-4000-8300-000000000001','94000000-0000-4000-8100-000000000001','Banque A','bank_loan','Corrections','2026-01-01','active'),
  ('94000000-0000-4000-8300-000000000002','94000000-0000-4000-8100-000000000001','Banque B','bank_loan','Annulation ancienne','2026-01-01','active'),
  ('94000000-0000-4000-8300-000000000003','94000000-0000-4000-8100-000000000001','Banque C','bank_loan','Annulation courante','2026-01-01','active'),
  ('94000000-0000-4000-8300-000000000004','94000000-0000-4000-8100-000000000001','Banque D','bank_loan','Annulation unique','2026-01-01','active'),
  ('94000000-0000-4000-8300-000000000005','94000000-0000-4000-8100-000000000001','Banque E','bank_loan','Collision','2026-01-01','active'),
  ('94000000-0000-4000-8300-000000000006','94000000-0000-4000-8100-000000000001','Banque F','bank_loan','Gestionnaire','2026-01-01','active'),
  ('94000000-0000-4000-8300-000000000007','94000000-0000-4000-8100-000000000001','Banque G','bank_loan','Lecteur','2026-01-01','active'),
  ('94000000-0000-4000-8300-000000000008','94000000-0000-4000-8100-000000000002','Banque H','bank_loan','Exterieure','2026-01-01','active'),
  ('94000000-0000-4000-8300-000000000009','94000000-0000-4000-8100-000000000003','Banque I','bank_loan','Archivee','2026-01-01','active'),
  ('94000000-0000-4000-8300-000000000010','94000000-0000-4000-8100-000000000001','Banque J','bank_loan','Ancienne date close','2024-01-01','active'),
  ('94000000-0000-4000-8300-000000000011','94000000-0000-4000-8100-000000000001','Banque K','bank_loan','Nouvelle date close','2024-01-01','active'),
  ('94000000-0000-4000-8300-000000000012','94000000-0000-4000-8100-000000000001','Banque L','bank_loan','Dette a solder','2026-01-01','active'),
  ('94000000-0000-4000-8300-000000000013','94000000-0000-4000-8100-000000000001','Banque M','bank_loan','Revision','2026-01-01','active');

insert into public.debt_balances(
  id, debt_id, balance_date, remaining_balance, remaining_duration_months
) values
  ('94000000-0000-4000-8400-000000000001','94000000-0000-4000-8300-000000000001','2026-01-01',100,12),
  ('94000000-0000-4000-8400-000000000002','94000000-0000-4000-8300-000000000001','2026-06-01',60,6),
  ('94000000-0000-4000-8400-000000000003','94000000-0000-4000-8300-000000000001','2026-09-01',20,2),
  ('94000000-0000-4000-8400-000000000004','94000000-0000-4000-8300-000000000002','2026-01-01',100,12),
  ('94000000-0000-4000-8400-000000000005','94000000-0000-4000-8300-000000000002','2026-06-01',50,6),
  ('94000000-0000-4000-8400-000000000006','94000000-0000-4000-8300-000000000003','2026-01-01',100,12),
  ('94000000-0000-4000-8400-000000000007','94000000-0000-4000-8300-000000000003','2026-06-01',50,6),
  ('94000000-0000-4000-8400-000000000008','94000000-0000-4000-8300-000000000004','2026-06-01',40,4),
  ('94000000-0000-4000-8400-000000000009','94000000-0000-4000-8300-000000000005','2026-05-01',80,8),
  ('94000000-0000-4000-8400-000000000010','94000000-0000-4000-8300-000000000005','2026-06-01',70,7),
  ('94000000-0000-4000-8400-000000000011','94000000-0000-4000-8300-000000000006','2026-06-01',60,6),
  ('94000000-0000-4000-8400-000000000012','94000000-0000-4000-8300-000000000007','2026-06-01',60,6),
  ('94000000-0000-4000-8400-000000000013','94000000-0000-4000-8300-000000000008','2026-06-01',60,6),
  ('94000000-0000-4000-8400-000000000014','94000000-0000-4000-8300-000000000009','2026-06-01',60,6),
  ('94000000-0000-4000-8400-000000000015','94000000-0000-4000-8300-000000000010','2024-06-01',60,6),
  ('94000000-0000-4000-8400-000000000016','94000000-0000-4000-8300-000000000011','2026-06-01',60,6),
  ('94000000-0000-4000-8400-000000000017','94000000-0000-4000-8300-000000000012','2026-09-01',0,0),
  ('94000000-0000-4000-8400-000000000018','94000000-0000-4000-8300-000000000013','2026-06-01',60,6);

insert into public.management_periods(
  id, protected_person_id, start_date, end_date, status, closed_at
) values (
  '94000000-0000-4000-8500-000000000001',
  '94000000-0000-4000-8100-000000000001',
  '2024-01-01', '2024-12-31', 'closed', now()
);

insert into public.management_reports(
  id, protected_person_id, report_year, period_start, period_end,
  status, generated_at, created_by
) values (
  '94000000-0000-4000-8600-000000000001',
  '94000000-0000-4000-8100-000000000001',
  2026, '2026-01-01', '2026-12-31', 'generated', now(),
  '94000000-0000-4000-8000-000000000001'
);

insert into public.management_reports(
  id, protected_person_id, report_year, period_start, period_end,
  status, generated_at, finalized_at, created_by
) values (
  '94000000-0000-4000-8600-000000000002',
  '94000000-0000-4000-8100-000000000001',
  2027, '2027-01-01', '2027-12-31', 'finalized', now(), now(),
  '94000000-0000-4000-8000-000000000001'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','94000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"94000000-0000-4000-8000-000000000001","role":"authenticated"}',true);

select extensions.is(
  public.correct_debt_balance(
    '94000000-0000-4000-8100-000000000001',
    '94000000-0000-4000-8300-000000000001',
    '94000000-0000-4000-8400-000000000002',
    1, '2026-06-01', 55, 6, 'CRD rectifie'
  ),
  2::bigint,
  'le CRD est corrige avec une nouvelle revision'
);
select extensions.is(
  (select remaining_balance from public.debt_balances where id='94000000-0000-4000-8400-000000000002'),
  55.00::numeric,
  'le nouveau CRD est conserve'
);
select extensions.is(
  public.correct_debt_balance(
    '94000000-0000-4000-8100-000000000001',
    '94000000-0000-4000-8300-000000000001',
    '94000000-0000-4000-8400-000000000002',
    2, '2026-07-01', 55, 6, 'Date rectifiee'
  ),
  3::bigint,
  'la date est corrigee'
);
select extensions.is(
  public.correct_debt_balance(
    '94000000-0000-4000-8100-000000000001',
    '94000000-0000-4000-8300-000000000001',
    '94000000-0000-4000-8400-000000000002',
    3, '2026-07-01', 55, 5, 'Duree rectifiee'
  ),
  4::bigint,
  'la duree restante est corrigee'
);
select extensions.is(
  (select count(*) from public.debt_balance_changes where debt_balance_id='94000000-0000-4000-8400-000000000002'),
  3::bigint,
  'chaque correction produit une trace'
);
select extensions.is(
  (select old_values->>'remaining_balance' from public.debt_balance_changes
   where debt_balance_id='94000000-0000-4000-8400-000000000002'
   order by changed_at, id limit 1),
  '60.00',
  'l ancien CRD est audite'
);
select extensions.is(
  (select changed_by from public.debt_balance_changes
   where debt_balance_id='94000000-0000-4000-8400-000000000002'
   order by changed_at, id limit 1),
  '94000000-0000-4000-8000-000000000001'::uuid,
  'l auteur authentifie est audite'
);
select extensions.is(
  (select current_balance from public.debts where id='94000000-0000-4000-8300-000000000001'),
  20.00::numeric,
  'corriger une situation ancienne conserve la situation courante plus recente'
);
select extensions.ok(
  (select revision > 4 from public.debts where id='94000000-0000-4000-8300-000000000001'),
  'les corrections incrementent la revision globale de la dette'
);
select extensions.is(
  public.correct_debt_balance(
    '94000000-0000-4000-8100-000000000001',
    '94000000-0000-4000-8300-000000000001',
    '94000000-0000-4000-8400-000000000003',
    1, '2026-09-01', 18, 2, 'CRD courant rectifie'
  ),
  2::bigint,
  'la situation courante peut etre corrigee'
);
select extensions.is(
  (select current_balance from public.debts where id='94000000-0000-4000-8300-000000000001'),
  18.00::numeric,
  'la correction courante actualise le CRD utilise par le patrimoine net'
);

select extensions.is(
  public.cancel_debt_balance(
    '94000000-0000-4000-8100-000000000001',
    '94000000-0000-4000-8300-000000000002',
    '94000000-0000-4000-8400-000000000004',
    1, 'Situation ancienne saisie par erreur'
  ),
  2::bigint,
  'une situation ancienne peut etre annulee'
);
select extensions.is(
  (select current_balance from public.debts where id='94000000-0000-4000-8300-000000000002'),
  50.00::numeric,
  'annuler une situation ancienne conserve le CRD courant'
);
select extensions.is(
  public.cancel_debt_balance(
    '94000000-0000-4000-8100-000000000001',
    '94000000-0000-4000-8300-000000000003',
    '94000000-0000-4000-8400-000000000007',
    1, 'Situation courante incorrecte'
  ),
  2::bigint,
  'la situation courante peut etre annulee'
);
select extensions.is(
  (select current_balance from public.debts where id='94000000-0000-4000-8300-000000000003'),
  100.00::numeric,
  'le CRD courant revient a la situation active precedente'
);
select extensions.is(
  (select current_balance_date from public.debts where id='94000000-0000-4000-8300-000000000003'),
  '2026-01-01'::date,
  'la date courante revient a la situation active precedente'
);
select extensions.is(
  public.cancel_debt_balance(
    '94000000-0000-4000-8100-000000000001',
    '94000000-0000-4000-8300-000000000004',
    '94000000-0000-4000-8400-000000000008',
    1, 'Unique situation incorrecte'
  ),
  2::bigint,
  'la derniere situation active peut etre annulee'
);
select extensions.is(
  (select current_balance from public.debts where id='94000000-0000-4000-8300-000000000004'),
  null::numeric,
  'une dette sans situation active retrouve un CRD inconnu'
);
select extensions.is(
  (select current_balance_date from public.debts where id='94000000-0000-4000-8300-000000000004'),
  null::date,
  'une dette sans situation active ne conserve aucune date courante'
);
select extensions.is(
  (select count(*) from public.debt_balances
   where debt_id='94000000-0000-4000-8300-000000000004' and cancelled_at is null),
  0::bigint,
  'les situations annulees sont exclues des lectures metier actives'
);
select extensions.is(
  (select change_type from public.debt_balance_changes
   where debt_balance_id='94000000-0000-4000-8400-000000000008'),
  'cancellation',
  'l annulation est qualifiee dans le journal'
);
select extensions.is(
  (select reason from public.debt_balance_changes
   where debt_balance_id='94000000-0000-4000-8400-000000000008'),
  'Unique situation incorrecte',
  'le motif d annulation est conserve'
);
insert into public.debt_balances(
  id, debt_id, balance_date, remaining_balance, remaining_duration_months
) values (
  '94000000-0000-4000-8400-000000000019',
  '94000000-0000-4000-8300-000000000004',
  '2026-06-01', 30, 3
);
select extensions.is(
  (select current_balance from public.debts where id='94000000-0000-4000-8300-000000000004'),
  30.00::numeric,
  'une nouvelle situation active peut reutiliser la date d une situation annulee'
);

select extensions.throws_ok(
  $$select public.correct_debt_balance(
    '94000000-0000-4000-8100-000000000001','94000000-0000-4000-8300-000000000005',
    '94000000-0000-4000-8400-000000000009',1,'2026-06-01',80,8,'Collision'
  )$$,
  '23505', 'Une situation active existe deja a cette date.',
  'une collision avec une autre situation active est refusee'
);
select extensions.throws_ok(
  $$select public.correct_debt_balance(
    '94000000-0000-4000-8100-000000000001','94000000-0000-4000-8300-000000000013',
    '94000000-0000-4000-8400-000000000018',2,'2026-06-01',50,5,'Revision ancienne'
  )$$,
  '40001', 'La situation de dette a ete modifiee par une autre operation.',
  'une revision perimee est refusee'
);
select extensions.throws_ok(
  $$select public.correct_debt_balance(
    '94000000-0000-4000-8100-000000000001','94000000-0000-4000-8300-000000000013',
    '94000000-0000-4000-8400-000000000018',1,'2026-06-01',50,5,'   '
  )$$,
  '23514', 'Le motif de la correction est obligatoire.',
  'le motif de correction est obligatoire'
);
select extensions.throws_ok(
  $$select public.cancel_debt_balance(
    '94000000-0000-4000-8100-000000000001','94000000-0000-4000-8300-000000000013',
    '94000000-0000-4000-8400-000000000018',1,'   '
  )$$,
  '23514', 'Le motif de l annulation est obligatoire.',
  'le motif d annulation est obligatoire'
);
select extensions.throws_ok(
  $$select public.cancel_debt_balance(
    '94000000-0000-4000-8100-000000000001','94000000-0000-4000-8300-000000000004',
    '94000000-0000-4000-8400-000000000008',2,'Seconde annulation'
  )$$,
  '23514', 'Cette situation de dette est deja annulee.',
  'une seconde annulation est refusee'
);
select extensions.throws_ok(
  $$update public.debt_balances set remaining_balance=1 where id='94000000-0000-4000-8400-000000000003'$$,
  '42501', 'permission denied for table debt_balances',
  'un acces direct ne permet aucune modification non auditee'
);
select extensions.throws_ok(
  $$delete from public.debt_balances where id='94000000-0000-4000-8400-000000000003'$$,
  '42501', 'permission denied for table debt_balances',
  'un acces direct ne permet aucune suppression physique'
);
select extensions.throws_ok(
  $$insert into public.debt_balances(
    id,debt_id,balance_date,remaining_balance,revision,cancelled_at,cancelled_by,cancellation_reason
  ) values (
    '94000000-0000-4000-8400-000000000020','94000000-0000-4000-8300-000000000013',
    '2026-07-01',50,1,clock_timestamp(),'94000000-0000-4000-8000-000000000001','Insertion annulee'
  )$$,
  '23514', 'Une nouvelle situation de dette ne peut pas etre creee comme annulee.',
  'une situation ne peut pas etre inseree directement comme annulee'
);

select extensions.ok(
  (select refresh_required_at is not null
   from public.management_reports where id='94000000-0000-4000-8600-000000000001'),
  'une correction retroactive invalide le projet genere concerne'
);
select extensions.ok(
  (select refresh_required_at is null
   from public.management_reports where id='94000000-0000-4000-8600-000000000002'),
  'un compte finalise n est jamais modifie automatiquement'
);

reset role;
select extensions.throws_ok(
  $$update public.debt_balance_changes set reason='Alteration' where debt_balance_id='94000000-0000-4000-8400-000000000002'$$,
  '23514', 'Une trace de correction de situation de dette est immuable.',
  'le journal reste immuable meme pour un acces privilegie'
);
select extensions.throws_ok(
  $$update public.debt_balances set remaining_balance=1 where id='94000000-0000-4000-8400-000000000003'$$,
  '42501', 'La correction ou l annulation doit utiliser le parcours dedie.',
  'le trigger bloque une modification privilegiee sans permis interne'
);
select extensions.throws_ok(
  $$delete from public.debt_balances where id='94000000-0000-4000-8400-000000000003'$$,
  '42501', 'Une situation de dette ne peut pas etre supprimee physiquement.',
  'le trigger bloque aussi une suppression privilegiee'
);
select extensions.throws_ok(
  $$delete from public.debt_balance_changes where debt_balance_id='94000000-0000-4000-8400-000000000002'$$,
  '23514', 'Une trace de correction de situation de dette est immuable.',
  'une trace ne peut pas etre supprimee'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','94000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"94000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select extensions.is(
  public.correct_debt_balance(
    '94000000-0000-4000-8100-000000000001','94000000-0000-4000-8300-000000000006',
    '94000000-0000-4000-8400-000000000011',1,'2026-06-01',58,5,'Correction gestionnaire'
  ),
  2::bigint,
  'un gestionnaire peut corriger une situation'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','94000000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"94000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select extensions.throws_ok(
  $$select public.correct_debt_balance(
    '94000000-0000-4000-8100-000000000001','94000000-0000-4000-8300-000000000007',
    '94000000-0000-4000-8400-000000000012',1,'2026-06-01',58,5,'Tentative lecteur'
  )$$,
  '42501', 'Droits insuffisants pour corriger cette situation de dette.',
  'un lecteur ne peut pas corriger une situation'
);
select extensions.ok(
  (select count(*) > 0 from public.debt_balance_changes),
  'un lecteur autorise peut consulter le journal du dossier'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','94000000-0000-4000-8000-000000000004',true);
select set_config('request.jwt.claims','{"sub":"94000000-0000-4000-8000-000000000004","role":"authenticated"}',true);
select extensions.throws_ok(
  $$select public.cancel_debt_balance(
    '94000000-0000-4000-8100-000000000001','94000000-0000-4000-8300-000000000007',
    '94000000-0000-4000-8400-000000000012',1,'Tentative exterieure'
  )$$,
  '42501', 'Droits insuffisants pour annuler cette situation de dette.',
  'un utilisateur exterieur ne peut pas annuler une situation'
);
select extensions.is(
  (select count(*) from public.debt_balance_changes),
  0::bigint,
  'RLS masque le journal des autres dossiers'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','94000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"94000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select extensions.throws_ok(
  $$select public.correct_debt_balance(
    '94000000-0000-4000-8100-000000000001','94000000-0000-4000-8300-000000000010',
    '94000000-0000-4000-8400-000000000015',1,'2026-05-01',55,5,'Ancienne date close'
  )$$,
  '23514', 'Cette situation appartient a un exercice cloture. Elle ne peut plus etre corrigee ni annulee.',
  'une situation issue d un exercice cloture reste immuable'
);
select extensions.throws_ok(
  $$select public.correct_debt_balance(
    '94000000-0000-4000-8100-000000000001','94000000-0000-4000-8300-000000000011',
    '94000000-0000-4000-8400-000000000016',1,'2024-05-01',55,5,'Nouvelle date close'
  )$$,
  '23514', 'Cette situation appartient a un exercice cloture. Elle ne peut plus etre corrigee ni annulee.',
  'une situation ne peut pas etre deplacee dans un exercice cloture'
);

reset role;
select set_config('request.jwt.claim.sub','94000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"94000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
update public.protected_persons
set status='archived', archived_at=clock_timestamp()
where id='94000000-0000-4000-8100-000000000003';
set local role authenticated;
select extensions.throws_ok(
  $$select public.correct_debt_balance(
    '94000000-0000-4000-8100-000000000003','94000000-0000-4000-8300-000000000009',
    '94000000-0000-4000-8400-000000000014',1,'2026-06-01',55,5,'Dossier archive'
  )$$,
  'P4R01', 'Ce dossier est archivé. Restaurez-le avant toute modification.',
  'un dossier archive bloque les corrections'
);

select extensions.is(
  public.settle_debt(
    '94000000-0000-4000-8100-000000000001','94000000-0000-4000-8300-000000000012',
    2,'2026-09-01','Dette soldee pour le test'
  ),
  3::bigint,
  'la cloture explicite existante reste fonctionnelle'
);
select extensions.throws_ok(
  $$select public.correct_debt_balance(
    '94000000-0000-4000-8100-000000000001','94000000-0000-4000-8300-000000000012',
    '94000000-0000-4000-8400-000000000017',1,'2026-09-01',1,1,'Apres cloture'
  )$$,
  '23514', 'Une dette soldee ne peut pas etre corrigee.',
  'une dette soldee ne peut pas etre corrigee'
);
select extensions.throws_ok(
  $$select public.cancel_debt_balance(
    '94000000-0000-4000-8100-000000000001','94000000-0000-4000-8300-000000000012',
    '94000000-0000-4000-8400-000000000017',1,'Apres cloture'
  )$$,
  '23514', 'Une dette soldee ne peut pas etre corrigee.',
  'la situation utilisee pour la cloture ne peut pas etre annulee'
);
select extensions.is(
  (select count(*) from public.debt_status_changes
   where balance_id='94000000-0000-4000-8400-000000000017'),
  1::bigint,
  'la situation de cloture reste rattachee a son audit de statut'
);

select extensions.throws_ok(
  $$select public.cancel_debt_balance(
    '94000000-0000-4000-8100-000000000001','94000000-0000-4000-8300-000000000003',
    '94000000-0000-4000-8400-000000000007',2,'Nouvelle annulation'
  )$$,
  '23514', 'Cette situation de dette est deja annulee.',
  'une situation annulee ne peut pas etre reutilisee'
);

select * from extensions.finish();
rollback;
