type PeriodWriteFailure = { code?: string; message?: string };

export class ManagementPeriodWriteError extends Error {
  readonly reason: "overlap" | "permission" | "unavailable" | "linked_report" | "generic";
  constructor(reason: "overlap" | "permission" | "unavailable" | "linked_report" | "generic") {
    super(reason);
    this.reason = reason;
  }
}

export function classifyManagementPeriodWriteFailure(error: PeriodWriteFailure): ManagementPeriodWriteError {
  if (error.code === "23P01" || error.code === "23505" && error.message?.includes("management_periods_unique_dates_idx")) {
    return new ManagementPeriodWriteError("overlap");
  }
  if (error.code === "42501") return new ManagementPeriodWriteError("permission");
  if (error.code === "P4R02") return new ManagementPeriodWriteError("linked_report");
  return new ManagementPeriodWriteError("generic");
}

export function managementPeriodUserMessage(error: unknown, operation: "create" | "update") {
  if (error instanceof ManagementPeriodWriteError) {
    if (error.reason === "overlap") return "Les dates de cet exercice chevauchent un exercice existant. Choisissez une période qui ne recoupe aucun autre exercice.";
    if (error.reason === "permission") return "Vous ne pouvez pas gérer les exercices de ce dossier.";
    if (error.reason === "unavailable") return "Cet exercice est introuvable ou clôturé et ne peut plus être modifié.";
    if (error.reason === "linked_report") return "Les dates de cet exercice sont verrouillées car un compte de gestion y est déjà rattaché.";
  }
  return operation === "create"
    ? "Impossible de créer cet exercice pour le moment. Réessayez sans modifier les dates si elles sont correctes."
    : "Impossible de modifier cet exercice pour le moment. Réessayez ; aucune modification n’a été enregistrée.";
}
