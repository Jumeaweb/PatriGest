import assert from "node:assert/strict";
import test from "node:test";
import {
  assertLegalNoticePublicationReady,
  buildLegalNoticeConfiguration,
  LEGAL_NOTICE_REQUIRED_VARIABLES,
} from "./legal-notice-config-core.ts";

const completeEnvironment = Object.fromEntries(
  LEGAL_NOTICE_REQUIRED_VARIABLES.map((name, index) => [name, `configured-${index + 1}`]),
);

test("une configuration complète exige une validation explicite", () => {
  const pending = buildLegalNoticeConfiguration(completeEnvironment);
  assert.equal(pending.missingVariables.length, 0);
  assert.equal(pending.publicationApproved, false);
  assert.equal(pending.readyForPublication, false);

  const ready = buildLegalNoticeConfiguration({
    ...completeEnvironment,
    LEGAL_NOTICE_PUBLICATION_READY: "true",
  });
  assert.equal(ready.readyForPublication, true);
});

test("les valeurs vides sont signalées sans valeur de remplacement", () => {
  const configuration = buildLegalNoticeConfiguration({
    ...completeEnvironment,
    LEGAL_PUBLISHER_ADDRESS: "   ",
    LEGAL_NOTICE_PUBLICATION_READY: "true",
  });
  assert.deepEqual(configuration.missingVariables, ["LEGAL_PUBLISHER_ADDRESS"]);
  assert.equal(configuration.values.LEGAL_PUBLISHER_ADDRESS, null);
  assert.equal(configuration.readyForPublication, false);
});

test("la production refuse une configuration incomplète ou non approuvée", () => {
  assert.throws(
    () => assertLegalNoticePublicationReady(buildLegalNoticeConfiguration({}), "production"),
    /Mentions légales non prêtes pour la publication/,
  );
  assert.throws(
    () => assertLegalNoticePublicationReady(buildLegalNoticeConfiguration(completeEnvironment), "production"),
    /LEGAL_NOTICE_PUBLICATION_READY doit valoir exactement true/,
  );
  assert.doesNotThrow(() => assertLegalNoticePublicationReady(buildLegalNoticeConfiguration({}), "preview"));
  assert.doesNotThrow(() => assertLegalNoticePublicationReady(buildLegalNoticeConfiguration({
    ...completeEnvironment,
    LEGAL_NOTICE_PUBLICATION_READY: "true",
  }), "production"));
});
