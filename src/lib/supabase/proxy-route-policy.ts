const PRIVATE_ROUTE_PREFIXES = [
  "/tableau-de-bord",
  "/dossiers",
  "/administration",
  "/parametres",
  "/mon-compte",
  "/invitations",
  "/api",
] as const;

const PUBLIC_RELEASE_HISTORY_PATH = "/historique-versions";

export function isProtectedApplicationRoute(pathname: string) {
  return PRIVATE_ROUTE_PREFIXES.some((path) => pathname.startsWith(path));
}

export function requiresApplicationAccess(pathname: string, authenticated: boolean) {
  return isProtectedApplicationRoute(pathname)
    || (authenticated && pathname === PUBLIC_RELEASE_HISTORY_PATH);
}

