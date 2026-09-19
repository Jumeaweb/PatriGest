const internalPathBase = new URL("https://patrigest.invalid");

export function getSafeInternalPath(value: string | null | undefined) {
  if (!value || !value.startsWith("/") || value.startsWith("//")) return null;

  try {
    const destination = new URL(value, internalPathBase);
    if (destination.origin !== internalPathBase.origin) return null;
    return `${destination.pathname}${destination.search}${destination.hash}`;
  } catch {
    return null;
  }
}

const directlyAllowedCallbackPaths = new Set(["/parametres/compte"]);

export function getSafeAuthCallbackNextPath(value: string | null) {
  const safePath = getSafeInternalPath(value);
  if (!safePath) return null;

  try {
    const base = new URL("https://patrigest.invalid");
    const destination = new URL(safePath, base);
    if (directlyAllowedCallbackPaths.has(destination.pathname) && !destination.search && !destination.hash) {
      return destination.pathname;
    }
    if (destination.pathname === "/nouveau-mot-de-passe" && !destination.hash) {
      if (!destination.search) return destination.pathname;
      const nextPath = destination.searchParams.get("next");
      const safeNextPath = getSafeInternalPath(nextPath);
      if (destination.searchParams.size !== 1 || !safeNextPath) return null;
      return `/nouveau-mot-de-passe?next=${encodeURIComponent(safeNextPath)}`;
    }
    if (destination.pathname.startsWith("/invitation/") && !destination.hash) {
      return `${destination.pathname}${destination.search}`;
    }
  } catch {
    return null;
  }

  return null;
}
