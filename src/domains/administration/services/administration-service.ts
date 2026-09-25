import "server-only";
import { notFound } from "next/navigation";
import type { User } from "@supabase/supabase-js";
import { createAdminClient } from "@/lib/supabase/admin";
import { createClient } from "@/lib/supabase/server";
import type { AccountMode, ApplicationUserAuthorizationStatus, SharedAccessRole } from "@/types/database";
import { sendApplicationActivationEmail } from "../registration-email";

export const ADMIN_USERS_PAGE_SIZE = 25;

export async function requirePlatformAdministrator() {
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  const userId = claims?.claims?.sub;
  if (!userId) notFound();
  const { data } = await supabase.from("platform_administrators").select("user_id").eq("user_id", userId).maybeSingle();
  if (!data) notFound();
  return { supabase, userId };
}

export async function getAccountRequests() {
  const { supabase } = await requirePlatformAdministrator();
  const { data, error } = await supabase.from("account_requests").select("*").order("created_at", { ascending: false });
  if (error) throw new Error("Impossible de charger les demandes.");
  return data;
}

export async function getPendingApplicationRegistrations() {
  await requirePlatformAdministrator();
  const admin = createAdminClient();
  const { data: authorizations, error } = await admin
    .from("application_user_authorizations")
    .select("user_id,status,created_at")
    .eq("status", "pending")
    .order("created_at", { ascending: false });
  if (error) throw new Error("Impossible de charger les inscriptions en attente.");
  if (!authorizations.length) return [];

  const ids = authorizations.map((authorization) => authorization.user_id);
  const [users, { data: profiles, error: profileError }] = await Promise.all([
    getAllAuthUsers(admin),
    admin.from("profiles").select("id,first_name,last_name").in("id", ids),
  ]);
  if (profileError) throw new Error("Impossible de charger les inscriptions en attente.");
  const userById = new Map(users.map((user) => [user.id, user]));
  const profileById = new Map((profiles ?? []).map((profile) => [profile.id, profile]));

  return authorizations.flatMap((authorization) => {
    const user = userById.get(authorization.user_id);
    if (!user?.email_confirmed_at) return [];
    return [{
      userId: authorization.user_id,
      email: user.email ?? "",
      firstName: profileById.get(authorization.user_id)?.first_name ?? "",
      lastName: profileById.get(authorization.user_id)?.last_name ?? "",
      createdAt: user.created_at,
      emailConfirmedAt: user.email_confirmed_at,
      status: authorization.status,
    }];
  });
}

export async function reviewApplicationRegistration(userId: string, decision: "active" | "rejected") {
  const { supabase } = await requirePlatformAdministrator();
  const admin = createAdminClient();
  const [{ data: targetResult, error: targetError }, { data: profile, error: profileError }] = await Promise.all([
    admin.auth.admin.getUserById(userId),
    admin.from("profiles").select("first_name,last_name").eq("id", userId).maybeSingle(),
  ]);
  if (targetError || !targetResult.user || profileError) throw new Error("Inscription introuvable.");
  if (!targetResult.user.email_confirmed_at) throw new Error("L’adresse e-mail doit être confirmée avant validation.");

  const { error } = await supabase.rpc("review_application_user_registration", {
    p_user_id: userId,
    p_decision: decision,
  });
  if (error) {
    if (error.message.includes("déjà été traitée")) throw new Error("Cette inscription a déjà été traitée.");
    throw new Error("Impossible de traiter cette inscription.");
  }

  if (decision === "rejected") return { emailSent: false };
  try {
    await sendApplicationActivationEmail({
      email: targetResult.user.email ?? "",
      firstName: profile?.first_name ?? "",
      lastName: profile?.last_name ?? "",
    });
    return { emailSent: true };
  } catch {
    return { emailSent: false };
  }
}

export async function resendApplicationActivationEmail(userId: string) {
  await requirePlatformAdministrator();
  const admin = createAdminClient();
  const [{ data: targetResult, error: targetError }, { data: authorization, error: authorizationError }, { data: profile, error: profileError }] = await Promise.all([
    admin.auth.admin.getUserById(userId),
    admin.from("application_user_authorizations").select("status").eq("user_id", userId).maybeSingle(),
    admin.from("profiles").select("first_name,last_name").eq("id", userId).maybeSingle(),
  ]);
  if (targetError || !targetResult.user || authorizationError || profileError) throw new Error("Compte utilisateur introuvable.");
  if (authorization?.status !== "active") throw new Error("L’accès de ce compte n’est pas actif.");
  if (!targetResult.user.email) throw new Error("Aucune adresse e-mail n’est disponible pour ce compte.");
  await sendApplicationActivationEmail({ email: targetResult.user.email, firstName: profile?.first_name ?? "", lastName: profile?.last_name ?? "" });
}

export type PlatformUserSummary = {
  id: string;
  email: string;
  createdAt: string;
  firstName: string;
  lastName: string;
  emailConfirmed: boolean;
  ownedDossiers: number;
  authorizationStatus: ApplicationUserAuthorizationStatus | undefined;
  accountMode: AccountMode | null;
  sharedAccesses: Array<{ protectedPersonId: string; protectedPersonName: string; role: SharedAccessRole }>;
  canResendActivationEmail: boolean;
  canDelete: boolean;
  deletionBlockReasons: string[];
};

export async function getPlatformUsers(requestedPage = 1) {
  const { userId: currentUserId } = await requirePlatformAdministrator();
  const admin = createAdminClient();
  const firstResult = await admin.auth.admin.listUsers({ page: requestedPage, perPage: ADMIN_USERS_PAGE_SIZE });
  if (firstResult.error) throw new Error("Impossible de charger les utilisateurs.");
  const page = firstResult.data.lastPage > 0 && requestedPage > firstResult.data.lastPage ? firstResult.data.lastPage : requestedPage;
  const pageResult = page === requestedPage
    ? firstResult
    : await admin.auth.admin.listUsers({ page, perPage: ADMIN_USERS_PAGE_SIZE });
  if (pageResult.error) throw new Error("Impossible de charger les utilisateurs.");
  const users = pageResult.data.users;
  const ids = users.map((user) => user.id);
  const emails = users.flatMap((user) => user.email ? [user.email.trim().toLowerCase()] : []);
  const now = new Date().toISOString();
  const results = await Promise.all([
    ids.length ? admin.from("profiles").select("id,first_name,last_name").in("id", ids) : Promise.resolve({ data: [] }),
    ids.length ? admin.from("protected_persons").select("id,owner_id").in("owner_id", ids) : Promise.resolve({ data: [] }),
    ids.length ? admin.from("platform_administrators").select("user_id,appointed_by").in("user_id", ids) : Promise.resolve({ data: [] }),
    ids.length ? admin.from("platform_administrators").select("user_id,appointed_by").in("appointed_by", ids) : Promise.resolve({ data: [] }),
    ids.length ? admin.from("application_user_authorizations").select("user_id,status,account_mode").in("user_id", ids) : Promise.resolve({ data: [] }),
    ids.length ? admin.from("protected_person_access").select("user_id,protected_person_id,role").in("user_id", ids) : Promise.resolve({ data: [] }),
    ids.length ? admin.from("protected_person_invitations").select("invited_by,email").in("invited_by", ids).is("accepted_at", null).is("revoked_at", null).gt("expires_at", now) : Promise.resolve({ data: [] }),
    emails.length ? admin.from("protected_person_invitations").select("invited_by,email").in("email", emails).is("accepted_at", null).is("revoked_at", null).gt("expires_at", now) : Promise.resolve({ data: [] }),
    ids.length ? admin.from("categories").select("owner_id").in("owner_id", ids) : Promise.resolve({ data: [] }),
    ids.length ? admin.from("transaction_documents").select("created_by").in("created_by", ids) : Promise.resolve({ data: [] }),
    ids.length ? admin.from("bank_statements").select("created_by").in("created_by", ids) : Promise.resolve({ data: [] }),
    ids.length ? admin.from("management_reports").select("created_by").in("created_by", ids) : Promise.resolve({ data: [] }),
    ids.length ? admin.from("management_report_documents").select("generated_by").in("generated_by", ids) : Promise.resolve({ data: [] }),
    ids.length ? admin.from("management_report_transmissions").select("declared_by").in("declared_by", ids) : Promise.resolve({ data: [] }),
    ids.length ? admin.from("management_report_approvals").select("declared_by").in("declared_by", ids) : Promise.resolve({ data: [] }),
    ids.length ? admin.from("management_report_difficulties").select("declared_by").in("declared_by", ids) : Promise.resolve({ data: [] }),
    ids.length ? admin.from("management_report_account_selections").select("created_by").in("created_by", ids) : Promise.resolve({ data: [] }),
  ]);
  if (results.some((result) => "error" in result && result.error)) throw new Error("Impossible de charger les informations des utilisateurs.");
  const [profilesResult, ownedResult, administratorsResult, appointedResult, authorizationsResult, accessesResult, invitationsByUserResult, invitationsByEmailResult, ...businessResults] = results;
  const profiles = profilesResult.data ?? [];
  const owned = ownedResult.data ?? [];
  const administrators = administratorsResult.data ?? [];
  const appointed = appointedResult.data ?? [];
  const authorizations = authorizationsResult.data ?? [];
  const accesses = accessesResult.data ?? [];
  const protectedPersonIds = [...new Set(accesses.map((access) => access.protected_person_id))];
  const personResult = protectedPersonIds.length
    ? await admin.from("protected_persons").select("id,first_name,last_name").in("id", protectedPersonIds)
    : { data: [], error: null };
  if (personResult.error) throw new Error("Impossible de charger les accès partagés.");

  const profileById = new Map((profiles ?? []).map((profile) => [profile.id, profile]));
  const counts = new Map<string, number>();
  for (const person of owned ?? []) counts.set(person.owner_id, (counts.get(person.owner_id) ?? 0) + 1);
  const administratorIds = new Set((administrators ?? []).map((administrator) => administrator.user_id));
  const appointedByIds = new Set((appointed ?? []).flatMap((administrator) => administrator.appointed_by ? [administrator.appointed_by] : []));
  const authorizationById = new Map((authorizations ?? []).map((authorization) => [authorization.user_id, authorization]));
  const personById = new Map((personResult.data ?? []).map((person) => [person.id, person]));
  const activeInvitationUserIds = new Set((invitationsByUserResult.data ?? []).flatMap((invitation) => invitation.invited_by ? [invitation.invited_by] : []));
  const activeInvitationEmails = new Set((invitationsByEmailResult.data ?? []).map((invitation) => invitation.email.trim().toLowerCase()));
  const businessUserIds = new Set<string>();
  for (const result of businessResults) {
    for (const row of result.data ?? []) {
      const value = "owner_id" in row ? row.owner_id : "created_by" in row ? row.created_by : "generated_by" in row ? row.generated_by : row.declared_by;
      if (value) businessUserIds.add(value);
    }
  }

  const summaries: PlatformUserSummary[] = users.map((user) => {
    const authorization = authorizationById.get(user.id);
    const sharedAccesses = accesses.filter((access) => access.user_id === user.id).map((access) => {
      const person = personById.get(access.protected_person_id);
      return {
        protectedPersonId: access.protected_person_id,
        protectedPersonName: person ? `${person.first_name} ${person.last_name}`.trim() : "Dossier accessible",
        role: access.role,
      };
    });
    const reasons = new Set<string>();
    if (user.id === currentUserId) reasons.add("Compte administrateur actuellement connecté");
    if (administratorIds.has(user.id)) reasons.add("Administrateur PatriGest");
    if (appointedByIds.has(user.id)) reasons.add("Relation d’administration conservée");
    if ((counts.get(user.id) ?? 0) > 0) reasons.add("Dossier possédé");
    if (sharedAccesses.length > 0) reasons.add("Accès à un dossier partagé");
    if (activeInvitationUserIds.has(user.id) || (user.email && activeInvitationEmails.has(user.email.trim().toLowerCase()))) reasons.add("Invitation de partage active");
    if (businessUserIds.has(user.id)) reasons.add("Données métier associées");
    return {
      id: user.id,
      email: user.email ?? "",
      createdAt: user.created_at,
      firstName: profileById.get(user.id)?.first_name ?? "",
      lastName: profileById.get(user.id)?.last_name ?? "",
      emailConfirmed: Boolean(user.email_confirmed_at),
      ownedDossiers: counts.get(user.id) ?? 0,
      authorizationStatus: authorization?.status,
      accountMode: authorization?.account_mode ?? null,
      sharedAccesses,
      canResendActivationEmail: authorization?.status === "active" && !administratorIds.has(user.id),
      canDelete: reasons.size === 0,
      deletionBlockReasons: [...reasons],
    };
  });

  return {
    users: summaries,
    page,
    total: pageResult.data.total,
    totalPages: Math.max(1, pageResult.data.lastPage || Math.ceil(pageResult.data.total / ADMIN_USERS_PAGE_SIZE)),
  };
}

export async function deletePlatformUser(userId: string) {
  const { userId: currentUserId } = await requirePlatformAdministrator();
  if (userId === currentUserId) throw new Error("Vous ne pouvez pas supprimer votre propre compte administrateur.");
  const admin = createAdminClient();
  const { data: targetResult, error: targetError } = await admin.auth.admin.getUserById(userId);
  if (targetError || !targetResult.user) throw new Error("Utilisateur introuvable.");
  const email = targetResult.user.email ?? "";
  const now = new Date().toISOString();
  const blockingRelations = await Promise.all([
    admin.from("platform_administrators").select("user_id").or(`user_id.eq.${userId},appointed_by.eq.${userId}`).limit(1),
    admin.from("protected_persons").select("id").eq("owner_id", userId).limit(1),
    admin.from("protected_person_access").select("id").eq("user_id", userId).limit(1),
    admin.from("protected_person_invitations").select("id").eq("invited_by", userId).is("accepted_at", null).is("revoked_at", null).gt("expires_at", now).limit(1),
    email ? admin.from("protected_person_invitations").select("id").ilike("email", email).is("accepted_at", null).is("revoked_at", null).gt("expires_at", now).limit(1) : Promise.resolve({ data: [], error: null }),
    admin.from("categories").select("id").eq("owner_id", userId).limit(1),
    admin.from("transaction_documents").select("id").eq("created_by", userId).limit(1),
    admin.from("bank_statements").select("id").eq("created_by", userId).limit(1),
    admin.from("management_reports").select("id").eq("created_by", userId).limit(1),
    admin.from("management_report_documents").select("id").eq("generated_by", userId).limit(1),
    admin.from("management_report_transmissions").select("id").eq("declared_by", userId).limit(1),
    admin.from("management_report_approvals").select("id").eq("declared_by", userId).limit(1),
    admin.from("management_report_difficulties").select("id").eq("declared_by", userId).limit(1),
    admin.from("management_report_account_selections").select("id").eq("created_by", userId).limit(1),
  ]);
  if (blockingRelations.some((result) => result.error)) throw new Error("Impossible de vérifier les dépendances de cet utilisateur.");
  if (blockingRelations[0].data?.length) throw new Error("Cet utilisateur possède encore une relation d’administration et ne peut pas être supprimé.");
  if (blockingRelations.slice(1).some((result) => result.data?.length)) {
    throw new Error("Cet utilisateur ne peut pas être supprimé tant qu’il possède un dossier ou dispose encore d’un accès ou de données métier associées.");
  }
  const { error } = await admin.auth.admin.deleteUser(userId);
  if (error) throw new Error("Impossible de supprimer cet utilisateur.");
}

export type AdministrationDashboardData = {
  usersCount: number;
  pendingRequestsCount: number;
  pendingInvitationsCount: number;
  pendingRequests: Awaited<ReturnType<typeof getAccountRequests>>;
  pendingRegistrations: Awaited<ReturnType<typeof getPendingApplicationRegistrations>>;
};

export async function getAdministrationDashboardData(): Promise<AdministrationDashboardData> {
  const { supabase } = await requirePlatformAdministrator();
  const admin = createAdminClient();
  const now = new Date().toISOString();
  const [usersResult, requestsResult, invitationsResult, pendingRegistrations] = await Promise.all([
    admin.auth.admin.listUsers({ page: 1, perPage: 1 }),
    supabase.from("account_requests").select("*").eq("status", "pending").order("created_at", { ascending: false }),
    admin.from("protected_person_invitations").select("id", { count: "exact", head: true }).is("accepted_at", null).is("revoked_at", null).gt("expires_at", now),
    getPendingApplicationRegistrations(),
  ]);

  if (usersResult.error || requestsResult.error || invitationsResult.error) {
    throw new Error("Impossible de charger le tableau de bord d’administration.");
  }

  return {
    usersCount: usersResult.data.total,
    pendingRequestsCount: pendingRegistrations.length,
    pendingInvitationsCount: invitationsResult.count ?? 0,
    pendingRequests: requestsResult.data.slice(0, 5),
    pendingRegistrations: pendingRegistrations.slice(0, 5),
  };
}

async function getAllAuthUsers(admin: ReturnType<typeof createAdminClient>) {
  const users: User[] = [];
  const perPage = 1000;

  for (let page = 1; ; page += 1) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage });
    if (error) throw new Error("Impossible de charger les utilisateurs.");
    users.push(...data.users);
    if (data.users.length < perPage) return users;
  }
}
