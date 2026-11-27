begin;
create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

create function pg_temp.fixture(name text) returns uuid language sql immutable as $$
  select md5('pat-stripe-02e:' || name)::uuid
$$;
-- Keep the same JWT role for all requests; only the synthetic subject changes.
create function pg_temp.act_as(name text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', pg_temp.fixture(name)::text, true);
end
$$;
create function pg_temp.create_dossier(owner_name text, dossier_name text) returns void language sql as $$
  insert into public.protected_persons(id, owner_id, first_name, last_name)
  values (pg_temp.fixture(dossier_name), pg_temp.fixture(owner_name), 'Fixture', 'Quota')
$$;
create function pg_temp.quota() returns text language sql as $$
  select concat_ws('/', active_dossier_count, active_dossier_limit, remaining_dossier_count, block_reason)
  from public.get_owned_dossier_quota_gate()
$$;

insert into auth.users(id, email, raw_user_meta_data)
select pg_temp.fixture(name), name || '@stripe02e.example.test',
  case when name='shared' then '{"patrigest_registration_intent":"collaborator"}'::jsonb else '{}'::jsonb end
from unnest(array['trial','expired','monthly','annual','grace','suspended','assignment','override','terminated','shared','legacy','dev']) name;
update public.application_user_authorizations
set status='active', status_changed_at=now(),
  account_mode=case when user_id=pg_temp.fixture('shared') then 'collaborator' else 'autonomous' end,
  registration_intent=case when user_id=pg_temp.fixture('shared') then 'collaborator' else 'autonomous' end,
  autonomous_registration_status=case when user_id=pg_temp.fixture('shared') then autonomous_registration_status else 'active' end
where user_id in (select pg_temp.fixture(name) from unnest(
  array['trial','expired','monthly','annual','grace','suspended','assignment','override','terminated','shared','legacy','dev']) name);

insert into public.account_trials(user_id, terms_version, terms_accepted_at, started_at, ends_at, deletion_eligible_at)
select pg_temp.fixture(name), 'fixture', elapsed, elapsed, elapsed + interval '30 days', elapsed + interval '60 days'
from (values ('trial', now()-interval '1 day'), ('expired', now()-interval '31 days')) periods(name, elapsed);
insert into public.account_trial_legacy_access(user_id, reason, recorded_at)
values (pg_temp.fixture('legacy'), 'active_before_trial_cutover',now()-interval '1 day');
insert into public.account_subscriptions(owner_id, started_at, status)
values (pg_temp.fixture('dev'), now()-interval '1 day','development')
on conflict do nothing;

update public.protected_person_archive_runtime_config set lifecycle_enabled=true where singleton;
insert into public.protected_persons(id,owner_id,first_name,last_name,status,archived_at) values
  (pg_temp.fixture('expired_archived'),pg_temp.fixture('expired'),'Fixture','Archivée','archived',now()),
  (pg_temp.fixture('suspended_archived'),pg_temp.fixture('suspended'),'Fixture','Archivée','archived',now()),
  (pg_temp.fixture('shared1'),pg_temp.fixture('legacy'),'Fixture','Partage','active',null),
  (pg_temp.fixture('shared2'),pg_temp.fixture('dev'),'Fixture','Partage','active',null);
insert into public.protected_person_access(protected_person_id,user_id,role) values
  (pg_temp.fixture('shared1'),pg_temp.fixture('shared'),'manager'),
  (pg_temp.fixture('shared2'),pg_temp.fixture('shared'),'read_only');

insert into public.account_administrative_plan_assignments(id,owner_id,plan_key,billing_period,dossier_capacity_key,
  reason,created_at,valid_from,valid_until)
select pg_temp.fixture('base:' || name),pg_temp.fixture(name),plan,'annual',capacity,'fixture',
  now()-interval '5 days',null,null
from (values ('assignment','comfort','five'),('override','comfort','included'),('terminated','comfort','included')) t(name,plan,capacity);
insert into public.account_administrative_entitlement_overrides(
  id,owner_id,base_source,base_reference_id,dossier_capacity_key,reason,created_at,status,revoked_at)
values
  (pg_temp.fixture('override1'),pg_temp.fixture('override'),'administrative',pg_temp.fixture('base:override'),'five',
    'fixture',now()-interval '3 days','active',null),
  (pg_temp.fixture('override2'),pg_temp.fixture('terminated'),'administrative',pg_temp.fixture('base:terminated'),'five',
    'fixture',now()-interval '3 days','revoked',now()-interval '1 day');

insert into public.billing_stripe_contexts(id,stripe_account_id,mode)
values (pg_temp.fixture('context'),'acct_QuotaFixtures','live');
insert into public.billing_price_mappings(id,context_id,stripe_price_id,plan_key,billing_cycle,currency,amount_cents,sale_enabled)
values (pg_temp.fixture('price_monthly'),pg_temp.fixture('context'),'price_QuotaMonth','essential','monthly','eur',300,true),
       (pg_temp.fixture('price_annual'),pg_temp.fixture('context'),'price_QuotaYear','essential','annual','eur',3000,true);

create function pg_temp.payment(name text, cycle text, deadline timestamptz, renewal boolean default false)
returns text language plpgsql as $$
declare period_start timestamptz := case when renewal then now()-interval '16 days' else now()-interval '20 days' end;
declare payment_at timestamptz := case when renewal then now()-interval '1 minute' else period_start end;
declare invoice_id uuid := pg_temp.fixture('invoice:' || name || renewal::text);
begin
  if not renewal then
    insert into public.billing_customers(id,context_id,owner_id,stripe_customer_id)
    values (pg_temp.fixture('customer:' || name),pg_temp.fixture('context'),pg_temp.fixture(name),'cus_Quota' || name);
    insert into public.billing_subscriptions(id,context_id,billing_customer_id,price_mapping_id,
      stripe_subscription_id,stripe_status,started_at)
    values (pg_temp.fixture('sub:' || name),pg_temp.fixture('context'),pg_temp.fixture('customer:' || name),
      pg_temp.fixture('price_' || cycle),'sub_Quota' || name,'active',period_start);
  end if;
  insert into public.billing_invoice_periods(id,context_id,billing_subscription_id,price_mapping_id,stripe_invoice_id,
    billing_reason,stripe_status,billed_from,billed_until,currency,amount_due_cents,stripe_reported_paid_at,
    payment_evidence,payment_verified_at,stripe_payment_intent_id)
  values (invoice_id,pg_temp.fixture('context'),pg_temp.fixture('sub:' || name),pg_temp.fixture('price_' || cycle),
    'in_Quota' || name || renewal::text,case when renewal then 'renewal' else 'initial' end,'paid',
    period_start,deadline,'eur',case when cycle='monthly' then 300 else 3000 end,payment_at,
    'stripe_verified',payment_at,'pi_Quota' || name || renewal::text);
  return public.billing_accept_verified_invoice_at(invoice_id,payment_at);
end
$$;

select extensions.is(pg_temp.payment('monthly','monthly',now()+interval '10 days'),'applied','premier abonnement mensuel');
select extensions.is(pg_temp.payment('annual','annual',now()+interval '12 months'),'applied','premier abonnement annuel');
select extensions.is(pg_temp.payment('grace','monthly',now()-interval '1 day'),'applied','abonnement actuellement en grâce');
select extensions.is(pg_temp.payment('suspended','monthly',now()-interval '16 days'),'applied','ancien abonnement entré en suspension');

select extensions.ok(
  has_function_privilege('authenticated','public.get_owned_dossier_quota_gate()','execute')
  and not has_function_privilege('anon','public.get_owned_dossier_quota_gate()','execute')
  and not has_function_privilege('service_role','public.get_owned_dossier_quota_gate()','execute')
  and not has_function_privilege('authenticated','billing_internal.check_essential_dossier_capacity(uuid)','execute')
  and not has_function_privilege('service_role','billing_internal.check_essential_dossier_capacity(uuid)','execute'),
  'projection self-only et contrôle Checkout strictement privé');

set local role authenticated;
select pg_temp.act_as('trial');
select extensions.is(pg_temp.quota(),null::text,'réglage désactivé : aucune projection commerciale');
select extensions.lives_ok($$select pg_temp.create_dossier('trial','trial1')$$,'création par le parcours historique');
reset role;
update public.billing_runtime_config set commercial_access_enabled=true where singleton;

set local role authenticated;
select pg_temp.act_as('trial');
select extensions.is(pg_temp.quota(),'1/2/1','essai : une place restante');
select extensions.lives_ok($$select pg_temp.create_dossier('trial','trial2')$$,'deuxième dossier pendant l’essai');
select extensions.throws_ok($$select pg_temp.create_dossier('trial','trial3')$$,'P4D01',null,'troisième dossier refusé');
select extensions.throws_ok($$select pg_temp.create_dossier('legacy','substitute')$$,'42501',null,'substitution de propriétaire refusée');
select extensions.is(public.archive_protected_person(pg_temp.fixture('trial2'),1,'fixture'),2::bigint,'archivage volontaire');
select extensions.is(pg_temp.quota(),'1/2/1','l’archive libère une place');
select extensions.is(public.restore_protected_person(pg_temp.fixture('trial2'),2,'fixture'),3::bigint,'restauration avec une place');
select extensions.is(public.archive_protected_person(pg_temp.fixture('trial2'),3,'fixture'),4::bigint,'nouvel archivage');
select extensions.lives_ok($$select pg_temp.create_dossier('trial','trial3')$$,'création à la place libérée');
select extensions.throws_ok($$select public.restore_protected_person(pg_temp.fixture('trial2'),4,'fixture')$$,'P4D01',null,'restauration au quota refusée');
select extensions.throws_ok($$select public.restore_protected_person(pg_temp.fixture('expired_archived'),1,'fixture')$$,'P4A01',null,'restauration du dossier d’un tiers refusée');
select extensions.throws_ok($$update public.protected_persons set status='active',archived_at=null where id=pg_temp.fixture('trial2')$$,'42501',null,'mise à jour directe du statut refusée');

select pg_temp.act_as('expired');
select extensions.is(pg_temp.quota(),'0/account_suspended','aucun droit autonome à J30');
select extensions.throws_ok($$select pg_temp.create_dossier('expired','expired1')$$,'P4D04',null,'création après J30 refusée');
select extensions.throws_ok($$select public.restore_protected_person(pg_temp.fixture('expired_archived'),1,'fixture')$$,'P4D04',null,'restauration après J30 refusée');
select pg_temp.act_as('monthly');
select extensions.is(pg_temp.quota(),'0/2/2','Essentiel mensuel : deux places');
select pg_temp.act_as('annual');
select extensions.is(pg_temp.quota(),'0/2/2','Essentiel annuel : même plafond');
select extensions.lives_ok($$insert into public.protected_persons(owner_id,first_name,last_name)
 select pg_temp.fixture('annual'),'Fixture','Quota' from generate_series(1,2)$$,'deux insertions atomiques autorisées');
select extensions.throws_ok($$select pg_temp.create_dossier('annual','annual3')$$,'P4D01',null,'contrat annuel au quota');
select pg_temp.act_as('grace');
select extensions.is(pg_temp.quota(),'0/2/2','la grâce conserve les places');
select extensions.lives_ok($$select pg_temp.create_dossier('grace','grace1')$$,'création en période de grâce');
select pg_temp.act_as('suspended');
select extensions.is(pg_temp.quota(),'0/account_suspended','suspension après J14');
select extensions.throws_ok($$select pg_temp.create_dossier('suspended','susp1')$$,'P4D04',null,'création commerciale suspendue');
select extensions.throws_ok($$select public.restore_protected_person(pg_temp.fixture('suspended_archived'),1,'fixture')$$,'P4D04',null,'restauration commerciale suspendue');

select pg_temp.act_as('assignment');
select extensions.is(pg_temp.quota(),'0/5/5','attribution administrative à cinq');
select extensions.lives_ok($$insert into public.protected_persons(owner_id,first_name,last_name)
 select pg_temp.fixture('assignment'),'Fixture','Quota' from generate_series(1,3)$$,'trois dossiers valides dans une attribution à cinq');
select pg_temp.act_as('override');
select extensions.is(pg_temp.quota(),'0/5/5','dérogation administrative active à cinq');
select pg_temp.act_as('terminated');
select extensions.is(pg_temp.quota(),'0/2/2','fin de dérogation : retour au plafond de l’attribution');

select pg_temp.act_as('shared');
select extensions.is(pg_temp.quota(),null::text,'collaborateur sans quota autonome');
select extensions.is((select count(*) from public.protected_persons),2::bigint,'accès aux dossiers de deux propriétaires');
select extensions.throws_ok($$select pg_temp.create_dossier('shared','shared3')$$,null,null,'création autonome du collaborateur refusée');
select pg_temp.act_as('legacy');
select extensions.is(pg_temp.quota(),'1/2/1','exemption historique conservée');
select pg_temp.act_as('dev');
select extensions.is(pg_temp.quota(),'1/2/1','droits development conservés');
reset role;

set local role service_role;
select pg_temp.act_as('trial');
select extensions.throws_ok($$select pg_temp.create_dossier('trial','privileged')$$,'42501',null,'service_role refusé même avec un sujet JWT propriétaire');
select extensions.throws_ok($$select public.restore_protected_person(pg_temp.fixture('trial2'),4,'fixture')$$,'42501',null,'service_role ne peut appeler la restauration');
reset role;
select set_config('request.jwt.claim.sub','',true);
select extensions.ok((select active_dossier_count=2 and compatible from billing_internal.check_essential_dossier_capacity(pg_temp.fixture('trial'))),'essai compatible avant conversion');
select extensions.ok((select active_dossier_count=3 and exceeded_by=1 and not compatible from billing_internal.check_essential_dossier_capacity(pg_temp.fixture('assignment'))),'conversion administrative incompatible détectée');
select extensions.is((select count(*) from public.protected_persons where owner_id=pg_temp.fixture('assignment') and status='active'),3::bigint,'aucun dossier excédentaire modifié');
select extensions.is(pg_temp.payment('suspended','monthly',now()+interval '12 days',true),'applied','renouvellement vérifié rétablit les droits');
set local role authenticated;
select pg_temp.act_as('suspended');
select extensions.is(public.restore_protected_person(pg_temp.fixture('suspended_archived'),1,'fixture'),2::bigint,'restauration après reprise des droits');
reset role;

select * from extensions.finish();
rollback;
