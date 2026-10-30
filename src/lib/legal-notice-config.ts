import "server-only";

import {
  assertLegalNoticePublicationReady,
  buildLegalNoticeConfiguration,
} from "./legal-notice-config-core";

export function getLegalNoticeConfiguration() {
  const configuration = buildLegalNoticeConfiguration({
    LEGAL_PUBLISHER_NAME: process.env.LEGAL_PUBLISHER_NAME,
    LEGAL_PUBLISHER_ADDRESS: process.env.LEGAL_PUBLISHER_ADDRESS,
    LEGAL_PUBLISHER_SIREN: process.env.LEGAL_PUBLISHER_SIREN,
    LEGAL_PUBLICATION_DIRECTOR: process.env.LEGAL_PUBLICATION_DIRECTOR,
    LEGAL_HOST_NAME: process.env.LEGAL_HOST_NAME,
    LEGAL_HOST_ADDRESS: process.env.LEGAL_HOST_ADDRESS,
    LEGAL_HOST_PHONE: process.env.LEGAL_HOST_PHONE,
    LEGAL_NOTICE_PUBLICATION_READY: process.env.LEGAL_NOTICE_PUBLICATION_READY,
  });

  // Vercel définit VERCEL_ENV=production uniquement pour le déploiement de
  // production. Les builds locaux et les previews restent utilisables sans
  // enregistrer de coordonnées personnelles dans le dépôt.
  assertLegalNoticePublicationReady(configuration, process.env.VERCEL_ENV);

  return configuration;
}
