import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  getReleaseHistoryPage,
  getReleaseHistoryPageHref,
  getReleaseHistoryPaginationTargets,
  parseReleaseHistoryPage,
  RELEASE_HISTORY_PAGE_SIZE,
} from "./release-history-page.ts";

const source = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const pageSource = source("../../app/historique-versions/page.tsx");
const paginationSource = source("./release-history-pagination.tsx");
const versions = (count) => Array.from({ length: count }, (_, index) => ({ version: `${count - index}.0.0` }));

test("utilise exactement dix versions par page", () => {
  assert.equal(RELEASE_HISTORY_PAGE_SIZE, 10);
  assert.deepEqual(getReleaseHistoryPage(versions(0), 1), { items: [], page: 1, pageSize: 10, totalCount: 0, totalPages: 0 });
  assert.equal(getReleaseHistoryPage(versions(9), 1).items.length, 9);
  assert.equal(getReleaseHistoryPage(versions(10), 1).items.length, 10);
  assert.equal(getReleaseHistoryPage(versions(11), 1).items.length, 10);
  assert.equal(getReleaseHistoryPage(versions(11), 2).items.length, 1);
  assert.equal(getReleaseHistoryPage(versions(25), 2).items.length, 10);
});

test("conserve l’ordre antéchronologique fourni par la source", () => {
  const releases = versions(21);
  assert.deepEqual(getReleaseHistoryPage(releases, 2).items.map((release) => release.version), releases.slice(10, 20).map((release) => release.version));
});

test("normalise les pages absentes, invalides, négatives ou nulles", () => {
  assert.equal(parseReleaseHistoryPage(undefined), 1);
  assert.equal(parseReleaseHistoryPage("abc"), 1);
  assert.equal(parseReleaseHistoryPage("-2"), 1);
  assert.equal(parseReleaseHistoryPage("0"), 1);
  assert.equal(parseReleaseHistoryPage(["3", "4"]), 3);
});

test("ramène une page trop élevée à la dernière page valide", () => {
  const result = getReleaseHistoryPage(versions(21), 99);
  assert.equal(result.page, 3);
  assert.equal(result.items.length, 1);
  assert.equal(result.items[0].version, "1.0.0");
});

test("construit les cinq contrôles et leurs liens avec le paramètre page", () => {
  assert.equal(getReleaseHistoryPageHref(1), "/historique-versions?page=1");
  assert.equal(getReleaseHistoryPageHref(2), "/historique-versions?page=2");
  assert.deepEqual(getReleaseHistoryPaginationTargets(1, 3), {
    first: undefined,
    previous: undefined,
    next: "/historique-versions?page=2",
    last: "/historique-versions?page=3",
  });
  assert.deepEqual(getReleaseHistoryPaginationTargets(3, 3), {
    first: "/historique-versions?page=1",
    previous: "/historique-versions?page=2",
    next: undefined,
    last: undefined,
  });
  assert.match(paginationSource, /ChevronsLeft[\s\S]*?label="Première page"/);
  assert.match(paginationSource, /Page précédente/);
  assert.match(paginationSource, /Page suivante/);
  assert.match(paginationSource, /label="Dernière page"[\s\S]*?ChevronsRight/);
  assert.match(paginationSource, /Page \{page\} sur \{totalPages\}/);
});

test("affiche la pagination en haut et en bas sans recherche, filtre ni onglet", () => {
  assert.equal((pageSource.match(/<ReleaseHistoryPagination\b/g) ?? []).length, 2);
  assert.match(pageSource, /releases\.map/);
  assert.doesNotMatch(pageSource, /type=["']search|role=["']tablist|placeholder=.*recherch|Filtrer/i);
});
