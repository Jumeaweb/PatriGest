import "server-only";

import { mapDossierCapacityRpcError } from "@/domains/subscriptions/dossier-capacity";
import {
  executeProtectedPersonArchiveTransition,
  ProtectedPersonArchiveTransitionError,
  type ProtectedPersonArchiveRpcGateway,
  type ProtectedPersonArchiveRpcResult,
  type ProtectedPersonArchiveTransitionInput,
  type ProtectedPersonArchiveTransitionOperation,
} from "../archive-lifecycle";
import { getAuthenticatedUser } from "./authenticated-user";

type ArchiveRpcInvoker = (
  name: "archive_protected_person" | "restore_protected_person",
  args: {
    p_protected_person_id: string;
    p_expected_revision: number;
    p_reason: string;
  },
) => PromiseLike<ProtectedPersonArchiveRpcResult>;

function createProtectedPersonArchiveRpcGateway(
  supabase: Awaited<ReturnType<typeof getAuthenticatedUser>>["supabase"],
): ProtectedPersonArchiveRpcGateway {
  const rpc = supabase.rpc.bind(supabase) as unknown as ArchiveRpcInvoker;
  return {
    async transition(operation, input) {
      const rpcName = operation === "archive"
        ? "archive_protected_person"
        : "restore_protected_person";
      return await rpc(rpcName, {
        p_protected_person_id: input.protectedPersonId,
        p_expected_revision: input.expectedRevision,
        p_reason: input.reason,
      });
    },
  };
}

export async function changeProtectedPersonArchiveState(
  operation: ProtectedPersonArchiveTransitionOperation,
  input: ProtectedPersonArchiveTransitionInput,
) {
  let authenticated: Awaited<ReturnType<typeof getAuthenticatedUser>>;
  try {
    authenticated = await getAuthenticatedUser();
  } catch (error) {
    if (error instanceof Error
        && ["UNAUTHENTICATED", "APPLICATION_ACCESS_DENIED"].includes(error.message)) {
      throw new ProtectedPersonArchiveTransitionError("forbidden");
    }
    throw new ProtectedPersonArchiveTransitionError("technical");
  }

  return executeProtectedPersonArchiveTransition(
    createProtectedPersonArchiveRpcGateway(authenticated.supabase),
    operation,
    input,
    mapDossierCapacityRpcError,
  );
}

export function archiveProtectedPerson(input: ProtectedPersonArchiveTransitionInput) {
  return changeProtectedPersonArchiveState("archive", input);
}

export function restoreProtectedPerson(input: ProtectedPersonArchiveTransitionInput) {
  return changeProtectedPersonArchiveState("restore", input);
}
