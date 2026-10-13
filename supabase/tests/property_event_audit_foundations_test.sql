begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(51);

select extensions.has_table(
  'public', 'property_event_changes',
  'le journal générique des changements immobiliers existe'
);
select extensions.has_trigger(
  'public', 'property_event_changes', 'property_event_changes_immutable',
  'le journal générique est protégé par un trigger d’immuabilité'
);
select extensions.has_trigger(
  'public', 'property_event_changes', 'property_event_changes_validate_links',
  'les rattachements du journal générique sont contrôlés'
);
select extensions.has_trigger(
  'public', 'property_events', 'property_events_protect_closed_period',
  'les événements sont protégés au niveau PostgreSQL contre les périodes clôturées'
);
select extensions.has_trigger(
  'public', 'property_events', 'property_events_protect_lifecycle_foundations',
  'les fondations de révision et d’annulation sont protégées'
);
select extensions.has_column('public', 'property_events', 'revision', 'la révision technique existe');
select extensions.has_column('public', 'property_events', 'cancelled_at', 'la date d’annulation existe');
select extensions.has_column('public', 'property_events', 'cancelled_by', 'l’auteur de l’annulation existe');
select extensions.has_column('public', 'property_events', 'cancellation_reason', 'le motif d’annulation existe');
select extensions.ok(
  (select class.relrowsecurity from pg_class class where class.oid = 'public.property_event_changes'::regclass),
  'le journal générique utilise RLS'
);
select extensions.ok(has_table_privilege('authenticated', 'public.property_event_changes', 'SELECT'), 'les utilisateurs authentifiés peuvent lire les traces autorisées');
select extensions.ok(not has_table_privilege('authenticated', 'public.property_event_changes', 'INSERT'), 'les utilisateurs ne peuvent pas créer une trace');
select extensions.ok(not has_table_privilege('authenticated', 'public.property_event_changes', 'UPDATE'), 'les utilisateurs ne peuvent pas modifier une trace');
select extensions.ok(not has_table_privilege('authenticated', 'public.property_event_changes', 'DELETE'), 'les utilisateurs ne peuvent pas supprimer une trace');
select extensions.ok(has_column_privilege('authenticated', 'public.property_events', 'description', 'UPDATE'), 'les colonnes historiques déjà modifiables le restent');
select extensions.ok(not has_column_privilege('authenticated', 'public.property_events', 'revision', 'UPDATE'), 'la révision ne peut pas être fournie par le client');
select extensions.ok(not has_column_privilege('authenticated', 'public.property_events', 'cancelled_at', 'UPDATE'), 'l’annulation ne peut pas être activée directement');
select extensions.ok(not has_column_privilege('authenticated', 'public.property_events', 'cancelled_at', 'INSERT'), 'un événement ne peut pas être créé comme annulé par le client');
select extensions.ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.property_events'::regclass
      and conname = 'property_events_sale_price_positive'
  ),
  'la contrainte de prix de vente strictement positif existe'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '84000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'event-owner@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{"first_name":"Olivia","last_name":"Propriétaire"}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '84000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'event-manager@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{"first_name":"Marc","last_name":"Gestionnaire"}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '84000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'event-reader@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{"first_name":"Lise","last_name":"Lectrice"}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '84000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'event-outsider@example.test', 'test-hash', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

update public.application_user_authorizations
set status = 'active', status_changed_at = now()
where user_id in (
  '84000000-0000-4000-8000-000000000001',
  '84000000-0000-4000-8000-000000000002',
  '84000000-0000-4000-8000-000000000003',
  '84000000-0000-4000-8000-000000000004'
);

update public.profiles set first_name = 'Olivia', last_name = 'Propriétaire' where id = '84000000-0000-4000-8000-000000000001';
update public.profiles set first_name = 'Marc', last_name = 'Gestionnaire' where id = '84000000-0000-4000-8000-000000000002';

insert into public.protected_persons (id, owner_id, first_name, last_name)
values
  ('84000000-0000-4000-8000-000000000101', '84000000-0000-4000-8000-000000000001', 'Dossier', 'Principal'),
  ('84000000-0000-4000-8000-000000000102', '84000000-0000-4000-8000-000000000004', 'Dossier', 'Étranger');

insert into public.protected_person_access (id, protected_person_id, user_id, role, invited_by)
values
  ('84000000-0000-4000-8000-000000000201', '84000000-0000-4000-8000-000000000101', '84000000-0000-4000-8000-000000000002', 'manager', '84000000-0000-4000-8000-000000000001'),
  ('84000000-0000-4000-8000-000000000202', '84000000-0000-4000-8000-000000000101', '84000000-0000-4000-8000-000000000003', 'read_only', '84000000-0000-4000-8000-000000000001');

insert into public.real_estate_properties (
  id, protected_person_id, property_type, designation, entry_date, status
)
values
  ('84000000-0000-4000-8000-000000000301', '84000000-0000-4000-8000-000000000101', 'house', 'Bien avec événement clôturé', '2020-01-01', 'active'),
  ('84000000-0000-4000-8000-000000000302', '84000000-0000-4000-8000-000000000101', 'apartment', 'Bien avec événement ouvert', '2020-01-01', 'active'),
  ('84000000-0000-4000-8000-000000000303', '84000000-0000-4000-8000-000000000101', 'land', 'Bien vendu positif', '2020-01-01', 'active'),
  ('84000000-0000-4000-8000-000000000304', '84000000-0000-4000-8000-000000000101', 'commercial', 'Bien vente nulle', '2020-01-01', 'active'),
  ('84000000-0000-4000-8000-000000000305', '84000000-0000-4000-8000-000000000102', 'house', 'Bien étranger', '2020-01-01', 'active'),
  ('84000000-0000-4000-8000-000000000306', '84000000-0000-4000-8000-000000000101', 'house', 'Bien vendu en période clôturée', '2020-01-01', 'active');

insert into public.property_events (
  id, property_id, protected_person_id, event_type, event_date, description, amount
)
values
  ('84000000-0000-4000-8000-000000000501', '84000000-0000-4000-8000-000000000301', '84000000-0000-4000-8000-000000000101', 'significant_change', '2025-05-01', 'Événement qui sera clôturé', 1000),
  ('84000000-0000-4000-8000-000000000502', '84000000-0000-4000-8000-000000000302', '84000000-0000-4000-8000-000000000101', 'acquisition', '2026-02-01', 'Acquisition ouverte', 120000),
  ('84000000-0000-4000-8000-000000000503', '84000000-0000-4000-8000-000000000305', '84000000-0000-4000-8000-000000000102', 'inheritance', '2026-01-10', 'Événement étranger', 80000),
  ('84000000-0000-4000-8000-000000000504', '84000000-0000-4000-8000-000000000303', '84000000-0000-4000-8000-000000000101', 'sale', '2026-08-15', 'Vente positive', 150000),
  ('84000000-0000-4000-8000-000000000506', '84000000-0000-4000-8000-000000000306', '84000000-0000-4000-8000-000000000101', 'sale', '2025-07-01', 'Vente avant clôture', 175000);

insert into public.management_periods (
  id, protected_person_id, start_date, end_date, status, closed_at
)
values
  ('84000000-0000-4000-8000-000000000601', '84000000-0000-4000-8000-000000000101', '2025-01-01', '2025-12-31', 'closed', now()),
  ('84000000-0000-4000-8000-000000000602', '84000000-0000-4000-8000-000000000101', '2026-01-01', '2026-12-31', 'open', null);

select set_config('request.jwt.claim.sub', '84000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"84000000-0000-4000-8000-000000000001","role":"authenticated"}', true);

insert into public.property_event_changes (
  id, property_event_id, property_id, protected_person_id, change_type,
  old_values, new_values, reason, changed_by, changed_by_name
)
values (
  '84000000-0000-4000-8000-000000000701',
  '84000000-0000-4000-8000-000000000502',
  '84000000-0000-4000-8000-000000000302',
  '84000000-0000-4000-8000-000000000101',
  'correction',
  '{"description":"Acquisition"}'::jsonb,
  '{"description":"Acquisition ouverte"}'::jsonb,
  'Trace technique de test',
  '84000000-0000-4000-8000-000000000004',
  'Faux auteur fourni'
);

select extensions.is(
  (select count(*) from public.property_events where revision = 1 and cancelled_at is null),
  5::bigint,
  'les événements existants reçoivent une révision initiale sans être annulés'
);
select extensions.is((select changed_by from public.property_event_changes where id = '84000000-0000-4000-8000-000000000701'), '84000000-0000-4000-8000-000000000001'::uuid, 'l’auteur est imposé depuis le contexte authentifié');
select extensions.is((select changed_by_name from public.property_event_changes where id = '84000000-0000-4000-8000-000000000701'), 'Olivia Propriétaire', 'le nom de l’auteur est dérivé du profil fiable');

set local role authenticated;
select set_config('request.jwt.claim.sub', '84000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"84000000-0000-4000-8000-000000000001","role":"authenticated"}', true);

select extensions.is((select count(*) from public.property_event_changes), 1::bigint, 'le propriétaire peut consulter le journal de son dossier');
select extensions.throws_ok(
  $$insert into public.property_event_changes (
      property_event_id, property_id, protected_person_id, change_type,
      old_values, new_values, reason, changed_by, changed_by_name
    ) values (
      '84000000-0000-4000-8000-000000000502',
      '84000000-0000-4000-8000-000000000302',
      '84000000-0000-4000-8000-000000000101',
      'correction', '{}'::jsonb, '{}'::jsonb, 'Auteur falsifié',
      '84000000-0000-4000-8000-000000000004', 'Faux auteur'
    )$$,
  '42501', null,
  'un utilisateur ne peut pas falsifier l’auteur en créant lui-même une trace'
);
select extensions.throws_ok(
  $$insert into public.property_events (
      property_id, protected_person_id, event_type, event_date, description
    ) values (
      '84000000-0000-4000-8000-000000000301',
      '84000000-0000-4000-8000-000000000101',
      'significant_change', '2025-06-01', 'Insertion clôturée'
    )$$,
  'P0001',
  'Cet événement appartient à un exercice clôturé. Il ne peut plus être modifié ni annulé. Si vous constatez une erreur, veuillez contacter l''assistance PatriGest.',
  'le propriétaire ne peut pas insérer un événement dans un exercice clôturé'
);
select extensions.throws_ok(
  $$update public.property_events set description = 'Modification clôturée' where id = '84000000-0000-4000-8000-000000000501'$$,
  'P0001',
  'Cet événement appartient à un exercice clôturé. Il ne peut plus être modifié ni annulé. Si vous constatez une erreur, veuillez contacter l''assistance PatriGest.',
  'une modification directe dans un exercice clôturé est refusée'
);
select extensions.throws_ok(
  $$update public.property_events set event_date = '2026-02-01' where id = '84000000-0000-4000-8000-000000000501'$$,
  'P0001',
  'Cet événement appartient à un exercice clôturé. Il ne peut plus être modifié ni annulé. Si vous constatez une erreur, veuillez contacter l''assistance PatriGest.',
  'la date d’un événement ne peut pas sortir d’un exercice clôturé'
);
select extensions.throws_ok(
  $$update public.property_events set event_date = '2025-06-01' where id = '84000000-0000-4000-8000-000000000502'$$,
  'P0001',
  'Cet événement appartient à un exercice clôturé. Il ne peut plus être modifié ni annulé. Si vous constatez une erreur, veuillez contacter l''assistance PatriGest.',
  'la date d’un événement ne peut pas entrer dans un exercice clôturé'
);
select extensions.lives_ok(
  $$update public.property_events set description = 'Acquisition corrigée en période ouverte' where id = '84000000-0000-4000-8000-000000000502'$$,
  'un événement d’un exercice ouvert reste modifiable par le propriétaire'
);
select extensions.is((select revision from public.property_events where id = '84000000-0000-4000-8000-000000000502'), 2::bigint, 'une modification réussie incrémente la révision');
select extensions.throws_ok(
  $$update public.property_events set cancelled_at = now(), cancelled_by = '84000000-0000-4000-8000-000000000001', cancellation_reason = 'Tentative directe' where id = '84000000-0000-4000-8000-000000000502'$$,
  '42501', null,
  'les colonnes d’annulation ne sont pas modifiables directement'
);
select extensions.throws_ok(
  $$update public.property_events set revision = 99 where id = '84000000-0000-4000-8000-000000000502'$$,
  '42501', null,
  'la révision ne peut pas être falsifiée par le client'
);
select extensions.throws_ok(
  $$insert into public.property_events (
      property_id, protected_person_id, event_type, event_date, description, amount
    ) values (
      '84000000-0000-4000-8000-000000000304',
      '84000000-0000-4000-8000-000000000101',
      'sale', '2026-09-01', 'Vente gratuite incorrecte', 0
    )$$,
  '23514', 'Le prix de vente doit être strictement positif.',
  'une nouvelle vente à prix nul est refusée'
);
select extensions.is((select status from public.real_estate_properties where id = '84000000-0000-4000-8000-000000000304'), 'active', 'le refus d’un prix nul conserve le bien actif');
select extensions.lives_ok(
  $$select public.correct_property_sale_price(
      '84000000-0000-4000-8000-000000000101',
      '84000000-0000-4000-8000-000000000303',
      '84000000-0000-4000-8000-000000000504',
      150000, 155000, 'Correction positive conservée'
    )$$,
  'la correction existante d’un prix positif reste opérationnelle'
);
select extensions.is((select amount from public.property_events where id = '84000000-0000-4000-8000-000000000504'), 155000.00::numeric, 'le nouveau prix positif est enregistré');
select extensions.is((select revision from public.property_events where id = '84000000-0000-4000-8000-000000000504'), 2::bigint, 'la correction du prix incrémente aussi la révision');
select extensions.is((select count(*) from public.property_sale_price_corrections where property_event_id = '84000000-0000-4000-8000-000000000504'), 1::bigint, 'l’audit spécialisé du prix reste alimenté');
select extensions.throws_ok(
  $$select public.correct_property_sale_price(
      '84000000-0000-4000-8000-000000000101',
      '84000000-0000-4000-8000-000000000306',
      '84000000-0000-4000-8000-000000000506',
      175000, 176000, 'Correction clôturée'
    )$$,
  'P0001', 'Cette vente appartient à un exercice clôturé.',
  'la correction existante reste refusée dans un exercice clôturé'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '84000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"84000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
select extensions.lives_ok(
  $$update public.property_events set description = 'Acquisition modifiée par le gestionnaire' where id = '84000000-0000-4000-8000-000000000502'$$,
  'le gestionnaire peut encore modifier un événement ouvert'
);
select extensions.is((select revision from public.property_events where id = '84000000-0000-4000-8000-000000000502'), 3::bigint, 'la modification du gestionnaire incrémente la révision');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '84000000-0000-4000-8000-000000000003', true);
select set_config('request.jwt.claims', '{"sub":"84000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
update public.property_events
set description = 'Modification interdite au lecteur'
where id = '84000000-0000-4000-8000-000000000502';
select extensions.is((select description from public.property_events where id = '84000000-0000-4000-8000-000000000502'), 'Acquisition modifiée par le gestionnaire', 'le lecteur ne peut pas modifier un événement');
select extensions.is((select count(*) from public.property_event_changes), 1::bigint, 'le lecteur peut consulter le journal autorisé');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '84000000-0000-4000-8000-000000000004', true);
select set_config('request.jwt.claims', '{"sub":"84000000-0000-4000-8000-000000000004","role":"authenticated"}', true);
select extensions.is((select count(*) from public.property_event_changes), 0::bigint, 'un utilisateur étranger ne voit aucune trace');

reset role;
select extensions.throws_ok(
  $$insert into public.property_event_changes (
      property_event_id, property_id, protected_person_id, change_type,
      old_values, new_values, reason, changed_by, changed_by_name
    ) values (
      '84000000-0000-4000-8000-000000000502',
      '84000000-0000-4000-8000-000000000301',
      '84000000-0000-4000-8000-000000000101',
      'correction', '{}'::jsonb, '{}'::jsonb, 'Mauvais rattachement',
      '84000000-0000-4000-8000-000000000001', 'Olivia Propriétaire'
    )$$,
  'P0001', 'La trace ne correspond pas à l’événement immobilier indiqué.',
  'une trace privilégiée ne peut pas viser un mauvais bien'
);
select extensions.throws_ok(
  $$insert into public.property_events (
      property_id, protected_person_id, event_type, event_date, description,
      cancelled_at, cancelled_by, cancellation_reason
    ) values (
      '84000000-0000-4000-8000-000000000302',
      '84000000-0000-4000-8000-000000000101',
      'significant_change', '2026-03-01', 'Création annulée', now(),
      '84000000-0000-4000-8000-000000000001', 'Création invalide'
    )$$,
  'P0001', 'Un nouvel événement immobilier ne peut pas être créé comme annulé.',
  'même une insertion privilégiée ne crée pas un événement déjà annulé'
);
select extensions.throws_ok(
  $$update public.property_event_changes set reason = 'Altération' where id = '84000000-0000-4000-8000-000000000701'$$,
  'P0001', 'Une trace de modification d’événement immobilier est immuable.',
  'même un accès privilégié ne peut pas modifier une trace sans désactiver la protection'
);
select extensions.throws_ok(
  $$delete from public.property_event_changes where id = '84000000-0000-4000-8000-000000000701'$$,
  'P0001', 'Une trace de modification d’événement immobilier est immuable.',
  'même un accès privilégié ne peut pas supprimer une trace sans désactiver la protection'
);
select extensions.throws_ok(
  $$delete from public.property_events where id = '84000000-0000-4000-8000-000000000501'$$,
  'P0001',
  'Cet événement appartient à un exercice clôturé. Il ne peut plus être modifié ni annulé. Si vous constatez une erreur, veuillez contacter l''assistance PatriGest.',
  'une suppression directe privilégiée reste bloquée dans un exercice clôturé'
);
select extensions.is((select count(*) from public.transactions), 0::bigint, 'les fondations ne créent aucune opération bancaire');
select extensions.is((select count(*) from public.property_events where cancelled_at is not null), 0::bigint, 'aucun événement existant n’est annulé automatiquement');

select * from extensions.finish();
rollback;
