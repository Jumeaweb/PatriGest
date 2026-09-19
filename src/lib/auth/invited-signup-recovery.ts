export function shouldRecoverInvitedAuthAccount(input: {
  isDossierInvitation: boolean;
  signUpErrorCode: string | undefined;
  identityCount: number | null;
}) {
  if (!input.isDossierInvitation) return false;

  return input.signUpErrorCode === "user_already_exists"
    || (!input.signUpErrorCode && input.identityCount === 0);
}
