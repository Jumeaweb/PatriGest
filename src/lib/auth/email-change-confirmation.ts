export const EMAIL_CHANGE_CONFIRMATION_PATH = "/auth/email-change/confirm";
export const EMAIL_CHANGE_RESULT_PATH = "/changement-adresse-email";
export const DEFAULT_EMAIL_CHANGE_NEXT_PATH = "/parametres/compte?vue=email";

export type EmailChangeConfirmationState = "first-confirmed" | "completed" | "error";

export function getSafeEmailChangeNextPath(value: string | null | undefined) {
  return value === DEFAULT_EMAIL_CHANGE_NEXT_PATH
    ? value
    : DEFAULT_EMAIL_CHANGE_NEXT_PATH;
}

export function parseEmailChangeConfirmationParams(searchParams: URLSearchParams) {
  const tokenHash = searchParams.get("token_hash");
  const type = searchParams.get("type");
  const validTokenHash = Boolean(
    tokenHash
    && tokenHash.length >= 32
    && tokenHash.length <= 512
    && !/\s/.test(tokenHash),
  );

  if (type !== "email_change" || !validTokenHash) return null;
  return {
    tokenHash: tokenHash as string,
    nextPath: getSafeEmailChangeNextPath(searchParams.get("next")),
  };
}

export function getEmailChangeConfirmationState(error: unknown, user: unknown): EmailChangeConfirmationState {
  if (error) return "error";
  return user ? "completed" : "first-confirmed";
}

export function getEmailChangeResultPath(
  state: EmailChangeConfirmationState,
  nextPath: string = DEFAULT_EMAIL_CHANGE_NEXT_PATH,
) {
  const params = new URLSearchParams({ state });
  if (state !== "error") params.set("next", getSafeEmailChangeNextPath(nextPath));
  return `${EMAIL_CHANGE_RESULT_PATH}?${params.toString()}`;
}
