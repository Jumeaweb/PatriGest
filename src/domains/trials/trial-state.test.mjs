import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const source = (path) => readFileSync(new URL(path, import.meta.url), "utf8");

test("la migration fixe les bornes 30 + 30 jours et une activation explicite", () => {
  const sql = source("../../../supabase/migrations/20261106100000_create_account_trial_foundations.sql");
  assert.match(sql, /ends_at = started_at \+ interval '30 days'/);
  assert.match(sql, /deletion_eligible_at = started_at \+ interval '60 days'/);
  assert.match(sql, /p_at < context\.ends_at then 'active'/);
  assert.match(sql, /p_at < context\.deletion_eligible_at then 'suspended'/);
  assert.match(sql, /else 'deletion_due'/);
  assert.match(sql, /enforcement_enabled boolean not null default false/);
});

test("un essai ne peut être renouvelé et l'activation exige le consentement courant", () => {
  const sql = source("../../../supabase/migrations/20261106100000_create_account_trial_foundations.sql");
  assert.match(sql, /user_id uuid primary key references auth\.users/);
  assert.match(sql, /Une periode d''essai existe deja/);
  assert.match(sql, /conditions de l''essai doivent etre acceptees avant activation/);
  assert.match(sql, /grant execute on function public\.record_account_trial_terms_acceptance\(uuid, text\) to service_role/);
  assert.doesNotMatch(sql, /grant execute on function public\.record_account_trial_terms_acceptance\(uuid, text\) to authenticated/);
});

test("la purge est seulement préparée et les tables techniques restent fermées", () => {
  const sql = source("../../../supabase/migrations/20261106100000_create_account_trial_foundations.sql");
  assert.match(sql, /state text not null default 'prepared'/);
  assert.match(sql, /Compte non eligible a la purge/);
  assert.doesNotMatch(sql, /delete from auth\.users/i);
  assert.match(sql, /revoke all on table public\.account_trial_purge_requests from public, anon, authenticated, service_role/);
});

test("l'interface d'inscription impose une case non précochée", () => {
  const form = source("../../components/auth/auth-forms.tsx");
  const actions = source("../../app/(auth)/actions.ts");
  assert.match(form, /name="trialTermsAccepted"/);
  assert.doesNotMatch(form, /name="trialTermsAccepted"[^>]*defaultChecked/);
  assert.match(actions, /trialTermsAccepted: formData\.get\("trialTermsAccepted"\)/);
  assert.match(actions, /recordAccountTrialTermsAcceptance/);
});
