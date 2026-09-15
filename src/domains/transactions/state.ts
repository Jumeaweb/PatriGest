import type { AuthActionState } from "@/lib/auth/state";

export type TransactionActionState = AuthActionState & { proofUploadFailed?: boolean };

export const initialTransactionState: TransactionActionState = {
  status: "idle",
  message: "",
};
