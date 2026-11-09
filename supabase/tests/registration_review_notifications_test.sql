begin;
select plan(8);

select extensions.has_table(
  'public',
  'registration_review_notifications',
  'le registre prive des alertes de nouvelles inscriptions existe'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.registration_review_notifications'::regclass),
  'RLS est activee sur le registre'
);

select ok(
  not exists (
    select 1
    from pg_class relation
    cross join lateral aclexplode(coalesce(relation.relacl, acldefault('r', relation.relowner))) privilege
    where relation.oid = 'public.registration_review_notifications'::regclass
      and privilege.grantee = 0
      and privilege.privilege_type in ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
  ),
  'PUBLIC ne dispose d aucun acces direct'
);

select ok(
  not has_table_privilege('anon', 'public.registration_review_notifications', 'SELECT,INSERT,UPDATE,DELETE'),
  'anon ne dispose d aucun acces direct'
);

select ok(
  not has_table_privilege('authenticated', 'public.registration_review_notifications', 'SELECT,INSERT,UPDATE,DELETE'),
  'authenticated ne dispose d aucun acces direct'
);

select ok(
  has_table_privilege('service_role', 'public.registration_review_notifications', 'SELECT,INSERT,UPDATE')
  and not has_table_privilege('service_role', 'public.registration_review_notifications', 'DELETE'),
  'service_role peut suivre les envois sans les supprimer'
);

select col_is_pk(
  'public',
  'registration_review_notifications',
  'user_id',
  'une seule alerte logique est reservee par demande utilisateur'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.registration_review_notifications'::regclass
      and conname = 'registration_review_notifications_sent_check'
  ),
  'un envoi marque sent exige une date d envoi'
);

select * from finish();
rollback;
