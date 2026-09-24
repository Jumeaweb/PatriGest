export function parseAdministrationUsersPage(value: string | string[] | undefined): number {
  const raw = Array.isArray(value) ? value[0] : value;
  const parsed = Number(raw);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : 1;
}

export function getAdministrationUsersPageHref(page: number): string {
  return page <= 1 ? "/administration/utilisateurs" : `/administration/utilisateurs?page=${page}`;
}
