import type { ProtectedPerson } from "@/types/database";

type AddressFields = Pick<ProtectedPerson,
  | "address_line1" | "address_line2" | "postal_code" | "city" | "country"
  | "residence_address_line1" | "residence_address_line2" | "residence_postal_code" | "residence_city" | "residence_country"
>;

const present = (value: string | null | undefined) => Boolean(value?.trim());

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

export function getDossierPropertyState(properties: ReadonlyArray<{ estimated_value: number | null }>) {
  if (!properties.length) return { label: "Non renseigné", knownValue: null, missingValues: 0 };
  const values = properties.flatMap((property) => property.estimated_value === null ? [] : [property.estimated_value]);
  return {
    label: `${properties.length} bien${properties.length > 1 ? "s" : ""} renseigné${properties.length > 1 ? "s" : ""}`,
    knownValue: values.length ? values.reduce((total, value) => total + value, 0) : null,
    missingValues: properties.length - values.length,
  };
}

export function getDossierDebtState(debts: ReadonlyArray<{ status: "active" | "settled"; current_balance: number | null }>) {
  if (!debts.length) return { label: "Non renseigné", knownBalance: null, missingBalances: 0 };
  const active = debts.filter((debt) => debt.status === "active");
  if (!active.length) return { label: "Aucune dette active", knownBalance: null, missingBalances: 0 };
  const balances = active.flatMap((debt) => debt.current_balance === null ? [] : [debt.current_balance]);
  return {
    label: `${active.length} dette${active.length > 1 ? "s" : ""} active${active.length > 1 ? "s" : ""}`,
    knownBalance: balances.length ? balances.reduce((total, balance) => total + balance, 0) : null,
    missingBalances: active.length - balances.length,
  };
}

export function getDossierAssetActionLabel(area: "properties" | "debts", count: number, canManage: boolean) {
  if (!canManage) return area === "properties" ? "Consulter les biens" : "Consulter les dettes";
  if (!count) return area === "properties" ? "Renseigner les biens" : "Renseigner les dettes";
  return area === "properties" ? "Gérer les biens" : "Gérer les dettes";
}
