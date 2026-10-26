import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  documentInventoryAnomalySchema,
  documentInventoryCategorySchema,
  getAdministrativeDocumentInventoryHref,
  parseAdministrativeDocumentInventoryQuery,
// @ts-expect-error Node's strip-types test runner requires the source extension.
} from "./administrative-document-inventory.ts";

const read = (path) => readFileSync(new URL(path, import.meta.url), "utf8");

test("valide uniquement les filtres et tailles explicitement autorisés", () => {
  const query = parseAdministrativeDocumentInventoryQuery({
    category: "backup",
    anomaly: "backup_catalog_object_missing",
    limit: "50",
  });
  assert.deepEqual(query, { cursor: null, category: "backup", anomaly: "backup_catalog_object_missing", limit: 50 });
  assert.throws(() => parseAdministrativeDocumentInventoryQuery({ category: "storage.objects" }));
  assert.throws(() => parseAdministrativeDocumentInventoryQuery({ anomaly: "arbitrary_path" }));
  assert.throws(() => parseAdministrativeDocumentInventoryQuery({ limit: "101" }));
  assert.ok(documentInventoryCategorySchema.options.length === 7);
  assert.ok(documentInventoryAnomalySchema.options.includes("historical_noncanonical_path"));
  assert.ok(documentInventoryAnomalySchema.options.includes("unresolved_catalog_path"));
});

test("construit une pagination déterministe sans accepter de chemin libre", () => {
  const query = parseAdministrativeDocumentInventoryQuery({ category: "repair", limit: "25" });
  const href = getAdministrativeDocumentInventoryHref(query, "repair:expired_repair_authorization:11111111-1111-4111-8111-111111111111");
  assert.match(href, /^\/administration\/inventaire-documentaire\?/);
  assert.match(href, /category=repair/);
  assert.match(href, /cursor=repair%3Aexpired_repair_authorization/);
  assert.doesNotMatch(href, /bucket|path/);
});

test("l’interface distingue catalogue, octets physiques et absence de réparation", () => {
  const page = read("../../app/administration/inventaire-documentaire/page.tsx");
  const component = read("./components/administrative-document-inventory.tsx");
  const service = read("./services/administrative-document-inventory-service.ts");
  assert.match(page, /Aucune réparation n’est effectuée/);
  assert.match(page, /ne prouve pas la disponibilité des octets/);
  assert.match(component, /Fait SQL démontré/);
  assert.match(component, /Anomalie possible/);
  assert.match(component, /État historique potentiellement légitime/);
  assert.match(component, /Non vérifiés/);
  assert.doesNotMatch(component, /objectPath|storage_path|recoveryObjectPath/);
  assert.match(service, /requirePlatformAdministrator\(\)/);
  assert.doesNotMatch(service, /createAdminClient|service_role/);
});

test("le tableau de bord expose l’inventaire sans activer la réparation", () => {
  const dashboard = read("./components/administration-dashboard.tsx");
  assert.match(dashboard, /href="\/administration\/inventaire-documentaire"/);
  assert.match(dashboard, /Inventaire documentaire/);
  assert.match(dashboard, /isAdminDocumentRepairEnabled\(\) && <Link href="\/administration\/reparations-documentaires"/);
});

test("le serveur écarte les actions dépendant de la garde avant autorisation", () => {
  const service = read("./services/administrative-document-repair-service.ts");
  const panel = read("./components/administrative-document-repair-panel.tsx");
  const engine = read("./administrative-document-repair.ts");
  assert.match(service, /getAdministrativeRepairGuardBlockReason/);
  assert.ok(service.indexOf("actionCapabilities(target, capabilities.storageGuardEnabled)") < service.indexOf("issue_administrative_document_repair_authorization"));
  assert.match(panel, /Actions indisponibles avant activation de la garde Storage/);
  assert.match(engine, /if \(item\.progressState === "authorized"\)[\s\S]*?getAdministrativeRepairGuardBlockReason[\s\S]*?this\.rpc\.start/);
  assert.match(engine, /"STORAGE_GUARD_REQUIRED"/);
});
