import type { ProtectedPerson } from "@/types/database";

type AddressFields = Pick<ProtectedPerson,
  | "address_line1" | "address_line2" | "postal_code" | "city" | "country"
  | "residence_address_line1" | "residence_address_line2" | "residence_postal_code" | "residence_city" | "residence_country"
>;

const present = (value: string | null | undefined) => Boolean(value?.trim());

export type DossierPatrimonyInformationState = "unreported" | "confirmed_absent" | "complete" | "incomplete";

export type DossierPropertyState = {
  informationState: DossierPatrimonyInformationState;
  label: string;
  currentKnownValue: number | null;
  missingActiveValues: number;
  activeCount: number;
  disposedCount: number;
};

export type DossierDebtState = {
  informationState: DossierPatrimonyInformationState;
  label: string;
  knownBalance: number | null;
  missingBalances: number;
  activeCount: number;
  settledCount: number;
};

export function getDossierAddressStates(person: AddressFields) {
  const domicileKnown = [person.address_line1, person.address_line2, person.postal_code, person.city].some(present);
  const residenceKnown = [person.residence_address_line1, person.residence_address_line2, person.residence_postal_code, person.residence_city].some(present);
  const domicile = domicileKnown
    ? [person.address_line1, person.address_line2, [person.postal_code, person.city].filter(present).join(" "), person.country].filter(present).join(", ")
    : "Non renseigné";
  const residence = residenceKnown
    ? [person.residence_address_line1, person.residence_address_line2, [person.residence_postal_code, person.residence_city].filter(present).join(" "), person.residence_country].filter(present).join(", ")
    : domicileKnown ? "Identique au domicile" : "Non renseigné";
  return { domicile, residence };
}

export function getDossierPropertyState(
  properties: ReadonlyArray<{ status: "active" | "disposed"; estimated_value: number | null; archived_at?: string | null }>,
  absenceConfirmed = false,
): DossierPropertyState {
  const currentProperties = properties.filter((property) => property.archived_at == null);
  const active = currentProperties.filter((property) => property.status === "active");
  const disposedCount = currentProperties.length - active.length;
  if (!active.length) return {
    informationState: absenceConfirmed ? "confirmed_absent" : "unreported",
    label: absenceConfirmed ? "Absence de bien immobilier confirmée" : "Non renseigné",
    currentKnownValue: absenceConfirmed ? 0 : null,
    missingActiveValues: 0,
    activeCount: 0,
    disposedCount,
  };
  const values = active.flatMap((property) => property.estimated_value === null ? [] : [property.estimated_value]);
  const activeLabel = active.length
    ? `${active.length} bien${active.length > 1 ? "s" : ""} actif${active.length > 1 ? "s" : ""}`
    : "Aucun bien actif";
  const disposedLabel = disposedCount
    ? ` · ${disposedCount} bien${disposedCount > 1 ? "s" : ""} cédé${disposedCount > 1 ? "s" : ""}`
    : "";
  return {
    informationState: values.length === active.length ? "complete" : "incomplete",
    label: `${activeLabel}${disposedLabel}`,
    currentKnownValue: values.length ? values.reduce((total, value) => total + value, 0) : null,
    missingActiveValues: active.length - values.length,
    activeCount: active.length,
    disposedCount,
  };
}

export function getDossierDebtState(
  debts: ReadonlyArray<{ status: "active" | "settled"; current_balance: number | null }>,
  absenceConfirmed = false,
): DossierDebtState {
  const active = debts.filter((debt) => debt.status === "active");
  const settledCount = debts.length - active.length;
  if (!active.length) return {
    informationState: absenceConfirmed ? "confirmed_absent" : "unreported",
    label: absenceConfirmed ? "Absence de dette active confirmée" : "Non renseigné",
    knownBalance: absenceConfirmed ? 0 : null,
    missingBalances: 0,
    activeCount: 0,
    settledCount,
  };
  const balances = active.flatMap((debt) => debt.current_balance === null ? [] : [debt.current_balance]);
  return {
    informationState: balances.length === active.length ? "complete" : "incomplete",
    label: `${active.length} dette${active.length > 1 ? "s" : ""} active${active.length > 1 ? "s" : ""}`,
    knownBalance: balances.length ? balances.reduce((total, balance) => total + balance, 0) : null,
    missingBalances: active.length - balances.length,
    activeCount: active.length,
    settledCount,
  };
}

export function getDossierAssetActionLabel(area: "properties" | "debts", count: number, canManage: boolean) {
  if (!canManage) return area === "properties" ? "Consulter les biens" : "Consulter les dettes";
  if (!count) return area === "properties" ? "Renseigner les biens" : "Renseigner les dettes";
  return area === "properties" ? "Gérer les biens" : "Gérer les dettes";
}
