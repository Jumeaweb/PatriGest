import assert from "node:assert/strict";
import test from "node:test";

import {
  describeAdministrationOverrideDraft,
  getAdministrativeCapacityLimit,
  selectAdministrationPlan,
  validateAdministrationOverrideDraft,
  validateAdministrationPlanDraft,
} from "./administration-user-subscription-editor.ts";

test("Essentiel impose deux dossiers et Confort conserve une capacité explicite", () => {
  const essential = selectAdministrationPlan({ planKey: "premium", billingPeriod: "annual", capacityKey: "ten" }, "essential");
  assert.deepEqual(essential, { planKey: "essential", billingPeriod: "annual", capacityKey: "included" });
  const comfort = selectAdministrationPlan(essential, "comfort");
  assert.equal(comfort.planKey, "comfort");
  assert.equal(getAdministrativeCapacityLimit(comfort.capacityKey), 2);
});

test("la validation d'une attribution refuse une réduction sous le nombre actif", () => {
  assert.equal(validateAdministrationPlanDraft({ planKey: "comfort", billingPeriod: "monthly", capacityKey: "five" }, 5), null);
  assert.match(validateAdministrationPlanDraft({ planKey: "comfort", billingPeriod: "monthly", capacityKey: "five" }, 6) ?? "", /6 dossiers actifs/);
  assert.match(validateAdministrationPlanDraft({ planKey: "essential", billingPeriod: "annual", capacityKey: "ten" }, 0) ?? "", /Essentiel/);
});

test("une dérogation doit changer au moins un droit et respecte le quota actif", () => {
  assert.match(validateAdministrationOverrideDraft({ featurePlanKey: null, capacityKey: null }, 0) ?? "", /au moins une dérogation/);
  assert.match(validateAdministrationOverrideDraft({ featurePlanKey: "premium", capacityKey: "five" }, 6) ?? "", /6 dossiers actifs/);
  assert.equal(validateAdministrationOverrideDraft({ featurePlanKey: "premium", capacityKey: null }, 8), null);
});

test("la description d'une dérogation conserve la capacité de base lorsqu'elle n'est pas remplacée", () => {
  assert.deepEqual(describeAdministrationOverrideDraft({ featurePlanKey: "comfort", capacityKey: null }, 2), {
    formula: "Confort",
    capacity: "2 dossiers actifs",
  });
});
