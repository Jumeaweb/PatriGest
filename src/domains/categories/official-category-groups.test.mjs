import assert from "node:assert/strict";
import test from "node:test";

import { groupOfficialCategories } from "./official-category-groups.ts";

const incomeGroups = [
  ["Les revenus", 1],
  ["Les allocations", 2],
  ["Les revenus mobiliers", 3],
  ["Les autres ressources", 4],
];

const expenseGroups = [
  ["Les dépenses de la vie courante", 1],
  ["Le logement", 2],
  ["Les impôts et taxes", 3],
  ["Les frais d'assurance", 4],
  ["Les frais de maintien à domicile", 5],
  ["Les achats importants", 6],
  ["Les travaux divers et réparations", 7],
  ["Les placements", 8],
  ["Les emprunts en cours", 9],
  ["Autres dépenses", 10],
];

function category(group, groupOrder, itemOrder, usage = "expense") {
  const prefix = usage === "income" ? "RES" : "DEP";
  return {
    id: `${prefix}-${groupOrder}-${itemOrder}`,
    name: `${group} ${itemOrder}`,
    usage,
    is_system: true,
    active: true,
    official_code: `${prefix}-${groupOrder}-${String(itemOrder).padStart(2, "0")}`,
    official_section: usage === "income" ? "Ressources" : "Dépenses",
    official_group: group,
    official_order: groupOrder * 100 + itemOrder,
  };
}

test("ordonne les quatre rubriques de recettes depuis le référentiel", () => {
  const categories = incomeGroups
    .flatMap(([group, order]) => [category(group, order, 2, "income"), category(group, order, 1, "income")])
    .reverse();
  const result = groupOfficialCategories(categories);
  assert.deepEqual(result.map((group) => group.label), incomeGroups.map(([label]) => label));
  assert.deepEqual(result.map((group) => group.categories.map((item) => item.official_order)), [
    [101, 102], [201, 202], [301, 302], [401, 402],
  ]);
});

test("ordonne les dix rubriques de dépenses depuis le référentiel", () => {
  const categories = expenseGroups.map(([group, order]) => category(group, order, 1)).reverse();
  assert.deepEqual(
    groupOfficialCategories(categories).map((group) => group.label),
    expenseGroups.map(([label]) => label),
  );
});

test("ignore les catégories personnelles et les entrées officielles incomplètes", () => {
  const official = category("Les revenus", 1, 1, "income");
  const personal = { ...official, id: "personal", is_system: false, official_code: null, official_group: null };
  const incomplete = { ...official, id: "incomplete", official_group: null };
  assert.deepEqual(groupOfficialCategories([personal, incomplete, official]), [{
    label: "Les revenus",
    categories: [official],
  }]);
});
