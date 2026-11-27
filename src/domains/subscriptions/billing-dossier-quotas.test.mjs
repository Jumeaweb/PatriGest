import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { classifyDossierCapacityMutationError, getDossierQuotaBlockMessage } from "./dossier-capacity.ts";
import { mapProtectedPersonArchiveRpcError } from "../protected-persons/archive-lifecycle.ts";

test("la suspension est distincte du quota atteint pour créer ou restaurer", () => {
  assert.equal(classifyDossierCapacityMutationError({ code: "P4D04" })?.code, "account_suspended");
  assert.equal(mapProtectedPersonArchiveRpcError({ code: "P4D04" }).code, "account_suspended");
  assert.match(getDossierQuotaBlockMessage({ block_reason: "account_suspended" }), /suspendus/);
  assert.match(getDossierQuotaBlockMessage({ block_reason: "quota_reached" }), /maximal/);
  assert.equal(getDossierQuotaBlockMessage({ block_reason: null }), null);
  assert.equal(getDossierQuotaBlockMessage(null), null);
});

test("le contrôle couvre le formulaire direct et la restauration sans bloquer l’archivage", () => {
  const read = (file) => readFileSync(new URL(file, import.meta.url), "utf8");
  assert.match(read("../../app/dossiers/nouveau/page.tsx"), /if \(quota\?\.block_reason\) redirect\("\/dossiers"\)/);
  const archive = read("../protected-persons/components/protected-person-archive-action.tsx");
  assert.match(archive, /archived \? restoreBlockedMessage : null/);
  assert.match(archive, /disabled=\{Boolean\(blockMessage\)\}/);
});
