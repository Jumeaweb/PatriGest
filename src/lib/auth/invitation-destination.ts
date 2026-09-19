export function getDossierInvitationPath(token: string) {
  return `/invitation/${encodeURIComponent(token)}`;
}

export function getDossierInvitationLoginPath(token: string) {
  return `/connexion?next=${encodeURIComponent(getDossierInvitationPath(token))}`;
}
