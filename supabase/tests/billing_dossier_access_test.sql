begin;
create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

create function pg_temp.billing_id(value text) returns uuid language sql immutable as $$
  select md5('pat-stripe-02d:' || value)::uuid
$$;

insert into auth.users(id, email, raw_user_meta_data)
select pg_temp.billing_id(name), name || '@stripe02d.example.test',
  case when name in ('manager','reader') then '{"patrigest_registration_intent":"collaborator"}'::jsonb else '{}'::jsonb end
from unnest(array['owner','other','manager','reader','outsider']) name;
update public.application_user_authorizations
set status='active', status_changed_at=now(), account_mode=registration_intent,
  autonomous_registration_status=case when registration_intent='autonomous' then 'active' else null end
where user_id in (select pg_temp.billing_id(name) from unnest(array['owner','other','manager','reader','outsider']) name);
update public.application_user_authorizations
set status='active', status_changed_at=now(), account_mode='autonomous', registration_intent='autonomous', autonomous_registration_status='active'
where user_id in (pg_temp.billing_id('owner'),pg_temp.billing_id('other'),pg_temp.billing_id('outsider'));

insert into public.protected_persons(id,owner_id,first_name,last_name)
values (pg_temp.billing_id('dossier'),pg_temp.billing_id('owner'),'Fixture','One'),
       (pg_temp.billing_id('other-dossier'),pg_temp.billing_id('other'),'Fixture','Two');
insert into public.protected_person_access(protected_person_id,user_id,role,invited_by)
values (pg_temp.billing_id('dossier'),pg_temp.billing_id('manager'),'manager',pg_temp.billing_id('owner')),
       (pg_temp.billing_id('dossier'),pg_temp.billing_id('reader'),'read_only',pg_temp.billing_id('owner')),
       (pg_temp.billing_id('other-dossier'),pg_temp.billing_id('manager'),'manager',pg_temp.billing_id('other'));
insert into public.account_trials(user_id,terms_version,terms_accepted_at,started_at,ends_at,deletion_eligible_at)
values (pg_temp.billing_id('owner'),'fixture',now()-interval '1 day',now()-interval '1 day',now()+interval '29 days',now()+interval '59 days');
insert into public.account_trial_legacy_access(user_id,reason)
values (pg_temp.billing_id('other'),'active_before_trial_cutover');

create function pg_temp.use_billing_actor(name text) returns text language sql as $$
  select set_config('request.jwt.claim.sub',pg_temp.billing_id(name)::text,true)
$$;

select pg_temp.use_billing_actor('owner');
select extensions.ok((select can_generate and can_finalize and can_print
  from public.get_management_report_commercial_capabilities(pg_temp.billing_id('dossier'))), 'les capacités CRG historiques sont conservées avec les réglages désactivés');
update public.billing_runtime_config set commercial_access_enabled=true,shared_access_enforcement_enabled=true;

select extensions.ok(public.can_manage_protected_person(pg_temp.billing_id('dossier')),
  'le propriétaire en essai actif peut gérer le dossier');
select extensions.ok((select not can_generate and not can_finalize and not can_print
  from public.get_management_report_commercial_capabilities(pg_temp.billing_id('dossier'))), 'l’essai désactive génération, finalisation et impression');
select extensions.ok((select not can_read and not can_write from public.get_protected_person_feature_capabilities(pg_temp.billing_id('dossier'))
  where feature_key='data_export'), 'l’export est refusé par le contrôle central');
select pg_temp.use_billing_actor('manager');
select extensions.ok(public.can_read_protected_person(pg_temp.billing_id('dossier')) and public.can_manage_protected_person(pg_temp.billing_id('dossier')),
  'le gestionnaire garde ses droits sur le dossier d’un propriétaire en essai');
select extensions.ok((select not can_generate and not can_finalize and not can_print
  from public.get_management_report_commercial_capabilities(pg_temp.billing_id('dossier'))), 'le gestionnaire hérite des restrictions PDF du propriétaire');
select pg_temp.use_billing_actor('reader');
select extensions.ok(public.can_read_protected_person(pg_temp.billing_id('dossier')) and not public.can_manage_protected_person(pg_temp.billing_id('dossier')),
  'le lecteur conserve la lecture seule');
select pg_temp.use_billing_actor('outsider');
select extensions.ok(not public.can_read_protected_person(pg_temp.billing_id('dossier')), 'le tiers reste exclu');
select extensions.throws_ok($$select * from public.get_management_report_commercial_capabilities(pg_temp.billing_id('dossier'))$$,
  '42501', 'Dossier introuvable.', 'la projection ne révèle pas les droits à un tiers');

update public.account_trials set terms_accepted_at=now()-interval '30 days',started_at=now()-interval '30 days',
  ends_at=now(),deletion_eligible_at=now()+interval '30 days' where user_id=pg_temp.billing_id('owner');
select pg_temp.use_billing_actor('owner');
select extensions.ok(not public.can_read_protected_person(pg_temp.billing_id('dossier'))
  and not public.has_application_business_access(pg_temp.billing_id('owner'),now()-interval '1 day'),
  'J30 est atteint même si un instant antérieur est fourni à l’ancienne signature interne');
select pg_temp.use_billing_actor('manager');
select extensions.ok(not public.can_read_protected_person(pg_temp.billing_id('dossier'))
  and public.can_manage_protected_person(pg_temp.billing_id('other-dossier')),
  'la session existante perd exactement le dossier du propriétaire suspendu');
select extensions.is((select count(*) from public.protected_person_access where protected_person_id=pg_temp.billing_id('dossier')),
  2::bigint,'les partages restent enregistrés');

select set_config('request.jwt.claim.sub','',true);
insert into public.account_administrative_plan_assignments(owner_id,plan_key,billing_period,dossier_capacity_key,reason,created_by)
values (pg_temp.billing_id('owner'),'essential','monthly','included','fixture',pg_temp.billing_id('other'));
select pg_temp.use_billing_actor('manager');
select extensions.ok((select can_generate and can_finalize and can_print
  from public.get_management_report_commercial_capabilities(pg_temp.billing_id('dossier'))), 'l’attribution restaure les capacités du partage maintenu');
select set_config('request.jwt.claim.sub','',true);
delete from public.protected_person_access where protected_person_id=pg_temp.billing_id('dossier') and user_id=pg_temp.billing_id('manager');
select pg_temp.use_billing_actor('manager');
select extensions.ok(not public.can_read_protected_person(pg_temp.billing_id('dossier')), 'le partage révoqué ne revient pas');
select extensions.ok(not has_function_privilege('anon','public.get_management_report_commercial_capabilities(uuid)','EXECUTE')
  and not has_function_privilege('authenticated','public.get_enabled_dossier_billing_features(uuid)','EXECUTE'),
  'seule la projection authentifiée est accessible, le détail reste interne');

select * from extensions.finish();
rollback;
