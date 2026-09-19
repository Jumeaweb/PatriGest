type AuthUser = { email?: string };
type ListUsersResult = {
  data: { users: AuthUser[]; total?: number };
  error: Error | null;
};
type AuthAdmin = {
  listUsers(params: { page: number; perPage: number }): Promise<ListUsersResult>;
};

const usersPerPage = 1000;

export async function authUserExistsByEmail(admin: AuthAdmin, email: string) {
  const normalizedEmail = email.trim().toLowerCase();

  for (let page = 1; ; page += 1) {
    const { data, error } = await admin.listUsers({ page, perPage: usersPerPage });
    if (error) throw error;
    if (data.users.some((user) => user.email?.trim().toLowerCase() === normalizedEmail)) return true;

    const reachedKnownEnd = typeof data.total === "number" && page * usersPerPage >= data.total;
    if (data.users.length < usersPerPage || reachedKnownEnd) return false;
  }
}
