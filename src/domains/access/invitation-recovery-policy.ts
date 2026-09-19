export type InvitationRecoveryAuthorizationStatus = "pending" | "active" | "rejected" | null;

export function canRecoverDossierInvitations(input: {
  emailConfirmed: boolean;
  authorizationStatus: InvitationRecoveryAuthorizationStatus;
  platformAdministrator: boolean;
}) {
  return input.emailConfirmed
    && !input.platformAdministrator
    && (input.authorizationStatus === "pending" || input.authorizationStatus === "active");
}
