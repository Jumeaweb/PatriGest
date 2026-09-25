import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import test from "node:test";

const fromApp = (name) => new URL(name, import.meta.url);

test("les métadonnées et icônes navigateur utilisent l’identité PatriGest", () => {
  const layout = readFileSync(fromApp("./layout.tsx"), "utf8");
  const favicon = readFileSync(fromApp("./favicon.ico"));
  const sourceIcon = readFileSync(fromApp("../../public/logos/patrigest-icon-32.png"));
  const embeddedSize = favicon.readUInt32LE(14);
  const embeddedOffset = favicon.readUInt32LE(18);
  assert.match(layout, /applicationName: APP_NAME/);
  assert.match(layout, /appleWebApp:[\s\S]*title: APP_NAME/);
  assert.equal(existsSync(fromApp("./favicon.ico")), true);
  assert.equal(existsSync(fromApp("./apple-icon.png")), true);
  assert.equal(existsSync(fromApp("./icon.svg")), false);
  assert.equal(favicon.readUInt16LE(2), 1);
  assert.equal(favicon.readUInt16LE(4), 1);
  assert.equal(favicon[6], 32);
  assert.equal(favicon[7], 32);
  assert.deepEqual(favicon.subarray(embeddedOffset, embeddedOffset + embeddedSize), sourceIcon);
});
