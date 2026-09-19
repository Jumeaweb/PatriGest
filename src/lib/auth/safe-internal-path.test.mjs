import assert from "node:assert/strict";
import test from "node:test";

import { getSafeInternalPath } from "./callback-destination.ts";

test("conserve les chemins internes et leurs paramètres", () => {
  assert.equal(getSafeInternalPath("/invitation/jeton?source=email"), "/invitation/jeton?source=email");
  assert.equal(getSafeInternalPath("/tableau-de-bord"), "/tableau-de-bord");
});

test("refuse les destinations externes et relatives au protocole", () => {
  for (const value of ["https://evil.example", "//evil.example", "///evil.example", "javascript:alert(1)"]) {
    assert.equal(getSafeInternalPath(value), null);
  }
});

test("refuse les variantes backslash interprétables hors origine", () => {
  for (const value of ["/\\evil.example", "/\\\\evil.example"]) {
    assert.equal(getSafeInternalPath(value), null);
  }
});
