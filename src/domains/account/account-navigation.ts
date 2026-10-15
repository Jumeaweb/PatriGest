export type AccountSection = "profile" | "subscription" | "invoices" | "cancellation" | "data";
export type AccountProfileView = "profile" | "email" | "security" | "deletion";
export type AccountView = AccountSection | Exclude<AccountProfileView, "profile">;

export const ACCOUNT_VIEW_ITEMS = [
  { key: "profile", label: "Profil", value: null },
  { key: "subscription", label: "Abonnement", value: "abonnement" },
  { key: "invoices", label: "Factures", value: "factures" },
  { key: "cancellation", label: "Résiliation", value: "resiliation" },
  { key: "data", label: "Mes données", value: "donnees" },
] as const satisfies ReadonlyArray<{ key: AccountSection; label: string; value: string | null }>;

export const ACCOUNT_PROFILE_VIEW_ITEMS = [
  { key: "profile", label: "Informations personnelles", value: null },
  { key: "email", label: "Adresse e-mail", value: "email" },
  { key: "security", label: "Sécurité", value: "securite" },
  { key: "deletion", label: "Suppression du compte", value: "suppression" },
] as const satisfies ReadonlyArray<{ key: AccountProfileView; label: string; value: string | null }>;

const ALL_ACCOUNT_VIEWS = [...ACCOUNT_VIEW_ITEMS, ...ACCOUNT_PROFILE_VIEW_ITEMS.slice(1)];

export function getAccountView(value: string | string[] | undefined): AccountView {
  const normalized = Array.isArray(value) ? value[0] : value;
  return ALL_ACCOUNT_VIEWS.find((item) => item.value === normalized)?.key ?? "profile";
}

export function getAccountViewHref(view: AccountView): string {
  const item = ALL_ACCOUNT_VIEWS.find((candidate) => candidate.key === view);
  return item?.value ? `/parametres/compte?vue=${item.value}` : "/parametres/compte";
}

export function getAccountSection(view: AccountView): AccountSection {
  return view === "email" || view === "security" || view === "deletion" ? "profile" : view;
}

export function isAccountProfileView(view: AccountView): view is AccountProfileView {
  return view === "profile" || view === "email" || view === "security" || view === "deletion";
}
