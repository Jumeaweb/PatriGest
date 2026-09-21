export type ReleaseRecipient = {
  userId: string;
  email: string;
  firstName: string;
  lastName: string;
};

export type RecipientAuthUser = {
  id: string;
  email: string | null | undefined;
  emailConfirmedAt: string | null | undefined;
};

export async function collectAllPages<T>(loadPage: (page: number, perPage: number) => Promise<readonly T[]>, perPage = 1000) {
  const items: T[] = [];
  for (let page = 1; ; page += 1) {
    const current = await loadPage(page, perPage);
    items.push(...current);
    if (current.length < perPage) return items;
  }
}

export function selectEligibleReleaseRecipients({ users, activeUserIds, administratorIds, profiles = new Map() }: {
  users: readonly RecipientAuthUser[];
  activeUserIds: ReadonlySet<string>;
  administratorIds: ReadonlySet<string>;
  profiles?: ReadonlyMap<string, { firstName: string; lastName: string }>;
}) {
  const recipients = new Map<string, ReleaseRecipient>();
  for (const user of users) {
    const email = user.email?.trim();
    if (!email || !user.emailConfirmedAt) continue;
    if (!activeUserIds.has(user.id) && !administratorIds.has(user.id)) continue;
    const profile = profiles.get(user.id);
    recipients.set(user.id, {
      userId: user.id,
      email,
      firstName: profile?.firstName ?? "",
      lastName: profile?.lastName ?? "",
    });
  }
  return [...recipients.values()].sort((left, right) => left.email.localeCompare(right.email, "fr"));
}
