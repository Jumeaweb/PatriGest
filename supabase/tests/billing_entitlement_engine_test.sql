begin;
set local time zone 'UTC';
create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

create function pg_temp.id(name text) returns uuid language sql immutable as $$
  select md5('pat-stripe-02c:' || name)::uuid
$$;

insert into auth.users(id, email, raw_user_meta_data)
select pg_temp.id(name), name || '@stripe02c.example.test',
  case when name = 'collaborator' then '{"patrigest_registration_intent":"collaborator"}'::jsonb else '{}'::jsonb end
from unnest(array['trial','legacy','dev','admin','conversion','collaborator','forever','uncertain','irreversible']) name;

update public.application_user_authorizations
set status='active', status_changed_at=now(), account_mode='autonomous',
  registration_intent='autonomous', autonomous_registration_status='active'
where user_id in (select pg_temp.id(name) from unnest(array['trial','legacy','dev','admin','conversion','forever','uncertain','irreversible']) name);
update public.application_user_authorizations set status='active', status_changed_at=now(), account_mode='collaborator', registration_intent='collaborator'
where user_id=pg_temp.id('collaborator');

insert into public.account_trials(user_id, terms_version, terms_accepted_at, started_at, ends_at, deletion_eligible_at)
select pg_temp.id(name), 'fixture', '2027-01-01', '2027-01-01', '2027-01-31', '2027-03-02'
from unnest(array['trial','uncertain','irreversible']) name;
insert into public.account_trial_legacy_access(user_id, reason, recorded_at)
values (pg_temp.id('legacy'), 'active_before_trial_cutover', '2027-01-01');
insert into public.account_subscriptions(owner_id, started_at)
select pg_temp.id(name), '2027-01-01' from unnest(array['dev','trial']) name
where not exists (select 1 from public.account_subscriptions where owner_id=pg_temp.id(name));

insert into public.billing_stripe_contexts(id,stripe_account_id,mode)
values (pg_temp.id('context'),'acct_BillingEngine','live');
insert into public.billing_customers(id,context_id,owner_id,stripe_customer_id)
select pg_temp.id('customer:' || name), pg_temp.id('context'), pg_temp.id(name), 'cus_BillingEngine' || name
from unnest(array['trial','conversion','uncertain','irreversible']) name;
insert into public.billing_price_mappings(id,context_id,stripe_price_id,plan_key,billing_cycle,currency,amount_cents,sale_enabled)
values (pg_temp.id('monthly'),pg_temp.id('context'),'price_BillingMonth','essential','monthly','eur',300,true),
       (pg_temp.id('annual'),pg_temp.id('context'),'price_BillingYear','essential','annual','eur',3000,true);

create function pg_temp.contract(name text, owner_name text, cycle text, starts timestamptz, attempt text default null)
returns void language sql as $$
  insert into public.billing_subscriptions(id,context_id,billing_customer_id,price_mapping_id,checkout_attempt_id,
    stripe_subscription_id,stripe_status,started_at)
  values (pg_temp.id(name),pg_temp.id('context'),pg_temp.id('customer:' || owner_name),pg_temp.id(cycle),
    case when attempt is not null then pg_temp.id(attempt) end,'sub_' || name,'active',starts)
$$;

create function pg_temp.invoice(name text, contract text, starts timestamptz, ends timestamptz,
  paid timestamptz, reason text, evidence text default 'stripe_verified')
returns void language sql as $$
  insert into public.billing_invoice_periods(id,context_id,billing_subscription_id,price_mapping_id,stripe_invoice_id,
    billing_reason,stripe_status,billed_from,billed_until,currency,amount_due_cents,stripe_reported_paid_at,
    payment_evidence,payment_verified_at,stripe_payment_intent_id)
  select pg_temp.id(name), subscription.context_id,subscription.id,price.id,'in_' || name,reason,
    case when paid is null then 'open' else 'paid' end,starts,ends,'eur',price.amount_cents,paid,evidence,
    case when evidence='stripe_verified' then paid end,
    case when evidence='stripe_verified' then 'pi_' || name end
  from public.billing_subscriptions subscription
  join public.billing_price_mappings price on price.id=subscription.price_mapping_id
  where subscription.id=pg_temp.id(contract)
$$;

select extensions.ok((select not stripe_sales_enabled and not commercial_access_enabled
  and not shared_access_enforcement_enabled and not notifications_enabled and not purges_enabled
  from public.billing_runtime_config), 'les cinq réglages restent désactivés');
select extensions.is((select count(*) from public.billing_resolve_current_entitlements(pg_temp.id('trial'))),
  0::bigint, 'le point d’entrée courant est fermé par défaut');
select extensions.ok(public.has_application_business_access(pg_temp.id('trial'), '2027-03-02'),
  'le contrôle applicatif historique reste inchangé');
select extensions.is((select access_source from public.billing_resolve_entitlements_at(pg_temp.id('legacy'),'2027-01-15')),
  'legacy', 'exemption historique sans conversion');
select extensions.is((select access_source from public.billing_resolve_entitlements_at(pg_temp.id('dev'),'2027-01-15')),
  'development', 'ligne development existante conservée');
select extensions.ok((select access_source='shared_access' and active_dossier_limit is null
  and not purge_eligible and cardinality(features)=0
  from public.billing_resolve_entitlements_at(pg_temp.id('collaborator'),'2027-03-02')),
  'collaborateur sans droit autonome ni purge autonome');
select extensions.ok((select access_source='trial' and active_dossier_limit=2 and rights_end_at='2027-01-31'
  from public.billing_resolve_entitlements_at(pg_temp.id('trial'),'2027-01-30 23:59:59.999999+00')),
  'essai actif juste avant J30 avec deux dossiers');
select extensions.ok((select features @> array['core_management','bank_reconciliation','uploaded_document_upload',
  'uploaded_document_read','uploaded_document_download','management_report_prepare','management_report_screen_preview']
  and not features && array['data_export','csv_export','excel_export','dossier_export','global_zip_export',
    'application_pdf_generate','management_report_finalize','management_report_print']
  from public.billing_resolve_entitlements_at(pg_temp.id('trial'),'2027-01-15')), 'matrice distincte des droits d’essai');
select extensions.ok((select lifecycle_state='trial_suspended' and grace_ends_at is null and not purge_eligible
  from public.billing_resolve_entitlements_at(pg_temp.id('trial'),'2027-01-31')), 'suspension exactement à J30 sans grâce');
select extensions.ok((select lifecycle_state='trial_suspended' and not purge_eligible
  from public.billing_resolve_entitlements_at(pg_temp.id('trial'),'2027-03-01 23:59:59.999999+00')),
  'aucune purge juste avant J60');
select extensions.ok((select purge_eligible from public.billing_resolve_entitlements_at(pg_temp.id('trial'),'2027-03-02')),
  'éligibilité exactement à J60');
select extensions.ok((select access_source='none' and active_dossier_limit is null
  and rights_end_at is null and grace_ends_at is null and not purge_eligible
  from public.billing_resolve_entitlements_at(pg_temp.id('trial'),'2027-01-31 00:00:00.000001+00')),
  'juste après J30, aucun plafond actif ni prolongation implicite');
select extensions.ok((select access_source='none' and purge_eligible and retention_until='2027-03-02'
  from public.billing_resolve_entitlements_at(pg_temp.id('trial'),'2027-03-02 00:00:00.000001+00')),
  'juste après J60, l’éligibilité ne crée ni droit ni nouvelle échéance');

insert into public.billing_checkout_attempts(id,context_id,billing_customer_id,price_mapping_id,intent,state,consent_version,
 consented_at,scheduled_for,expires_at,stripe_schedule_id)
values (pg_temp.id('scheduled'),pg_temp.id('context'),pg_temp.id('customer:trial'),pg_temp.id('monthly'),
 'setup_trial','scheduled','fixture','2027-01-10','2027-01-31','2027-02-01','sub_sched_BillingEngine');
select extensions.is((select access_source from public.billing_resolve_entitlements_at(pg_temp.id('trial'),'2027-01-15')),
  'trial', 'programmation sans paiement : maintien de l’essai seul');
update public.billing_checkout_attempts set state='canceled', finished_at='2027-01-20' where id=pg_temp.id('scheduled');
select extensions.is((select access_source from public.billing_resolve_entitlements_at(pg_temp.id('trial'),'2027-01-21')),
  'trial', 'annulation de programmation sans effet sur l’essai');

select pg_temp.contract('first','trial','monthly','2027-01-31');
select pg_temp.invoice('firstinvoice','first','2027-01-31','2027-03-28 01:30+00',null,'initial','unverified');
select extensions.is(public.billing_accept_verified_invoice_at(pg_temp.id('firstinvoice'),'2027-01-31'),
  'payment_not_verified','premier paiement échoué ou absent');
select extensions.is((select access_source from public.billing_resolve_entitlements_at(pg_temp.id('trial'),'2027-02-01')),
  'none', 'un statut Stripe actif et une période facturée n’accordent aucun droit');
update public.billing_invoice_periods set stripe_status='paid',stripe_reported_paid_at='2027-02-01',
  payment_evidence='stripe_verified',payment_verified_at='2027-02-02',stripe_payment_intent_id='pi_BillingInitial'
where id=pg_temp.id('firstinvoice');
select extensions.is(public.billing_accept_verified_invoice_at(pg_temp.id('firstinvoice'),'2027-02-01'),
  'payment_not_verified','preuve non encore vérifiée à la date de référence');
select extensions.is(public.billing_accept_verified_invoice_at(pg_temp.id('firstinvoice'),'2027-02-02'), 'applied',
  'premier règlement vérifié après J30');
select extensions.is(public.billing_accept_verified_invoice_at(pg_temp.id('firstinvoice'),'2027-02-02'), 'already_applied',
  'rejouer la même preuve ne convertit pas deux fois');
select extensions.ok((select first_paid_at='2027-02-01' and trial_converted_at='2027-02-02' and revision=1
  from public.billing_account_lifecycle where owner_id=pg_temp.id('trial')), 'date du paiement distincte de sa prise en compte');
select extensions.ok((select commercial_state='paid' and effective_plan_key='essential' and active_dossier_limit=2
  and rights_end_at='2027-03-28 01:30+00' and 'application_pdf_generate'=any(features)
  from public.billing_resolve_entitlements_at(pg_temp.id('trial'),'2027-02-02')), 'activation Essentiel après paiement');
select extensions.ok((select commercial_state='grace' and grace_ends_at='2027-04-11 01:30+00'
  and 'csv_export'=any(features) from public.billing_resolve_entitlements_at(pg_temp.id('trial'),'2027-03-28 01:30+00')),
  'grâce à l’échéance exacte, droits intégraux et 336 heures au passage à l’heure d’été');
select extensions.lives_ok($$select public.billing_record_lifecycle_at(pg_temp.id('trial'),'2027-03-28 01:30+00')$$,
  'enregistrement de l’épisode d’impayé');
select extensions.lives_ok($$select public.billing_record_lifecycle_at(pg_temp.id('trial'),'2027-04-01')$$,
  'une relance n’allonge pas l’épisode');
select extensions.is((select count(*) from public.billing_lifecycle_episodes where owner_id=pg_temp.id('trial')
  and kind='renewal_arrears' and grace_ends_at='2027-04-11 01:30+00'),1::bigint,'épisode unique à échéance fixe');
update public.billing_subscriptions set stripe_status='canceled',stripe_ended_at='2027-04-02',end_reason='nonpayment'
where id=pg_temp.id('first');
select extensions.is((select commercial_state from public.billing_resolve_entitlements_at(pg_temp.id('trial'),'2027-04-11 01:29:59.999999+00')),
  'grace','résiliation anticipée pour impayé : droits maintenus jusqu’à J14');
select extensions.ok((select access_source='none' and lifecycle_state='retention' and retention_started_at='2027-04-11 01:30+00'
  and retention_until='2028-04-11 01:30+00' from public.billing_resolve_entitlements_at(pg_temp.id('trial'),'2027-04-11 01:30+00')),
  'J14 exact, conservation sans retour à un ancien droit ni dépendance à un ordonnanceur');
select pg_temp.invoice('oldrenewal','first','2027-03-28 01:30+00','2027-04-28 01:30+00','2027-04-12','renewal');
select extensions.is(public.billing_accept_verified_invoice_at(pg_temp.id('oldrenewal'),'2027-04-12'),
  'contract_ended','une facture tardive d’un contrat terminé ne réactive pas les droits');
select extensions.is((select retention_until from public.billing_resolve_entitlements_at(pg_temp.id('trial'),'2027-04-12')),
  '2028-04-11 01:30+00'::timestamptz,'la facture tardive ne déplace pas la conservation');

select pg_temp.contract('annualcontract','trial','annual','2027-04-13');
select pg_temp.invoice('annualfirst','annualcontract','2027-04-13','2028-04-13','2027-04-13','initial');
select extensions.is(public.billing_accept_verified_invoice_at(pg_temp.id('annualfirst'),'2027-04-13'), 'applied',
  'une nouvelle souscription annuelle payée rétablit les droits');
select pg_temp.invoice('annualrepeat','annualcontract','2028-04-13','2029-04-13','2028-04-14','renewal');
select extensions.is(public.billing_accept_verified_invoice_at(pg_temp.id('annualrepeat'),'2028-04-14'), 'applied',
  'renouvellement annuel pendant la grâce');
select extensions.ok((select access_source='commercial' and rights_end_at='2029-04-13' and retention_until is null
  from public.billing_resolve_entitlements_at(pg_temp.id('trial'),'2028-04-14')),'période annuelle payée après régularisation');
update public.billing_subscriptions set cancel_effective_at='2029-04-13' where id=pg_temp.id('annualcontract');
select extensions.ok((select commercial_state='paid' and grace_ends_at is null
  from public.billing_resolve_entitlements_at(pg_temp.id('trial'),'2029-04-12')),'résiliation volontaire, droits jusqu’à la fin payée');
select extensions.ok((select retention_started_at='2029-04-13' and retention_until='2030-04-13' and grace_ends_at is null
  from public.billing_resolve_entitlements_at(pg_temp.id('trial'),'2029-04-13')),'conservation à la fin payée, sans grâce volontaire');
select extensions.ok((select access_source='none' and grace_ends_at is null and active_dossier_limit is null
  from public.billing_resolve_entitlements_at(pg_temp.id('trial'),'2029-04-13 00:00:00.000001+00')),
  'après fin payée volontaire, aucun retour aux droits antérieurs');

select pg_temp.contract('monthlycontract','trial','monthly','2029-04-14');
select pg_temp.invoice('monthlyfirst','monthlycontract','2029-04-14','2029-05-14','2029-04-14','initial');
select extensions.is(public.billing_accept_verified_invoice_at(pg_temp.id('monthlyfirst'),'2029-04-14'),'applied','nouveau contrat mensuel');
select pg_temp.invoice('monthlyrepeat','monthlycontract','2029-05-14','2029-06-14','2029-05-30','renewal');
select extensions.is((select access_source from public.billing_resolve_entitlements_at(pg_temp.id('trial'),'2029-05-28')),
  'none','suspension à J14 avant vérification du renouvellement');
select extensions.is(public.billing_accept_verified_invoice_at(pg_temp.id('monthlyrepeat'),'2029-05-30'),'applied',
  'paiement après J14 si le contrat est toujours valide');
select extensions.is((select rights_end_at from public.billing_resolve_entitlements_at(pg_temp.id('trial'),'2029-05-30')),
  '2029-06-14'::timestamptz,'renouvellement mensuel après rétablissement');
select extensions.is(public.billing_accept_verified_invoice_at(pg_temp.id('oldrenewal'),'2029-05-30'),
  'period_expired','une facture obsolète ne remplace pas le contrat actuel');

select extensions.is(public.billing_retention_deadline('2028-02-29 15:45+00'),'2029-02-28 15:45+00'::timestamptz,
  '29 février ramené au dernier jour du mois, heure de référence conservée');
select extensions.is(public.billing_retention_deadline('2027-03-28 08:15+00'),'2028-03-28 08:15+00'::timestamptz,
  'conservation de l’heure civile après passage à l’heure d’été');
select extensions.is(public.billing_retention_deadline('2027-03-27 09:15+00'),'2028-03-27 08:15+00'::timestamptz,
  'conservation de l’heure civile malgré un décalage UTC différent');
select extensions.is(public.billing_retention_deadline('2027-03-26 01:30+00'),'2028-03-26 01:30+00'::timestamptz,
  'heure inexistante au printemps décalée vers l’avant suivant la convention PostgreSQL');
select extensions.is(public.billing_retention_deadline('2027-10-29 00:30+00'),'2028-10-29 01:30+00'::timestamptz,
  'heure ambiguë en automne interprétée avec le décalage standard');

select pg_temp.contract('fallcontract','uncertain','monthly','2027-09-25 08:00+00');
select pg_temp.invoice('fallinitial','fallcontract','2027-09-25 08:00+00','2027-10-25 08:00+00',
  '2027-09-25 08:00+00','initial');
select extensions.is(public.billing_accept_verified_invoice_at(pg_temp.id('fallinitial'),'2027-09-25 08:00+00'),
  'applied','premier paiement après J60 tant que la purge n’est pas irréversible');
set local time zone 'Europe/Paris';
select extensions.is((select grace_ends_at from public.billing_resolve_entitlements_at(pg_temp.id('uncertain'),'2027-10-25 08:00+00')),
  '2027-11-08 08:00+00'::timestamptz, '336 heures réelles lors du passage à l’heure d’hiver');
set local time zone 'UTC';

insert into public.account_administrative_plan_assignments(id,owner_id,plan_key,billing_period,dossier_capacity_key,
  reason,created_by,created_at,valid_from,valid_until)
values (pg_temp.id('temporary'),pg_temp.id('trial'),'comfort','annual','five','fixture',pg_temp.id('admin'),
  '2029-07-01','2029-08-01','2029-09-01'),
  (pg_temp.id('indefinite'),pg_temp.id('forever'),'essential','monthly','included','fixture',pg_temp.id('admin'),
  '2027-01-01',null,null),
  (pg_temp.id('offerconversion'),pg_temp.id('conversion'),'comfort','monthly','five','fixture',pg_temp.id('admin'),
  '2027-01-01',null,null),
  (pg_temp.id('adminreplacement'),pg_temp.id('legacy'),'essential','annual','included','fixture',pg_temp.id('admin'),
  '2027-02-01','2027-02-01','2027-04-01');
select extensions.ok((select access_source='administrative' and rights_end_at is null and 'application_pdf_generate'=any(features)
  from public.billing_resolve_entitlements_at(pg_temp.id('forever'),'2027-12-31')), 'attribution existante indéterminée, droit PDF normal');
select extensions.lives_ok($$select public.billing_record_lifecycle_at(pg_temp.id('trial'),'2029-07-01')$$,
  'matérialisation de la conservation après J14');
insert into public.billing_purge_jobs(owner_id,episode_id,kind,request_key,eligible_at)
select owner_id,id,kind,pg_temp.id('plannedpurge'),retention_until
from public.billing_lifecycle_episodes where owner_id=pg_temp.id('trial') and kind='retention' and closed_at is null;
select extensions.ok((select access_source='administrative' and active_dossier_limit=5 and retention_until is null
  from public.billing_resolve_entitlements_at(pg_temp.id('trial'),'2029-08-01')), 'offre valide pendant la conservation, droits rétablis');
select extensions.lives_ok($$select public.billing_record_lifecycle_at(pg_temp.id('trial'),'2029-08-01')$$,
  'synchronisation des transitions lors du rétablissement administratif');
select extensions.is((select state from public.billing_purge_jobs where request_key=pg_temp.id('plannedpurge')),
  'canceled','restauration administrative : procédure réversible annulée');
select extensions.ok((select retention_started_at='2029-09-01' and retention_until='2030-09-01'
  from public.billing_resolve_entitlements_at(pg_temp.id('trial'),'2029-09-01')), 'nouvelle période complète après échéance de l’offre');
select extensions.ok((select access_source='administrative' and active_dossier_limit=5
  from public.billing_resolve_entitlements_at(pg_temp.id('trial'),'2029-08-31 23:59:59.999999+00')),
  'l’attribution reste valide jusqu’à la limite exclue');
select extensions.ok((select access_source='none' and active_dossier_limit is null
  from public.billing_resolve_entitlements_at(pg_temp.id('trial'),'2029-09-01 00:00:00.000001+00')),
  'l’attribution cesse sans nouveau plafond après son échéance');
select extensions.ok((
  select bool_and(decision.purge_eligible=boundary.eligible and decision.retention_until='2030-09-01')
  from (values ('2030-08-31 23:59:59.999999+00'::timestamptz,false),
               ('2030-09-01 00:00:00+00',true), ('2030-09-01 00:00:00.000001+00',true)) boundary(at_time,eligible)
  cross join lateral public.billing_resolve_entitlements_at(pg_temp.id('trial'),boundary.at_time) decision
), 'conservation administrative : juste avant, à et après douze mois calendaires');
select extensions.lives_ok($$select public.billing_record_transition_replacement_at(pg_temp.id('adminreplacement'),'2027-02-01')$$,
  'remplacement explicite du droit transitoire');
select extensions.ok((select access_source='none' and retention_started_at='2027-04-01'
  from public.billing_resolve_entitlements_at(pg_temp.id('legacy'),'2027-04-01')), 'aucun retour au droit historique remplacé');

insert into public.account_administrative_entitlement_overrides(owner_id,base_source,base_reference_id,feature_plan_key,
  dossier_capacity_key,reason,created_by,created_at)
values (pg_temp.id('forever'),'administrative',pg_temp.id('indefinite'),'premium','ten','fixture',pg_temp.id('admin'),'2027-09-01');
select extensions.ok((select base_plan_key='essential' and effective_plan_key='premium' and active_dossier_limit=10
  from public.billing_resolve_entitlements_at(pg_temp.id('forever'),'2027-09-01')), 'application de la seule dérogation de la source active');
select extensions.is((select effective_plan_key from public.billing_resolve_entitlements_at(pg_temp.id('forever'),'2027-08-31')),
  'essential','une dérogation ne s’applique pas rétroactivement');

select pg_temp.contract('offer','conversion','monthly','2027-02-01');
select pg_temp.invoice('offerpaid','offer','2027-02-01','2027-03-01','2027-02-01','initial');
select extensions.is(public.billing_accept_verified_invoice_at(pg_temp.id('offerpaid'),'2027-02-01'),
  'administrative_consent_required','un paiement seul ne révoque pas une attribution');
select extensions.is((select access_source from public.billing_resolve_entitlements_at(pg_temp.id('conversion'),'2027-02-01')),
  'administrative','attribution intacte avant consentement explicite');
insert into public.billing_checkout_attempts(id,context_id,billing_customer_id,price_mapping_id,intent,state,consent_version,
 consented_at,expires_at,finished_at)
values (pg_temp.id('consent'),pg_temp.id('context'),pg_temp.id('customer:conversion'),pg_temp.id('monthly'),
 'subscribe_now','completed','administrative-to-essential-v1','2027-01-30','2027-02-03','2027-02-01');
update public.billing_subscriptions set checkout_attempt_id=pg_temp.id('consent') where id=pg_temp.id('offer');
insert into public.protected_persons(id, owner_id, first_name, last_name)
select pg_temp.id('dossier' || name), pg_temp.id('conversion'), 'Fixture', name
from unnest(array['one','two','three']) name;
select extensions.is(public.billing_accept_verified_invoice_at(pg_temp.id('offerpaid'),'2027-02-01'),
  'active_dossier_limit_exceeded','conversion refusée lorsque trois dossiers sont actifs');
select extensions.is((select count(*) from public.protected_persons where owner_id=pg_temp.id('conversion') and status='active'),
  3::bigint,'aucun archivage automatique');
select set_config('request.jwt.claim.sub',pg_temp.id('conversion')::text,true);
update public.protected_persons set status='archived',archived_at=now()
where id=pg_temp.id('dossierthree');
select set_config('request.jwt.claim.sub','',true);
select extensions.is(public.billing_accept_verified_invoice_at(pg_temp.id('offerpaid'),'2027-02-01'),
  'applied','conversion payée et consentie avec conservation de la preuve');
select extensions.ok((select superseded_assignment_id=pg_temp.id('offerconversion') and consent_attempt_id=pg_temp.id('consent')
  from billing_internal.accepted_invoice_periods where invoice_id=pg_temp.id('offerpaid')),'audit de la conversion de l’offre');
select extensions.is((select access_source from public.billing_resolve_entitlements_at(pg_temp.id('conversion'),'2027-04-01')),
  'none','ancienne attribution remplacée jamais réactivée');

select pg_temp.contract('uncertaincontract','uncertain','monthly','2027-02-15');
select pg_temp.invoice('uncertaininvoice','uncertaincontract','2027-02-15','2027-03-15','2027-02-16','initial','out_of_band_unverified');
select extensions.is(public.billing_accept_verified_invoice_at(pg_temp.id('uncertaininvoice'),'2027-03-02'),
  'payment_not_verified','paiement hors Stripe sans qualification automatique');
select extensions.ok((select payment_uncertain and not purge_eligible and access_source='none'
  from public.billing_resolve_entitlements_at(pg_temp.id('uncertain'),'2027-03-02')),
  'incertitude bloque l’éligibilité à la purge sans restaurer l’accès');

insert into public.billing_lifecycle_episodes(id,owner_id,kind,episode_key,starts_at)
values (pg_temp.id('irrevtrial'),pg_temp.id('irreversible'),'trial',pg_temp.id('irrevtrialkey'),'2027-01-01');
insert into public.billing_purge_jobs(owner_id,episode_id,kind,request_key,state,eligible_at,reserved_at,irreversible_at)
values (pg_temp.id('irreversible'),pg_temp.id('irrevtrial'),'trial',pg_temp.id('irrevpurge'),'irreversible',
  '2027-03-02','2027-03-02','2027-03-02');
select pg_temp.contract('irrevcontract','irreversible','monthly','2027-03-03');
select pg_temp.invoice('irrevinvoice','irrevcontract','2027-03-03','2027-04-03','2027-03-03','initial');
select extensions.is(public.billing_accept_verified_invoice_at(pg_temp.id('irrevinvoice'),'2027-03-03'),
  'purge_irreversible','conversion refusée après le seuil irréversible');

select extensions.ok(not exists (
  select 1 from pg_proc procedure join pg_namespace ns on ns.oid=procedure.pronamespace
  cross join (values ('anon'),('authenticated'),('service_role')) role_name(name)
  where ns.nspname='public' and (procedure.proname like 'billing_resolve_%'
    or procedure.proname in ('billing_accept_verified_invoice_at','billing_record_lifecycle_at','billing_record_transition_replacement_at'))
    and (procedure.prosecdef or has_function_privilege(role_name.name,procedure.oid,'EXECUTE'))
), 'aucune RPC privilégiée ni exécutable par un rôle runtime');
select extensions.ok(not has_schema_privilege('service_role','billing_internal','USAGE') and not exists (
  select 1 from pg_class relation join pg_namespace ns on ns.oid=relation.relnamespace
  where ns.nspname='billing_internal' and relation.relkind='r'
    and not relation.relrowsecurity
), 'preuves et remplacements isolés dans un schéma privé avec RLS');
select extensions.is((select count(*) from public.billing_purge_jobs),2::bigint,'aucune purge créée ou exécutée par le moteur');

select * from extensions.finish();
rollback;
