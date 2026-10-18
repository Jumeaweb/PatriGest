begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

select extensions.has_column(
  'public', 'protected_persons', 'archive_revision',
  'les dossiers portent une révision de cycle de vie'
);
select extensions.has_table(
  'public', 'protected_person_archive_changes',
  'le journal des transitions de dossiers existe'
);
select extensions.has_function(
  'public', 'archive_protected_person', array['uuid','bigint','text'],
  'la RPC d’archivage existe'
);
select extensions.has_function(
  'public', 'restore_protected_person', array['uuid','bigint','text'],
  'la RPC de restauration existe'
);
select extensions.has_trigger(
  'public', 'protected_persons', 'protected_persons_protect_archive_state',
  'les transitions directes sont protégées'
);
select extensions.has_trigger(
  'public', 'protected_person_archive_changes',
  'protected_person_archive_changes_immutable',
  'le journal est immuable'
);
select extensions.ok(
  (select bool_and(procedure.prosecdef and procedure.proconfig = array['search_path=""'])
   from pg_proc procedure
   where procedure.oid in (
     'public.archive_protected_person(uuid,bigint,text)'::regprocedure,
     'public.restore_protected_person(uuid,bigint,text)'::regprocedure
   )),
  'les RPC sont SECURITY DEFINER avec un search_path vide'
);
select extensions.ok(
  has_function_privilege('authenticated', 'public.archive_protected_person(uuid,bigint,text)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.restore_protected_person(uuid,bigint,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.archive_protected_person(uuid,bigint,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.restore_protected_person(uuid,bigint,text)', 'EXECUTE'),
  'seuls les utilisateurs authentifiés peuvent appeler les RPC publiques'
);
select extensions.ok(
  has_table_privilege('authenticated', 'public.protected_person_archive_changes', 'SELECT')
  and not has_table_privilege('authenticated', 'public.protected_person_archive_changes', 'INSERT')
  and not has_table_privilege('authenticated', 'public.protected_person_archive_changes', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.protected_person_archive_changes', 'DELETE'),
  'le journal applicatif est strictement en lecture seule'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) select
  '00000000-0000-0000-0000-000000000000'::uuid,
  ('97000000-0000-4000-8000-' || lpad(user_number::text, 12, '0'))::uuid,
  'authenticated', 'authenticated',
  'archive-dossier-' || user_number || '@example.test',
  'test', now(), '{}', '{}', now(), now()
from generate_series(1, 8) user_number;

update public.application_user_authorizations
set status = 'active', status_changed_at = now()
where user_id::text like '97000000-0000-4000-8000-%';

update public.application_user_authorizations
set account_mode = 'autonomous'
where user_id in (
  '97000000-0000-4000-8000-000000000001',
  '97000000-0000-4000-8000-000000000005',
  '97000000-0000-4000-8000-000000000006',
  '97000000-0000-4000-8000-000000000007'
);

insert into public.platform_administrators(user_id)
values ('97000000-0000-4000-8000-000000000004');

insert into public.account_subscriptions(
  owner_id, plan_key, dossier_capacity_key, status, started_at, ended_at
) values
  ('97000000-0000-4000-8000-000000000001',null,null,'development',now(),null),
  ('97000000-0000-4000-8000-000000000005','essential','included','active',now(),null),
  ('97000000-0000-4000-8000-000000000006',null,null,'development',now(),null),
  ('97000000-0000-4000-8000-000000000007',null,null,'development',now(),null);

insert into public.protected_persons(
  id, owner_id, first_name, last_name, status, archived_at
) values
  ('97000000-0000-4000-8101-000000000101','97000000-0000-4000-8000-000000000001','Cycle','Principal','active',null),
  ('97000000-0000-4000-8101-000000000102','97000000-0000-4000-8000-000000000001','Cycle','Vide','active',null),
  ('97000000-0000-4000-8101-000000000103','97000000-0000-4000-8000-000000000001','Archive','Antérieure','archived',now()),
  ('97000000-0000-4000-8105-000000000101','97000000-0000-4000-8000-000000000005','Quota','Actif un','active',null),
  ('97000000-0000-4000-8105-000000000102','97000000-0000-4000-8000-000000000005','Quota','Actif deux','active',null),
  ('97000000-0000-4000-8105-000000000103','97000000-0000-4000-8000-000000000005','Quota','Archive','archived',now()),
  ('97000000-0000-4000-8106-000000000101','97000000-0000-4000-8000-000000000006','Autre','Propriétaire','active',null),
  ('97000000-0000-4000-8107-000000000101','97000000-0000-4000-8000-000000000007','Lecture','Partagée','active',null);

insert into public.protected_person_access(
  id, protected_person_id, user_id, role, invited_by
) values
  ('97000000-0000-4000-9000-000000000201','97000000-0000-4000-8101-000000000101','97000000-0000-4000-8000-000000000002','manager','97000000-0000-4000-8000-000000000001'),
  ('97000000-0000-4000-9000-000000000202','97000000-0000-4000-8101-000000000101','97000000-0000-4000-8000-000000000003','read_only','97000000-0000-4000-8000-000000000001'),
  ('97000000-0000-4000-9000-000000000203','97000000-0000-4000-8107-000000000101','97000000-0000-4000-8000-000000000003','read_only','97000000-0000-4000-8000-000000000007');

set local role authenticated;
select set_config('request.jwt.claim.sub','97000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"97000000-0000-4000-8000-000000000001","role":"authenticated"}',true);

select extensions.is(
  public.archive_protected_person(
    '97000000-0000-4000-8101-000000000101', 1, '  Dossier terminé  '
  ),
  2::bigint,
  'le propriétaire archive le dossier et incrémente sa révision'
);
select extensions.ok(
  (select status = 'archived' and archived_at is not null and archive_revision = 2
   from public.protected_persons
   where id = '97000000-0000-4000-8101-000000000101'),
  'l’archivage met à jour atomiquement le statut, la date et la révision'
);
select extensions.ok(
  (select old_status = 'active'
          and new_status = 'archived'
          and changed_by = '97000000-0000-4000-8000-000000000001'
          and reason = 'Dossier terminé'
          and changed_at is not null
   from public.protected_person_archive_changes
   where protected_person_id = '97000000-0000-4000-8101-000000000101'),
  'la trace d’archivage utilise l’auteur et la date serveur'
);

select extensions.is(
  public.restore_protected_person(
    '97000000-0000-4000-8101-000000000101', 2, 'Correction nécessaire'
  ),
  3::bigint,
  'le propriétaire restaure le dossier et incrémente sa révision'
);
select extensions.ok(
  (select status = 'active' and archived_at is null and archive_revision = 3
   from public.protected_persons
   where id = '97000000-0000-4000-8101-000000000101'),
  'la restauration rétablit un état actif cohérent'
);
select extensions.is(
  (select count(*) from public.protected_person_archive_changes
   where protected_person_id = '97000000-0000-4000-8101-000000000101'),
  2::bigint,
  'les deux transitions sont conservées dans l’historique'
);

select extensions.throws_ok(
  $$select public.archive_protected_person('97000000-0000-4000-8101-000000000101',3,'   ')$$,
  'P4A03', 'Le motif de l’archivage est invalide.',
  'un motif vide est refusé'
);
select extensions.throws_ok(
  $$select public.archive_protected_person('97000000-0000-4000-8101-000000000101',3,repeat('x',2001))$$,
  'P4A03', 'Le motif de l’archivage est invalide.',
  'un motif trop long est refusé'
);
select extensions.throws_ok(
  $$select public.archive_protected_person('97000000-0000-4000-8101-000000000101',2,'Révision ancienne')$$,
  'P4A05', 'La révision du dossier est obsolète.',
  'une révision incorrecte est refusée'
);
select extensions.throws_ok(
  $$select public.archive_protected_person('97000000-0000-4000-8199-000000000999',1,'Dossier absent')$$,
  'P4A02', 'Dossier introuvable.',
  'un dossier inexistant produit une erreur distincte'
);

select extensions.is(
  public.archive_protected_person(
    '97000000-0000-4000-8101-000000000101',3,'Double soumission'
  ),
  4::bigint,
  'la première soumission est acceptée'
);
select extensions.throws_ok(
  $$select public.archive_protected_person('97000000-0000-4000-8101-000000000101',3,'Double soumission')$$,
  'P4A05', 'La révision du dossier est obsolète.',
  'la répétition de la même soumission est refusée'
);
select extensions.throws_ok(
  $$select public.archive_protected_person('97000000-0000-4000-8101-000000000101',4,'Déjà archivé')$$,
  'P4A04', 'Le dossier ne peut pas être archivé dans son état actuel.',
  'un état source incompatible est refusé'
);

select extensions.throws_ok(
  $$update public.protected_persons
    set status='active', archived_at=null
    where id='97000000-0000-4000-8101-000000000101'$$,
  '42501', 'Le cycle de vie du dossier nécessite le parcours dédié.',
  'une transition directe est refusée'
);
select extensions.throws_ok(
  $$update public.protected_persons
    set archive_revision=5
    where id='97000000-0000-4000-8101-000000000101'$$,
  '42501', 'La révision d’archivage du dossier est gérée automatiquement.',
  'une modification directe de la révision est refusée'
);
select extensions.throws_ok(
  $$insert into public.protected_person_archive_changes(
      protected_person_id,old_status,new_status,changed_by,reason
    ) values (
      '97000000-0000-4000-8101-000000000101','active','archived',
      '97000000-0000-4000-8000-000000000001','Trace directe'
    )$$,
  '42501', 'permission denied for table protected_person_archive_changes',
  'une insertion directe dans le journal est refusée'
);
select extensions.throws_ok(
  $$delete from public.protected_person_archive_changes
    where protected_person_id='97000000-0000-4000-8101-000000000101'$$,
  '42501', 'permission denied for table protected_person_archive_changes',
  'une suppression directe du journal est refusée'
);
select extensions.throws_ok(
  $$update public.protected_person_archive_changes
    set reason='Altération directe'
    where protected_person_id='97000000-0000-4000-8101-000000000101'$$,
  '42501', 'permission denied for table protected_person_archive_changes',
  'une modification directe du journal est refusée'
);

select set_config('request.jwt.claim.sub','97000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"97000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select extensions.throws_ok(
  $$select public.restore_protected_person('97000000-0000-4000-8101-000000000101',4,'Gestionnaire')$$,
  'P4A01', 'Accès à la transition du dossier refusé.',
  'un gestionnaire ne peut pas restaurer le dossier'
);
select extensions.is(
  (select count(*) from public.protected_person_archive_changes
   where protected_person_id='97000000-0000-4000-8101-000000000101'),
  3::bigint,
  'un gestionnaire peut lire l’historique autorisé'
);

select set_config('request.jwt.claim.sub','97000000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"97000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
select extensions.throws_ok(
  $$select public.restore_protected_person('97000000-0000-4000-8101-000000000101',4,'Lecteur')$$,
  'P4A01', 'Accès à la transition du dossier refusé.',
  'un lecteur ne peut pas restaurer le dossier'
);
select extensions.is(
  (select count(*) from public.protected_person_archive_changes
   where protected_person_id='97000000-0000-4000-8101-000000000101'),
  3::bigint,
  'un lecteur peut lire l’historique autorisé'
);

select set_config('request.jwt.claim.sub','97000000-0000-4000-8000-000000000004',true);
select set_config('request.jwt.claims','{"sub":"97000000-0000-4000-8000-000000000004","role":"authenticated"}',true);
select extensions.throws_ok(
  $$select public.restore_protected_person('97000000-0000-4000-8101-000000000101',4,'Administrateur')$$,
  'P4A01', 'Accès à la transition du dossier refusé.',
  'un administrateur de plateforme ne peut pas restaurer le dossier'
);

select set_config('request.jwt.claim.sub','97000000-0000-4000-8000-000000000006',true);
select set_config('request.jwt.claims','{"sub":"97000000-0000-4000-8000-000000000006","role":"authenticated"}',true);
select extensions.is(
  (select count(*) from public.protected_person_archive_changes
   where protected_person_id='97000000-0000-4000-8101-000000000101'),
  0::bigint,
  'un autre propriétaire ne voit pas l’historique'
);
select extensions.throws_ok(
  $$select public.restore_protected_person('97000000-0000-4000-8101-000000000101',4,'Autre propriétaire')$$,
  'P4A01', 'Accès à la transition du dossier refusé.',
  'un autre propriétaire ne peut pas restaurer le dossier'
);

select set_config('request.jwt.claim.sub','97000000-0000-4000-8000-000000000005',true);
select set_config('request.jwt.claims','{"sub":"97000000-0000-4000-8000-000000000005","role":"authenticated"}',true);
select extensions.throws_ok(
  $$select public.restore_protected_person('97000000-0000-4000-8105-000000000103',1,'Retour au plafond')$$,
  'P4D01', 'La capacité de dossiers actifs est atteinte.',
  'la restauration est refusée lorsque le quota est atteint'
);
select extensions.ok(
  (select status='archived' and archive_revision=1
   from public.protected_persons
   where id='97000000-0000-4000-8105-000000000103'),
  'l’échec de quota conserve le dossier archivé et sa révision'
);
select extensions.is(
  (select count(*) from public.protected_person_archive_changes
   where protected_person_id='97000000-0000-4000-8105-000000000103'),
  0::bigint,
  'l’échec de quota ne crée aucune trace'
);

select set_config('request.jwt.claim.sub','97000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"97000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select extensions.is(
  (select archive_revision from public.protected_persons
   where id='97000000-0000-4000-8101-000000000103'),
  1::bigint,
  'un dossier déjà archivé reçoit la révision initiale sans faux historique'
);
select extensions.is(
  (select count(*) from public.protected_person_archive_changes
   where protected_person_id='97000000-0000-4000-8101-000000000103'),
  0::bigint,
  'aucune trace historique artificielle n’est créée'
);
select extensions.is(
  public.restore_protected_person(
    '97000000-0000-4000-8101-000000000103',1,'Reprise du dossier historique'
  ),
  2::bigint,
  'un dossier déjà archivé reste restaurable'
);

select extensions.is(
  public.archive_protected_person(
    '97000000-0000-4000-8101-000000000102',1,'Préparation de suppression'
  ),
  2::bigint,
  'un dossier vide peut être archivé avant suppression'
);
select extensions.lives_ok(
  $$select public.delete_empty_protected_person('97000000-0000-4000-8101-000000000102')$$,
  'la suppression contrôlée accepte un dossier vide archivé'
);
select extensions.is(
  (select count(*) from public.protected_persons
   where id='97000000-0000-4000-8101-000000000102'),
  0::bigint,
  'le dossier vide est supprimé'
);
select extensions.is(
  (select count(*) from public.protected_person_archive_changes
   where protected_person_id='97000000-0000-4000-8101-000000000102'),
  0::bigint,
  'son historique est supprimé dans la même transaction'
);

select * from extensions.finish();
rollback;
