begin;
create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

create function pg_temp.fixture(value text) returns uuid language sql immutable as $$
  select md5('administrative-collaborator-counts:' || value)::uuid
$$;
create function pg_temp.actor(value text) returns text language sql as $$
  select set_config('request.jwt.claim.sub', case when value is null then '' else pg_temp.fixture(value)::text end, true)
$$;
create function pg_temp.counts(value text) returns text language sql as $$
  select concat_ws('/', total_count, manager_count, read_only_count)
  from public.list_administrative_collaborator_access_counts(array[pg_temp.fixture(value)])
$$;

insert into auth.users(id, email, raw_user_meta_data)
select pg_temp.fixture(name), name || '@admin-collab.example.test',
  case when name in ('mixed', 'reader', 'unshared') then '{"patrigest_registration_intent":"collaborator"}'::jsonb else '{}'::jsonb end
from unnest(array['admin', 'owner', 'other-owner', 'mixed', 'reader', 'unshared', 'pending']) name;
insert into public.platform_administrators(user_id) values (pg_temp.fixture('admin'));
update public.application_user_authorizations
set status = 'active', status_changed_at = now(), account_mode = registration_intent,
    autonomous_registration_status = case when registration_intent = 'autonomous' then 'active' else null end
where user_id in (pg_temp.fixture('owner'), pg_temp.fixture('other-owner'), pg_temp.fixture('mixed'), pg_temp.fixture('reader'), pg_temp.fixture('unshared'));
insert into public.protected_persons(id, owner_id, first_name, last_name)
select pg_temp.fixture(name), pg_temp.fixture(case when name = 'dossier3' then 'other-owner' else 'owner' end), 'Test', name
from unnest(array['dossier1', 'dossier2', 'dossier3']) name;
insert into public.protected_person_access(protected_person_id, user_id, role, invited_by)
values
  (pg_temp.fixture('dossier1'), pg_temp.fixture('mixed'), 'manager', pg_temp.fixture('owner')),
  (pg_temp.fixture('dossier2'), pg_temp.fixture('mixed'), 'manager', pg_temp.fixture('owner')),
  (pg_temp.fixture('dossier3'), pg_temp.fixture('mixed'), 'read_only', pg_temp.fixture('other-owner')),
  (pg_temp.fixture('dossier1'), pg_temp.fixture('reader'), 'read_only', pg_temp.fixture('owner'));
insert into public.protected_person_invitations(protected_person_id,email,role,token_hash,expires_at,invited_by)
values (pg_temp.fixture('dossier3'),'unshared@admin-collab.example.test','read_only',repeat('a',64),now()+interval '1 day',pg_temp.fixture('other-owner'));
insert into public.account_trials(user_id,terms_version,terms_accepted_at,started_at,ends_at,deletion_eligible_at)
select pg_temp.fixture(name),'fixture',now()-interval '1 day',now()-interval '1 day',now()+interval '29 days',now()+interval '59 days'
from unnest(array['owner', 'other-owner']) name;

select extensions.ok(
  not has_function_privilege('anon','public.list_administrative_collaborator_access_counts(uuid[])','EXECUTE')
  and not has_function_privilege('service_role','public.list_administrative_collaborator_access_counts(uuid[])','EXECUTE')
  and has_function_privilege('authenticated','public.list_administrative_collaborator_access_counts(uuid[])','EXECUTE'),
  'RPC appelable seulement par authenticated avant contrôle métier');
select extensions.ok(
  not has_schema_privilege('authenticated','billing_internal','USAGE')
  and not has_schema_privilege('service_role','billing_internal','USAGE')
  and not has_function_privilege('authenticated','billing_internal.can_read_dossier_as(uuid,uuid)','EXECUTE')
  and not has_function_privilege('service_role','billing_internal.can_manage_dossier_as(uuid,uuid)','EXECUTE')
  and not has_function_privilege('authenticated','public.billing_resolve_entitlements_at(uuid,timestamptz)','EXECUTE')
  and not has_function_privilege('service_role','public.billing_resolve_entitlements_at(uuid,timestamptz)','EXECUTE'),
  'fonctions internes et résolveur restent privés');

set local role anon;
select extensions.throws_ok($$select * from public.list_administrative_collaborator_access_counts('{}')$$, '42501');
reset role;
set local role service_role;
select extensions.throws_ok($$select * from public.list_administrative_collaborator_access_counts('{}')$$, '42501');
reset role;
set local role authenticated;
select pg_temp.actor(null);
select extensions.throws_ok($$select * from public.list_administrative_collaborator_access_counts('{}')$$, '42501','Accès administrateur requis.');
select pg_temp.actor('mixed');
select extensions.throws_ok($$select * from public.list_administrative_collaborator_access_counts('{}')$$, '42501','Accès administrateur requis.');
select extensions.ok(public.can_read_protected_person(pg_temp.fixture('dossier1')) and public.can_manage_protected_person(pg_temp.fixture('dossier1')), 'gestionnaire autorisé par les fonctions publiques');
select extensions.ok(public.can_read_protected_person(pg_temp.fixture('dossier3')) and not public.can_manage_protected_person(pg_temp.fixture('dossier3')), 'lecteur reconnu par les fonctions publiques');
select pg_temp.actor('reader');
select extensions.is((select count(*) from public.protected_persons where id in (pg_temp.fixture('dossier1'),pg_temp.fixture('dossier2'),pg_temp.fixture('dossier3'))),1::bigint,'la RLS du lecteur demeure limitée au dossier partagé');
select pg_temp.actor('owner');
select extensions.ok(public.can_read_protected_person(pg_temp.fixture('dossier2')) and public.can_manage_protected_person(pg_temp.fixture('dossier2')), 'le propriétaire conserve ses droits');

select pg_temp.actor('admin');
select extensions.throws_ok($$select * from public.list_administrative_collaborator_access_counts(array_fill(pg_temp.fixture('mixed'),array[26]))$$, '22023','Liste de comptes invalide.');
select extensions.throws_ok($$select * from public.list_administrative_collaborator_access_counts(array[null::uuid])$$, '22023','Liste de comptes invalide.');
select extensions.is((select count(*) from public.list_administrative_collaborator_access_counts('{}')),0::bigint,'liste vide');
select extensions.is((select count(*) from public.list_administrative_collaborator_access_counts(array[pg_temp.fixture('unknown')])),0::bigint,'compte inexistant ignoré');
select extensions.is((select count(*) from public.list_administrative_collaborator_access_counts(array_fill(pg_temp.fixture('mixed'),array[25]))),1::bigint,'25 identifiants autorisés et dédupliqués');
select extensions.is(pg_temp.counts('mixed'),'3/2/1','rôles mixtes et décompte distinct');
select extensions.is(pg_temp.counts('reader'),'1/0/1','lecture seule');
select extensions.is(pg_temp.counts('unshared'),'0/0/0','une invitation en attente ne compte pas');
select extensions.is(pg_temp.counts('pending'),'0/0/0','un compte en attente ne reçoit aucun accès');
select extensions.is(pg_temp.counts('owner'),'0/0/0','aucun dossier propre ne compte comme partage');
select extensions.is(
  (select array_agg(key order by key) from public.list_administrative_collaborator_access_counts(array[pg_temp.fixture('mixed')]) row_data cross join lateral jsonb_object_keys(to_jsonb(row_data)) key),
  array['manager_count','read_only_count','total_count','user_id']::text[],
  'aucun titre de dossier ni donnée patrimoniale dans la projection');
reset role;

select pg_temp.actor(null);
update public.protected_person_archive_runtime_config set lifecycle_enabled=true where singleton;
set local role authenticated;
select pg_temp.actor('owner');
select public.archive_protected_person(pg_temp.fixture('dossier1'),1,'Recette archivage');
select pg_temp.actor('mixed');
select extensions.ok(public.can_read_protected_person(pg_temp.fixture('dossier1')) and public.can_manage_protected_person(pg_temp.fixture('dossier1')), 'les contrôles publics de lecture et de rôle restent inchangés pour un dossier archivé');
select pg_temp.actor('admin');
select extensions.is(pg_temp.counts('mixed'),'3/1/2','gestionnaire archivé compté en lecture seule');
select extensions.is(pg_temp.counts('reader'),'1/0/1','lecteur archivé toujours compté en lecture seule');
select pg_temp.actor('owner');
select public.restore_protected_person(pg_temp.fixture('dossier1'),2,'Recette restauration');
select pg_temp.actor('admin');
select extensions.is(pg_temp.counts('mixed'),'3/2/1','le désarchivage rétablit le compteur Gestionnaire');
reset role;
select pg_temp.actor(null);
select extensions.is((select role from public.protected_person_access where protected_person_id=pg_temp.fixture('dossier1') and user_id=pg_temp.fixture('mixed')),'manager','la projection ne modifie pas le rôle enregistré');
select extensions.is((select count(*) from public.protected_person_invitations where protected_person_id=pg_temp.fixture('dossier3') and accepted_at is null),1::bigint,'aucune invitation consommée par la projection');

update public.billing_runtime_config set commercial_access_enabled=true,shared_access_enforcement_enabled=true where singleton;
set local role authenticated;
select pg_temp.actor('admin');
select extensions.is(pg_temp.counts('mixed'),'3/2/1','les partages restent accessibles avec les contrôles actifs et le propriétaire en essai');
reset role;
select pg_temp.actor(null);
update public.account_trials set terms_accepted_at=now()-interval '31 days',started_at=now()-interval '31 days',
  ends_at=now()-interval '1 day',deletion_eligible_at=now()+interval '29 days'
where user_id in (pg_temp.fixture('owner'), pg_temp.fixture('other-owner'));
set local role authenticated;
select pg_temp.actor('mixed');
select extensions.is((select count(*) from public.protected_persons where id in (pg_temp.fixture('dossier1'),pg_temp.fixture('dossier2'),pg_temp.fixture('dossier3'))),0::bigint,'aucun dossier visible par RLS après suspension du propriétaire');
select pg_temp.actor('admin');
select extensions.is(pg_temp.counts('mixed'),'0/0/0','les partages suspendus du propriétaire sont exclus');
reset role;
select pg_temp.actor(null);
update public.billing_runtime_config set shared_access_enforcement_enabled=false where singleton;
set local role authenticated;
select pg_temp.actor('admin');
select extensions.is(pg_temp.counts('mixed'),'3/2/1','le comportement historique est conservé quand le contrôle des partages est désactivé');
reset role;
select pg_temp.actor(null);
update public.application_user_authorizations set status='rejected', status_changed_at=now() where user_id=pg_temp.fixture('mixed');
set local role authenticated;
select pg_temp.actor('admin');
select extensions.is(pg_temp.counts('mixed'),'0/0/0','une autorisation collaborateur inactive exclut tous ses partages');
reset role;
select pg_temp.actor(null);
update public.application_user_authorizations set status='active', status_changed_at=now() where user_id=pg_temp.fixture('mixed');
delete from public.protected_person_access where protected_person_id=pg_temp.fixture('dossier2') and user_id=pg_temp.fixture('mixed');
set local role authenticated;
select pg_temp.actor('admin');
select extensions.is(pg_temp.counts('mixed'),'2/1/1','rétablissement des droits sauf partage révoqué');
reset role;

select * from extensions.finish();
rollback;
