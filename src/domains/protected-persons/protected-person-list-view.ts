import type { ProtectedPersonListItem } from "./services/protected-person-service";

export type ProtectedPersonListView = "active" | "archived";

export function getProtectedPersonListView(value: string | string[] | undefined): ProtectedPersonListView {
  const requested = Array.isArray(value) ? value[0] : value;
  return requested === "archives" ? "archived" : "active";
}

export function partitionProtectedPersons(persons: ProtectedPersonListItem[]) {
  return {
    active: persons.filter((person) => person.status === "active"),
    archived: persons.filter((person) => person.status === "archived"),
  };
}
