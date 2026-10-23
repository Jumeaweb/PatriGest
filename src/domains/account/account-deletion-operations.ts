import { createHash, randomUUID } from "node:crypto";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { AccountDeletionInput } from "./schemas";
import type { Database, Json } from "@/types/database";
import {
  assertAccountDeletionDocumentBarrier,
  beginAccountStorageNeutralization,
  cancelAccountDeletionAuthorization,
  inspectAccountOwnedStorageObject,
  issueAccountDeletionAuthorization,
  listAccountStorageNeutralizations,
  resumeAccountStorageNeutralization,
  type AccountDeletionDurableAdminClient,
  type AccountDeletionDurableUserClient,
// @ts-expect-error Node's strip-types test runner requires the source extension.
} from "./account-deletion-durable.ts";
// @ts-expect-error Node's strip-types test runner requires the source extension.
import { isAccountDeletionDurableNeutralizationEnabled } from "./account-deletion-durable-availability.ts";

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
export class AccountDeletionAuthOutcomeUnknownError extends Error {}

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

function authUserMissing(error: unknown) {
  if (!error || typeof error !== "object") return false;
  const code = "code" in error ? String(error.code) : "";
  const status = "status" in error ? String(error.status) : "";
  return code === "user_not_found" || status === "404";
}

async function deleteAuthUserAndCloseSession(
  session: AccountClient,
  admin: AccountClient,
  userId: string,
) {
  let deletionConfirmed = false;
  try {
    const deleted = await admin.auth.admin.deleteUser(userId);
    deletionConfirmed = !deleted.error && deleted.data.user?.id === userId;
  } catch {
    // Une exception réseau peut survenir après traitement côté Auth. La
    // lecture autoritaire ci-dessous qualifie le résultat réel.
  }
  if (!deletionConfirmed) {
    let verification;
    try {
      verification = await admin.auth.admin.getUserById(userId);
    } catch {
      try {
        await session.auth.signOut({ scope: "local" });
      } catch {
        // L'incertitude Auth reste l'information prioritaire.
      }
      throw new AccountDeletionAuthOutcomeUnknownError(
        "Le résultat de la suppression Auth ne peut pas être confirmé.",
      );
    }
    if (verification.data.user?.id === userId) {
      throw new AccountDeletionAdminError("La suppression Auth a été refusée.");
    }
    if (!verification.error && !verification.data.user) {
      deletionConfirmed = true;
    } else if (authUserMissing(verification.error)) {
      deletionConfirmed = true;
    } else {
      try {
        await session.auth.signOut({ scope: "local" });
      } catch {
        // L'incertitude Auth reste l'information prioritaire.
      }
      throw new AccountDeletionAuthOutcomeUnknownError(
        "Le résultat de la suppression Auth ne peut pas être confirmé.",
      );
    }
  }
  if (!deletionConfirmed) {
    throw new AccountDeletionAuthOutcomeUnknownError(
      "Le résultat de la suppression Auth ne peut pas être confirmé.",
    );
  }
  try {
    const signOut = await session.auth.signOut({ scope: "local" });
    return { accountDeleted: true as const, sessionClosed: !signOut.error };
  } catch {
    return { accountDeleted: true as const, sessionClosed: false };
  }
}

async function deleteAccountWithDurableNeutralization(
  session: AccountClient,
  admin: AccountClient,
  userId: string,
  attemptId: string,
) {
  const userRpc = session as unknown as AccountDeletionDurableUserClient;
  const privileged = admin as unknown as AccountDeletionDurableAdminClient;
  const authorization = await issueAccountDeletionAuthorization(
    privileged,
    userId,
    attemptId,
  );
  let barrierPassed = authorization.state === "sealed";
  let documentOperationStarted = false;

  try {
    const previous = await listAccountStorageNeutralizations(privileged, userId);
    for (const operation of previous) {
      if (operation.phase !== "finalized") {
        documentOperationStarted = true;
        await resumeAccountStorageNeutralization(privileged, operation.operation_id);
      }
    }

    if (authorization.state === "cancelled") {
      throw new AccountDeletionStorageError("Cette tentative de suppression a été annulée.");
    }

    // Le gel SQL empêche les nouvelles mutations utilisateur. Plusieurs
    // passages bornés réconcilient néanmoins un upload déjà en vol au moment
    // de l'émission de l'autorisation.
    for (let pass = 0; pass < 8; pass += 1) {
      const objects = await listOwnedStorageObjects(session);
      if (objects.length === 0) break;
      if (authorization.state !== "active") {
        throw new AccountDeletionStorageError(
          "Un nouvel objet Storage est apparu après le scellement.",
        );
      }
      for (const object of objects) {
        documentOperationStarted = true;
        const observed = await inspectAccountOwnedStorageObject(privileged, object);
        const operationId = await beginAccountStorageNeutralization(
          userRpc,
          authorization.authorizationId,
          attemptId,
          object,
          observed,
        );
        await resumeAccountStorageNeutralization(privileged, operationId);
      }
    }

    if ((await listOwnedStorageObjects(session)).length !== 0) {
      throw new AccountDeletionStorageError(
        "Des objets Storage restent rattachés au compte.",
      );
    }
    const eligibility = await getAccountDeletionEligibility(session, userId);
    if (eligibility !== "eligible") throw new AccountDeletionBlockedError(eligibility);

    await assertAccountDeletionDocumentBarrier(
      privileged,
      authorization.authorizationId,
    );
    barrierPassed = true;
    return await deleteAuthUserAndCloseSession(session, admin, userId);
  } catch (error) {
    // Une opération commencée reste reprenable avec la même tentative. Une
    // autorisation sans opération (ou devenue métier-inéligible) peut être
    // annulée sans perdre d'état documentaire.
    if (!barrierPassed && (
      !documentOperationStarted || error instanceof AccountDeletionBlockedError
    )) {
      try {
        await cancelAccountDeletionAuthorization(
          privileged,
          authorization.authorizationId,
        );
      } catch {
        // Ne jamais masquer l'échec documentaire initial.
      }
    }
    throw error;
  }
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
  if (isAccountDeletionDurableNeutralizationEnabled()) {
    return deleteAccountWithDurableNeutralization(
      session,
      admin,
      userId,
      input.attemptId,
    );
  }
  await neutralizeCurrentUserStorageOwnership(session, admin);

  const recheckedEligibility = await getAccountDeletionEligibility(session, userId);
  if (recheckedEligibility !== "eligible") throw new AccountDeletionBlockedError(recheckedEligibility);
  if ((await listOwnedStorageObjects(session)).length !== 0) {
    throw new AccountDeletionStorageError("Des objets Storage restent rattachés au compte.");
  }

  return deleteAuthUserAndCloseSession(session, admin, userId);
}
