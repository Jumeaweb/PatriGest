export type AccountView = "profile" | "email" | "security" | "deletion";

export const ACCOUNT_VIEW_ITEMS = [
  { key: "profile", label: "Profil", value: null },
  { key: "email", label: "Adresse e-mail", value: "email" },
  { key: "security", label: "Sécurité", value: "securite" },
  { key: "deletion", label: "Suppression du compte", value: "suppression" },
] as const satisfies ReadonlyArray<{ key: AccountView; label: string; value: string | null }>;

export function getAccountView(value: string | string[] | undefined): AccountView {
  const normalized = Array.isArray(value) ? value[0] : value;
  return ACCOUNT_VIEW_ITEMS.find((item) => item.value === normalized)?.key ?? "profile";
}

export function getAccountViewHref(view: AccountView): string {
  const item = ACCOUNT_VIEW_ITEMS.find((candidate) => candidate.key === view);
  return item?.value ? `/parametres/compte?vue=${item.value}` : "/parametres/compte";
}
