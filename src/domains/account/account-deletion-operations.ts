import { createHash, randomUUID } from "node:crypto";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { AccountDeletionInput } from "./schemas";
import type { Database, Json } from "@/types/database";

type AccountClient = SupabaseClient<Database>;
type Eligibility = "eligible" | "blocked_owned_dossiers" | "blocked_platform_admin";
type OwnedStorageObject = Database["public"]["Functions"]["list_current_user_owned_storage_objects"]["Returns"][number];

type StorageSnapshot = {
  bytes: Uint8Array;
  size: number;
  sha256: string;
  contentType: string;
  cacheControl: string;
  metadata: Record<string, unknown>;
};

export class AccountDeletionBlockedError extends Error {
  readonly reason: Exclude<Eligibility, "eligible">;

  constructor(reason: Exclude<Eligibility, "eligible">) {
    super("Suppression de compte non autorisée.");
    this.reason = reason;
  }
}

export class AccountDeletionReauthenticationError extends Error {}
export class AccountDeletionStorageError extends Error {}
export class AccountDeletionAdminError extends Error {}

export async function getAccountDeletionEligibility(
  supabase: AccountClient,
  userId: string,
): Promise<Eligibility> {
  const [ownedDossier, administrator] = await Promise.all([
    supabase.from("protected_persons").select("id").eq("owner_id", userId).limit(1).maybeSingle(),
    supabase.from("platform_administrators").select("user_id").eq("user_id", userId).maybeSingle(),
  ]);
  if (ownedDossier.error || administrator.error) throw new Error("Impossible de vérifier l’éligibilité du compte.");
  if (ownedDossier.data) return "blocked_owned_dossiers";
  if (administrator.data) return "blocked_platform_admin";
  return "eligible";
}

export async function reauthenticateAccountDeletion(
  supabase: AccountClient,
  userId: string,
  currentPassword: string,
) {
  const current = await supabase.auth.getUser();
  if (current.error || !current.data.user?.email || current.data.user.id !== userId) {
    throw new AccountDeletionReauthenticationError("Réauthentification refusée.");
  }
  const reauthenticated = await supabase.auth.signInWithPassword({
    email: current.data.user.email,
    password: currentPassword,
  });
  if (reauthenticated.error || reauthenticated.data.user?.id !== userId) {
    throw new AccountDeletionReauthenticationError("Réauthentification refusée.");
  }
}

export async function listOwnedStorageObjects(supabase: AccountClient) {
  const { data, error } = await supabase.rpc("list_current_user_owned_storage_objects");
  if (error || !data) throw new AccountDeletionStorageError("Énumération Storage impossible.");
  return data;
}

function hash(bytes: Uint8Array) {
  return createHash("sha256").update(bytes).digest("hex");
}

function metadataRecord(value: Json): Record<string, unknown> {
  if (!value || Array.isArray(value) || typeof value !== "object") return {};
  return value as Record<string, unknown>;
}

function canonical(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).sort(([left], [right]) => left.localeCompare(right)).map(([key, item]) => [key, canonical(item)]));
  }
  return value;
}

function sameMetadata(left: unknown, right: unknown) {
  return JSON.stringify(canonical(left)) === JSON.stringify(canonical(right));
}

function cacheControlSeconds(value: string) {
  return value.replace(/^max-age=/, "");
}

async function inspectStorageObject(
  admin: AccountClient,
  bucketId: string,
  name: string,
): Promise<StorageSnapshot> {
  const storage = admin.storage.from(bucketId);
  const [download, info] = await Promise.all([storage.download(name), storage.info(name)]);
  if (download.error || !download.data || info.error || !info.data?.contentType || !info.data.cacheControl) {
    throw new AccountDeletionStorageError("Vérification Storage impossible.");
  }
  const bytes = new Uint8Array(await download.data.arrayBuffer());
  return {
    bytes,
    size: info.data.size ?? bytes.byteLength,
    sha256: hash(bytes),
    contentType: info.data.contentType,
    cacheControl: cacheControlSeconds(info.data.cacheControl),
    metadata: (info.data.metadata ?? {}) as Record<string, unknown>,
  };
}

function sameRequiredStorageData(actual: StorageSnapshot, expected: StorageSnapshot) {
  return actual.size === expected.size
    && actual.sha256 === expected.sha256
    && actual.contentType === expected.contentType
    && actual.cacheControl === expected.cacheControl
    && sameMetadata(actual.metadata, expected.metadata);
}

async function uploadFresh(
  admin: AccountClient,
  object: OwnedStorageObject,
  name: string,
  snapshot: StorageSnapshot,
) {
  const { error } = await admin.storage.from(object.bucket_id).upload(name, snapshot.bytes, {
    contentType: snapshot.contentType,
    cacheControl: snapshot.cacheControl,
    metadata: metadataRecord(object.user_metadata),
    upsert: false,
  });
  if (error) throw new AccountDeletionStorageError("Création Storage impossible.");
}

async function assertNotOwned(
  session: AccountClient,
  bucketId: string,
  name: string,
) {
  const owned = await listOwnedStorageObjects(session);
  if (owned.some((object) => object.bucket_id === bucketId && object.name === name)) {
    throw new AccountDeletionStorageError("La propriété Storage n’a pas été neutralisée.");
  }
}

async function restoreFromBackup(
  session: AccountClient,
  admin: AccountClient,
  object: OwnedStorageObject,
  backupName: string,
  expected: StorageSnapshot,
) {
  const backup = await inspectStorageObject(admin, object.bucket_id, backupName);
  if (!sameRequiredStorageData(backup, expected)) throw new AccountDeletionStorageError("Backup Storage invalide.");
  const storage = admin.storage.from(object.bucket_id);
  const removal = await storage.remove([object.name]);
  if (removal.error) throw new AccountDeletionStorageError("Récupération Storage impossible.");
  await uploadFresh(admin, object, object.name, backup);
  const restored = await inspectStorageObject(admin, object.bucket_id, object.name);
  if (!sameRequiredStorageData(restored, expected)) throw new AccountDeletionStorageError("Récupération Storage incomplète.");
  await assertNotOwned(session, object.bucket_id, object.name);
}

export async function neutralizeStorageObjectOwnership(
  session: AccountClient,
  admin: AccountClient,
  object: OwnedStorageObject,
) {
  const original = await inspectStorageObject(admin, object.bucket_id, object.name);
  const expectedMetadata = metadataRecord(object.user_metadata);
  if (!sameMetadata(original.metadata, expectedMetadata)) {
    throw new AccountDeletionStorageError("Métadonnées Storage incohérentes.");
  }

  const backupName = `${object.name}.sec02-backup-${randomUUID()}`;
  await uploadFresh(admin, object, backupName, original);
  const backup = await inspectStorageObject(admin, object.bucket_id, backupName);
  if (!sameRequiredStorageData(backup, original)) throw new AccountDeletionStorageError("Backup Storage invalide.");
  await assertNotOwned(session, object.bucket_id, backupName);

  const storage = admin.storage.from(object.bucket_id);
  const removal = await storage.remove([object.name]);
  if (removal.error) throw new AccountDeletionStorageError("Suppression Storage impossible.");

  try {
    await uploadFresh(admin, object, object.name, backup);
    const recreated = await inspectStorageObject(admin, object.bucket_id, object.name);
    if (!sameRequiredStorageData(recreated, original)) throw new AccountDeletionStorageError("Recréation Storage invalide.");
    await assertNotOwned(session, object.bucket_id, object.name);
  } catch {
    try {
      await restoreFromBackup(session, admin, object, backupName, original);
      const recoveryBackupRemoval = await storage.remove([backupName]);
      if (recoveryBackupRemoval.error) throw new AccountDeletionStorageError("Nettoyage du backup Storage impossible.");
    } catch {
      throw new AccountDeletionStorageError("Échec Storage avec récupération incomplète.");
    }
    throw new AccountDeletionStorageError("Échec Storage ; le fichier a été restauré.");
  }

  const backupRemoval = await storage.remove([backupName]);
  if (backupRemoval.error) throw new AccountDeletionStorageError("Nettoyage du backup Storage impossible.");
}

export async function neutralizeCurrentUserStorageOwnership(
  session: AccountClient,
  admin: AccountClient,
) {
  const objects = await listOwnedStorageObjects(session);
  for (const object of objects) {
    await neutralizeStorageObjectOwnership(session, admin, object);
  }
  const remaining = await listOwnedStorageObjects(session);
  if (remaining.length !== 0) throw new AccountDeletionStorageError("Des objets Storage restent rattachés au compte.");
  return objects.length;
}

export async function deleteAccountWithVerifiedDependencies(
  session: AccountClient,
  admin: AccountClient,
  userId: string,
  input: AccountDeletionInput,
) {
  const eligibility = await getAccountDeletionEligibility(session, userId);
  if (eligibility !== "eligible") throw new AccountDeletionBlockedError(eligibility);

  await reauthenticateAccountDeletion(session, userId, input.currentPassword);
  await neutralizeCurrentUserStorageOwnership(session, admin);

  const recheckedEligibility = await getAccountDeletionEligibility(session, userId);
  if (recheckedEligibility !== "eligible") throw new AccountDeletionBlockedError(recheckedEligibility);
  if ((await listOwnedStorageObjects(session)).length !== 0) {
    throw new AccountDeletionStorageError("Des objets Storage restent rattachés au compte.");
  }

  const deleted = await admin.auth.admin.deleteUser(userId);
  if (deleted.error || deleted.data.user?.id !== userId) {
    throw new AccountDeletionAdminError("Suppression Auth non confirmée.");
  }

  const signOut = await session.auth.signOut({ scope: "local" });
  if (signOut.error) throw new AccountDeletionAdminError("Nettoyage de session impossible.");
}
