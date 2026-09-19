export const INVITATION_RECOVERY_COOKIE = "patrigest_invitation_recovery";
export const INVITATION_RECOVERY_COOKIE_PATH = "/auth/callback";
export const INVITATION_RECOVERY_COOKIE_MAX_AGE = 60 * 60;

type RecoverableInvitation = { id: string };

export function getInvitationRecoveryDestination(
  invitations: RecoverableInvitation[],
  preferredInvitationId: string | null | undefined,
) {
  if (!invitations.length) return null;
  const preferredInvitation = preferredInvitationId
    ? invitations.find((invitation) => invitation.id === preferredInvitationId)
    : null;
  return preferredInvitation
    ? `/invitations?invitation=${encodeURIComponent(preferredInvitation.id)}`
    : "/invitations";
}

export function selectRecoverableInvitations<T extends RecoverableInvitation>(
  invitations: T[],
  preferredInvitationId: string | null | undefined,
) {
  if (!preferredInvitationId) return invitations;
  const preferredInvitation = invitations.find((invitation) => invitation.id === preferredInvitationId);
  return preferredInvitation ? [preferredInvitation] : invitations;
}
