export type AccessActionState = { status: "idle" | "success" | "warning" | "error"; message?: string; invitationUrl?: string; invitationExpiresAt?: string; fieldErrors?: Record<string, string[]> };
export const initialAccessState: AccessActionState = { status: "idle" };

export function isCompletedAccessAction(state: AccessActionState, warningCompletes = false) {
  return state.status === "success" || (warningCompletes && state.status === "warning");
}
