import assert from "node:assert/strict";
import test from "node:test";

import {
  getPropertyPresentationAtPeriodEnd,
  isPropertyHeldAtPeriodEnd,
} from "./property-period.ts";

test("un bien vendu après l’exercice reste détenu à la clôture historique", () => {
  assert.equal(
    isPropertyHeldAtPeriodEnd(
      { entry_date: "2012-01-01", disposal_date: "2024-09-25" },
      "2023-12-31",
    ),
    true,
  );
});

test("un bien vendu pendant ou avant l’exercice n’est plus détenu à sa clôture", () => {
  assert.equal(
    isPropertyHeldAtPeriodEnd(
      { entry_date: "2012-01-01", disposal_date: "2023-09-25" },
      "2023-12-31",
    ),
    false,
  );
  assert.equal(
    isPropertyHeldAtPeriodEnd(
      { entry_date: "2012-01-01", disposal_date: "2022-09-25" },
      "2023-12-31",
    ),
    false,
  );
});

test("les dates limites d’entrée et de cession sont interprétées à la clôture", () => {
  assert.equal(
    isPropertyHeldAtPeriodEnd(
      { entry_date: "2023-12-31", disposal_date: null },
      "2023-12-31",
    ),
    true,
  );
  assert.equal(
    isPropertyHeldAtPeriodEnd(
      { entry_date: "2012-01-01", disposal_date: "2023-12-31" },
      "2023-12-31",
    ),
    false,
  );
  assert.equal(
    isPropertyHeldAtPeriodEnd(
      { entry_date: "2024-01-01", disposal_date: null },
      "2023-12-31",
    ),
    false,
  );
});

test("un bien sans date de cession reste détenu à la fin de la période", () => {
  assert.equal(
    isPropertyHeldAtPeriodEnd(
      { entry_date: null, disposal_date: null },
      "2023-12-31",
    ),
    true,
  );
});

test("la présentation historique masque une cession postérieure à l’exercice", () => {
  assert.deepEqual(
    getPropertyPresentationAtPeriodEnd(
      { entry_date: "2012-07-04", disposal_date: "2024-09-25" },
      "2023-12-31",
    ),
    { status: "Actif", disposalDate: null },
  );
});

test("la présentation affiche la cession à partir de l’exercice concerné", () => {
  assert.deepEqual(
    getPropertyPresentationAtPeriodEnd(
      { entry_date: "2012-07-04", disposal_date: "2024-09-25" },
      "2024-12-31",
    ),
    { status: "Cédé", disposalDate: "2024-09-25" },
  );
});
