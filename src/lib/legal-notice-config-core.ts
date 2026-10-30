export const LEGAL_NOTICE_REQUIRED_VARIABLES = [
  "LEGAL_PUBLISHER_NAME",
  "LEGAL_PUBLISHER_ADDRESS",
  "LEGAL_PUBLISHER_SIREN",
  "LEGAL_PUBLICATION_DIRECTOR",
  "LEGAL_HOST_NAME",
  "LEGAL_HOST_ADDRESS",
  "LEGAL_HOST_PHONE",
] as const;

export const LEGAL_NOTICE_PUBLICATION_READY_VARIABLE =
  "LEGAL_NOTICE_PUBLICATION_READY" as const;

export type LegalNoticeRequiredVariable =
  (typeof LEGAL_NOTICE_REQUIRED_VARIABLES)[number];

type Environment = Partial<Record<LegalNoticeRequiredVariable | typeof LEGAL_NOTICE_PUBLICATION_READY_VARIABLE, string | undefined>>;

export type LegalNoticeConfiguration = {
  values: Record<LegalNoticeRequiredVariable, string | null>;
  missingVariables: LegalNoticeRequiredVariable[];
  publicationApproved: boolean;
  readyForPublication: boolean;
};

function normalized(value: string | undefined) {
  const result = value?.trim();
  return result ? result : null;
}

export function buildLegalNoticeConfiguration(
  environment: Environment,
): LegalNoticeConfiguration {
  const values = Object.fromEntries(
    LEGAL_NOTICE_REQUIRED_VARIABLES.map((name) => [name, normalized(environment[name])]),
  ) as Record<LegalNoticeRequiredVariable, string | null>;
  const missingVariables = LEGAL_NOTICE_REQUIRED_VARIABLES.filter(
    (name) => values[name] === null,
  );
  const publicationApproved =
    environment[LEGAL_NOTICE_PUBLICATION_READY_VARIABLE] === "true";

  return {
    values,
    missingVariables,
    publicationApproved,
    readyForPublication: missingVariables.length === 0 && publicationApproved,
  };
}

export function assertLegalNoticePublicationReady(
  configuration: LegalNoticeConfiguration,
  deploymentEnvironment: string | undefined,
) {
  if (deploymentEnvironment !== "production" || configuration.readyForPublication) {
    return;
  }

  const missing = configuration.missingVariables.length
    ? ` Variables manquantes : ${configuration.missingVariables.join(", ")}.`
    : "";
  const approval = configuration.publicationApproved
    ? ""
    : ` ${LEGAL_NOTICE_PUBLICATION_READY_VARIABLE} doit valoir exactement true.`;

  throw new Error(`Mentions légales non prêtes pour la publication.${missing}${approval}`);
}
