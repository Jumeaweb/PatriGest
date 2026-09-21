export type DeleteUserState = { status: "idle" | "error" | "success"; message: string };
export const initialDeleteUserState: DeleteUserState = { status: "idle", message: "" };

export type RegistrationReviewState = {
  status: "idle" | "error" | "success" | "warning";
  message: string;
  decision?: "active" | "rejected";
};

export const initialRegistrationReviewState: RegistrationReviewState = { status: "idle", message: "" };

export type ReleaseNotificationActionState = {
  status: "idle" | "error" | "success";
  message: string;
  summary?: { recipients: number; alreadySent: number; sent: number; failed: number };
};

export const initialReleaseNotificationActionState: ReleaseNotificationActionState = { status: "idle", message: "" };
