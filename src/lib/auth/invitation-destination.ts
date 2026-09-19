export function getDossierInvitationPath(token: string) {
  return `/invitation/${encodeURIComponent(token)}`;
}

export function getDossierInvitationLoginPath(token: string) {
  return `/connexion?next=${encodeURIComponent(getDossierInvitationPath(token))}`;
}

export function getDossierInvitationTokenFromPath(path: string | null | undefined) {
  const prefix = "/invitation/";
  if (!path?.startsWith(prefix)) return null;
  const encodedToken = path.slice(prefix.length);
  if (!encodedToken || encodedToken.includes("/") || encodedToken.includes("?") || encodedToken.includes("#")) return null;
  try {
    const token = decodeURIComponent(encodedToken);
    return token.length >= 32 && token.length <= 512 ? token : null;
  } catch {
    return null;
  }
}
