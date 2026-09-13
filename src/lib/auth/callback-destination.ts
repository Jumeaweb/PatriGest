const directlyAllowedCallbackPaths = new Set([
  "/nouveau-mot-de-passe",
  "/parametres/compte",
]);

export function getSafeAuthCallbackNextPath(value: string | null) {
  if (!value || !value.startsWith("/") || value.startsWith("//")) return null;

  try {
    const base = new URL("https://patrigest.invalid");
    const destination = new URL(value, base);
    if (destination.origin !== base.origin) return null;
    if (directlyAllowedCallbackPaths.has(destination.pathname) && !destination.search && !destination.hash) {
      return destination.pathname;
    }
    if (destination.pathname.startsWith("/invitation/") && !destination.hash) {
      return `${destination.pathname}${destination.search}`;
    }
  } catch {
    return null;
  }

  return null;
}
