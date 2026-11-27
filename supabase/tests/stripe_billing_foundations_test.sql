begin;
create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

select extensions.is(
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and c.relname like 'billing\_%' escape '\'
     and c.relrowsecurity), 13::bigint, 'les 13 tables techniques ont la RLS');
select extensions.ok(not exists (
  select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
  cross join (values ('anon'), ('authenticated'), ('service_role')) as roles(role_name)
  where n.nspname = 'public' and c.relname like 'billing\_%' escape '\' and c.relkind = 'r'
    and has_table_privilege(roles.role_name, c.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
), 'aucun rôle runtime ne dispose de privilège direct sur les tables billing');
select extensions.ok(not exists (
  select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
  cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) acl
  where n.nspname = 'public' and c.relname like 'billing\_%' escape '\' and c.relkind = 'r' and acl.grantee = 0
), 'PUBLIC ne reçoit aucun privilège direct');
select extensions.ok(not exists (
  select 1 from pg_policies where schemaname = 'public' and tablename like 'billing\_%' escape '\'
), 'aucune politique ne permet un accès direct aux données techniques');
select extensions.ok(not has_function_privilege('authenticated', 'public.validate_billing_customer_owner()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.validate_billing_checkout_context()', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.validate_billing_subscription_projection()', 'EXECUTE'),
  'les validations ne sont pas des RPC ouvertes');
select extensions.ok(not has_sequence_privilege('authenticated', 'public.billing_lifecycle_events_id_seq', 'USAGE'),
  'la séquence d’audit est privée');
select extensions.is((select count(*) from public.billing_runtime_config where singleton
  and not stripe_sales_enabled and not commercial_access_enabled
  and not shared_access_enforcement_enabled and not notifications_enabled and not purges_enabled),
  1::bigint, 'les cinq réglages sont désactivés');
select extensions.is((select count(*) from public.billing_stripe_contexts), 0::bigint, 'aucun contexte Stripe préconfiguré');
select extensions.is((select count(*) from public.billing_price_mappings), 0::bigint, 'aucun Price fictif ni activé');
select extensions.is((select monthly_price_cents from public.subscription_plans where plan_key='essential'), 300, 'Essentiel mensuel conservé');
select extensions.is((select annual_price_cents from public.subscription_plans where plan_key='essential'), 3000, 'Essentiel annuel conservé');
select extensions.ok(not exists (
  select 1 from pg_attribute where attrelid = 'public.billing_stripe_events'::regclass and attnum > 0
    and not attisdropped and atttypid in ('json'::regtype, 'jsonb'::regtype)
), 'la boîte de réception ne contient pas de colonne pour le webhook brut');

insert into auth.users(id, email, raw_user_meta_data)
values
  ('995b0000-0000-4000-8000-000000000001', 'billing-owner@example.test', '{}'),
  ('995b0000-0000-4000-8000-000000000002', 'billing-other@example.test', '{}'),
  ('995b0000-0000-4000-8000-000000000003', 'billing-collab@example.test', '{"patrigest_registration_intent":"collaborator"}');
update public.application_user_authorizations
set status='active', status_changed_at=now(), account_mode='autonomous',
    registration_intent='autonomous', autonomous_registration_status='active'
where user_id in ('995b0000-0000-4000-8000-000000000001', '995b0000-0000-4000-8000-000000000002');
update public.application_user_authorizations set account_mode='collaborator', registration_intent='collaborator'
where user_id='995b0000-0000-4000-8000-000000000003';

insert into public.account_trial_legacy_access(user_id, reason)
values ('995b0000-0000-4000-8000-000000000001', 'active_before_trial_cutover');
insert into public.account_administrative_plan_assignments(owner_id,plan_key,billing_period,dossier_capacity_key,reason,created_by)
values ('995b0000-0000-4000-8000-000000000002','comfort','monthly','five','Attribution de test','995b0000-0000-4000-8000-000000000001');
select extensions.is((select access_source from public.resolve_effective_account_entitlements('995b0000-0000-4000-8000-000000000001')),
  'legacy', 'le droit historique reste reconnu');
select extensions.is((select access_source from public.resolve_effective_account_entitlements('995b0000-0000-4000-8000-000000000002')),
  'administrative', 'le droit offert reste reconnu');
select extensions.ok((select valid_from is null and valid_until is null from public.account_administrative_plan_assignments
  where owner_id='995b0000-0000-4000-8000-000000000002'), 'l’attribution sans dates reste indéterminée');

insert into public.billing_stripe_contexts(id,stripe_account_id,mode) values
 ('995b0000-0000-4000-8100-000000000001','acct_Fixture','test'),
 ('995b0000-0000-4000-8100-000000000002','acct_Fixture','live');
insert into public.billing_customers(id,context_id,owner_id,stripe_customer_id) values
 ('995b0000-0000-4000-8200-000000000001','995b0000-0000-4000-8100-000000000001','995b0000-0000-4000-8000-000000000001','cus_Fixture'),
 ('995b0000-0000-4000-8200-000000000002','995b0000-0000-4000-8100-000000000002','995b0000-0000-4000-8000-000000000001','cus_Fixture'),
 ('995b0000-0000-4000-8200-000000000003','995b0000-0000-4000-8100-000000000001','995b0000-0000-4000-8000-000000000002','cus_Other');
select extensions.is((select count(*) from public.billing_customers), 3::bigint,
  'un même identifiant de client est isolé entre test et live');
select extensions.throws_ok($$insert into public.billing_customers(context_id,owner_id,stripe_customer_id)
values ('995b0000-0000-4000-8100-000000000001','995b0000-0000-4000-8000-000000000001','cus_Second')$$, '23505', null,
  'un seul client par propriétaire et contexte');
select extensions.throws_ok($$update public.billing_customers set stripe_customer_id='cus_Fixture'
where id='995b0000-0000-4000-8200-000000000003'$$, '23505', null, 'un identifiant Stripe ne peut être partagé');
select extensions.throws_ok($$insert into public.billing_customers(context_id,owner_id,stripe_customer_id)
values ('995b0000-0000-4000-8100-000000000001','995b0000-0000-4000-8000-000000000003','cus_Collab')$$, '23514', null,
  'un collaborateur ne peut pas recevoir de client Stripe');

insert into public.billing_price_mappings(id,context_id,stripe_price_id,plan_key,billing_cycle,currency,amount_cents,sale_enabled) values
 ('995b0000-0000-4000-8300-000000000001','995b0000-0000-4000-8100-000000000001','price_Month','essential','monthly','eur',300,true),
 ('995b0000-0000-4000-8300-000000000002','995b0000-0000-4000-8100-000000000002','price_Month','essential','monthly','eur',300,true),
 ('995b0000-0000-4000-8300-000000000003','995b0000-0000-4000-8100-000000000001','price_Year','essential','annual','eur',3000,true),
 ('995b0000-0000-4000-8300-000000000004','995b0000-0000-4000-8100-000000000001','price_Old','essential','monthly','eur',300,false);
select extensions.throws_ok($$update public.billing_price_mappings set stripe_price_id='price_Month'
where id='995b0000-0000-4000-8300-000000000004'$$, '23505', null, 'identifiant Price unique dans le contexte');
select extensions.throws_ok($$update public.billing_price_mappings set sale_enabled=true
where id='995b0000-0000-4000-8300-000000000004'$$, '23505', null, 'un seul prix ouvert par combinaison');
select extensions.throws_ok($$update public.billing_price_mappings set plan_key='comfort'
where id='995b0000-0000-4000-8300-000000000001'$$, '23514', null, 'Confort ne peut pas être mis en vente');
select extensions.throws_ok($$update public.billing_price_mappings set amount_cents=301
where id='995b0000-0000-4000-8300-000000000001'$$, '23514', null, 'un prix Essentiel ouvert respecte le montant validé');

create function pg_temp.add_attempt(p_id uuid,p_context uuid,p_customer uuid,p_price uuid,p_session text default null)
returns void language sql as $$
 insert into public.billing_checkout_attempts(id,context_id,billing_customer_id,price_mapping_id,intent,
   consent_version,consented_at,expires_at,stripe_checkout_session_id)
 values (p_id,p_context,p_customer,p_price,'subscribe_now','terms-v1',now(),now()+interval '1 hour',p_session)
$$;
select pg_temp.add_attempt('995b0000-0000-4000-8400-000000000001','995b0000-0000-4000-8100-000000000001',
 '995b0000-0000-4000-8200-000000000001','995b0000-0000-4000-8300-000000000001','cs_test_Fixture');
select extensions.throws_ok($$select pg_temp.add_attempt(gen_random_uuid(),'995b0000-0000-4000-8100-000000000001',
 '995b0000-0000-4000-8200-000000000001','995b0000-0000-4000-8300-000000000003')$$, '23505', null,
  'un autre prix ne permet pas une deuxième tentative ouverte');
select extensions.throws_ok($$select pg_temp.add_attempt(gen_random_uuid(),'995b0000-0000-4000-8100-000000000002',
 '995b0000-0000-4000-8200-000000000001','995b0000-0000-4000-8300-000000000002')$$, '23503', null,
  'un client de test ne peut être lié à une tentative live');
select extensions.throws_ok($$select pg_temp.add_attempt(gen_random_uuid(),'995b0000-0000-4000-8100-000000000002',
 '995b0000-0000-4000-8200-000000000002','995b0000-0000-4000-8300-000000000001')$$, '23503', null,
  'un Price de test ne peut être lié à une tentative live');
select extensions.throws_ok($$select pg_temp.add_attempt(gen_random_uuid(),'995b0000-0000-4000-8100-000000000002',
 '995b0000-0000-4000-8200-000000000002','995b0000-0000-4000-8300-000000000002','cs_test_WrongMode')$$, '23514', null,
  'le préfixe de session Checkout doit correspondre au contexte');
update public.billing_checkout_attempts set state='canceled', finished_at=now() where id='995b0000-0000-4000-8400-000000000001';
select extensions.lives_ok($$select pg_temp.add_attempt('995b0000-0000-4000-8400-000000000002','995b0000-0000-4000-8100-000000000001',
 '995b0000-0000-4000-8200-000000000001','995b0000-0000-4000-8300-000000000003')$$, 'une tentative terminée n’empêche pas la suivante');
select extensions.throws_ok($$update public.billing_checkout_attempts set intent='setup_trial'
where id='995b0000-0000-4000-8400-000000000002'$$, '23514', null, 'la programmation exige une date');

insert into public.billing_subscriptions(id,context_id,billing_customer_id,price_mapping_id,checkout_attempt_id,stripe_subscription_id,stripe_status,started_at)
values
 ('995b0000-0000-4000-8500-000000000001','995b0000-0000-4000-8100-000000000001','995b0000-0000-4000-8200-000000000001','995b0000-0000-4000-8300-000000000003','995b0000-0000-4000-8400-000000000002','sub_Fixture','incomplete',now()),
 ('995b0000-0000-4000-8500-000000000002','995b0000-0000-4000-8100-000000000001','995b0000-0000-4000-8200-000000000001','995b0000-0000-4000-8300-000000000001',null,'sub_Historic','canceled',now()-interval '2 years'),
 ('995b0000-0000-4000-8500-000000000003','995b0000-0000-4000-8100-000000000002','995b0000-0000-4000-8200-000000000002','995b0000-0000-4000-8300-000000000002',null,'sub_Fixture','incomplete',now());
select extensions.throws_ok($$update public.billing_subscriptions set stripe_subscription_id='sub_Fixture'
where id='995b0000-0000-4000-8500-000000000002'$$, '23505', null, 'une souscription Stripe est unique dans son contexte');
select extensions.throws_ok($$update public.billing_subscriptions set billing_customer_id='995b0000-0000-4000-8200-000000000003'
where id='995b0000-0000-4000-8500-000000000001'$$, '23503', null, 'la tentative appartient au même client que l’abonnement');

insert into public.billing_invoice_periods(id,context_id,billing_subscription_id,price_mapping_id,stripe_invoice_id,
 billing_reason,stripe_status,billed_from,billed_until,currency,amount_due_cents,stripe_reported_paid_at,payment_evidence)
values
 ('995b0000-0000-4000-8600-000000000001','995b0000-0000-4000-8100-000000000001','995b0000-0000-4000-8500-000000000001','995b0000-0000-4000-8300-000000000003','in_Fixture','initial','paid',now(),now()+interval '1 year','eur',3000,now(),'out_of_band_unverified'),
 ('995b0000-0000-4000-8600-000000000002','995b0000-0000-4000-8100-000000000002','995b0000-0000-4000-8500-000000000003','995b0000-0000-4000-8300-000000000002','in_Fixture','initial','open',now(),now()+interval '1 month','eur',300,null,'unverified');
select extensions.throws_ok($$insert into public.billing_invoice_periods(context_id,billing_subscription_id,price_mapping_id,stripe_invoice_id,billing_reason,stripe_status,billed_from,billed_until,currency,amount_due_cents)
select context_id,billing_subscription_id,price_mapping_id,stripe_invoice_id,billing_reason,stripe_status,billed_from,billed_until,currency,amount_due_cents
from public.billing_invoice_periods where id='995b0000-0000-4000-8600-000000000001'$$, '23505', null, 'une facture Stripe est unique dans son contexte');
select extensions.throws_ok($$update public.billing_invoice_periods set price_mapping_id='995b0000-0000-4000-8300-000000000002'
where id='995b0000-0000-4000-8600-000000000001'$$, '23503', null, 'la facture ne peut référencer un prix de l’autre mode');
select extensions.throws_ok($$update public.billing_invoice_periods set payment_verified_at=now()
where id='995b0000-0000-4000-8600-000000000001'$$, '23514', null, 'un règlement hors Stripe ne peut être promu implicitement');
select extensions.throws_ok($$update public.billing_subscriptions set account_subscription_id=gen_random_uuid()
where id='995b0000-0000-4000-8500-000000000001'$$, '23514', null, 'un abonnement non vérifié ne peut être rattaché à une projection');
select extensions.is((select count(*) from public.account_subscriptions
where owner_id in ('995b0000-0000-4000-8000-000000000001','995b0000-0000-4000-8000-000000000002') and status<>'development'),
  0::bigint, 'les faits techniques ne créent aucun abonnement commercial');
select extensions.is((select access_source from public.resolve_effective_account_entitlements('995b0000-0000-4000-8000-000000000002')),
  'administrative', 'les droits offerts restent inchangés après les écritures techniques');

insert into public.billing_stripe_events(context_id,stripe_event_id,event_type,stripe_created_at) values
 ('995b0000-0000-4000-8100-000000000001','evt_Fixture','charge.dispute.created',now()),
 ('995b0000-0000-4000-8100-000000000002','evt_Fixture','refund.updated',now());
select extensions.throws_ok($$insert into public.billing_stripe_events(context_id,stripe_event_id,event_type,stripe_created_at)
values ('995b0000-0000-4000-8100-000000000001','evt_Fixture','invoice.paid',now())$$, '23505', null,
  'un webhook dupliqué est refusé, indépendamment du type');
select extensions.throws_ok($$update public.billing_stripe_events set state='processing'
where context_id='995b0000-0000-4000-8100-000000000001'$$, '23514', null, 'le traitement exige un bail complet');

insert into public.billing_account_lifecycle(owner_id,first_paid_at,paid_through,trial_converted_at)
values ('995b0000-0000-4000-8000-000000000001',now(),now()+interval '1 month',now());
select extensions.throws_ok($$update public.billing_account_lifecycle set trial_converted_at=null
where owner_id='995b0000-0000-4000-8000-000000000001'$$, '23514', null, 'le marqueur de conversion ne peut être effacé par mise à jour');
insert into public.billing_lifecycle_episodes(id,owner_id,kind,episode_key,starts_at,access_ended_at,retention_until)
values ('995b0000-0000-4000-8700-000000000001','995b0000-0000-4000-8000-000000000001','retention',gen_random_uuid(),now(),now(),now()+interval '12 months');
select extensions.throws_ok($$insert into public.billing_lifecycle_episodes(owner_id,kind,episode_key,starts_at,access_ended_at,retention_until)
values ('995b0000-0000-4000-8000-000000000001','retention',gen_random_uuid(),now()+interval '1 day',now()+interval '1 day',now()+interval '13 months')$$,
 '23505', null, 'une seule conservation ouverte par propriétaire');
set local time zone 'Europe/Paris';
select extensions.throws_ok($$insert into public.billing_lifecycle_episodes(owner_id,kind,episode_key,context_id,billing_customer_id,
 billing_subscription_id,starts_at,renewal_due_at,grace_ends_at)
select '995b0000-0000-4000-8000-000000000001','renewal_arrears',gen_random_uuid(),'995b0000-0000-4000-8100-000000000001',
 '995b0000-0000-4000-8200-000000000001','995b0000-0000-4000-8500-000000000001',due,due,due+interval '14 days'
from (values ('2026-03-22 09:00+01'::timestamptz)) v(due)$$, '23514', null, '14 jours civils peuvent différer de 336 h');
select extensions.lives_ok($$insert into public.billing_lifecycle_episodes(owner_id,kind,episode_key,context_id,billing_customer_id,
 billing_subscription_id,starts_at,renewal_due_at,grace_ends_at)
select '995b0000-0000-4000-8000-000000000001','renewal_arrears',gen_random_uuid(),'995b0000-0000-4000-8100-000000000001',
 '995b0000-0000-4000-8200-000000000001','995b0000-0000-4000-8500-000000000001',due,due,due+interval '336 hours'
from (values ('2026-03-22 09:00+01'::timestamptz)) v(due)$$, '336 h sont valides au changement d’heure');

insert into public.billing_notification_jobs(episode_id,notification_code,due_at)
values ('995b0000-0000-4000-8700-000000000001','retention_warning_7d',now());
select extensions.throws_ok($$insert into public.billing_notification_jobs(episode_id,notification_code,due_at)
values ('995b0000-0000-4000-8700-000000000001','retention_warning_7d',now()+interval '1 day')$$, '23505', null,
  'un rappel logique ne peut être programmé deux fois');
insert into public.billing_purge_jobs(owner_id,episode_id,kind,request_key,eligible_at)
values ('995b0000-0000-4000-8000-000000000001','995b0000-0000-4000-8700-000000000001','retention',gen_random_uuid(),now()+interval '12 months');
select extensions.throws_ok($$update public.billing_purge_jobs set state='completed',completed_at=now()$$,
 '23514', null, 'une purge ne peut être annoncée terminée avant une étape irréversible');
set constraints all immediate;
select extensions.throws_ok($$update public.billing_purge_jobs set kind='trial'$$,
 '23503', null, 'une purge doit correspondre au type de son épisode');
select extensions.ok((select confdeltype = 'n' from pg_constraint where conrelid='public.billing_customers'::regclass
  and confrelid='auth.users'::regclass and contype='f'), 'la référence Auth financière est détachée, sans cascade');
select extensions.ok(not exists (
  select 1 from pg_constraint where conrelid in ('public.billing_invoice_periods'::regclass,'public.billing_subscriptions'::regclass)
    and contype='f' and confdeltype='c'
), 'les faits de facturation ne sont pas supprimés par cascade');

set local role anon;
select extensions.throws_ok($$select * from public.billing_customers$$, '42501', null, 'lecture anonyme refusée');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','995b0000-0000-4000-8000-000000000001',true);
select extensions.throws_ok($$select * from public.billing_customers$$, '42501', null, 'même le propriétaire ne lit pas la table technique');
select extensions.throws_ok($$insert into public.billing_stripe_contexts(stripe_account_id,mode) values('acct_Forbidden','test')$$,
 '42501', null, 'écriture directe authentifiée refusée');
select extensions.lives_ok($$select status from public.account_subscriptions
where owner_id='995b0000-0000-4000-8000-000000000001'$$, 'la lecture existante des abonnements reste disponible');
reset role;

select * from extensions.finish();
rollback;
