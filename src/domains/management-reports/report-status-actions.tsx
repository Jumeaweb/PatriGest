"use client";

import { useActionState, useState } from "react";
import { AppConfirmDialog } from "@/components/ui/app-confirm-dialog";
import {
  markManagementReportReadyAction,
  resumeManagementReportPreparationAction,
} from "./actions";
import { initialManagementReportStatusState } from "./state";
import type { ManagementReportStatus } from "@/types/database";

export function ReportStatusActions({
  personId,
  reportId,
  status,
  complete,
  withinForm = false,
}: {
  personId: string;
  reportId: string;
  status: ManagementReportStatus;
  complete: boolean;
  withinForm?: boolean;
}) {
  const [readyOpen, setReadyOpen] = useState(false);
  const [resumeOpen, setResumeOpen] = useState(false);

  if (status === "draft") {
    return (
      <>
        <button
          type="button"
          className="button button-secondary"
          disabled={!complete}
          onClick={() => setReadyOpen(true)}
        >
          Marquer comme prêt
        </button>
        {readyOpen && (
          <ReadyDialog
            personId={personId}
            reportId={reportId}
            withinForm={withinForm}
            onClose={() => setReadyOpen(false)}
          />
        )}
      </>
    );
  }

  if (status !== "ready") return null;

  return (
    <>
      <button
        type="button"
        className="button button-secondary"
        onClick={() => setResumeOpen(true)}
      >
        Reprendre la préparation
      </button>
      {resumeOpen && (
        <ResumeDialog
          personId={personId}
          reportId={reportId}
          onClose={() => setResumeOpen(false)}
        />
      )}
    </>
  );
}

function ReadyDialog({
  personId,
  reportId,
  withinForm,
  onClose,
}: {
  personId: string;
  reportId: string;
  withinForm: boolean;
  onClose: () => void;
}) {
  const [state, action, pending] = useActionState(
    markManagementReportReadyAction.bind(null, personId, reportId),
    initialManagementReportStatusState,
  );
  return (
    <AppConfirmDialog
      open
      onClose={onClose}
      title="Marquer le compte de gestion comme prêt ?"
      description="Toutes les informations obligatoires sont complètes. Le compte de gestion sera verrouillé pour modification jusqu’à une éventuelle reprise de la préparation."
      actions={
        withinForm ? (
          <button
            className="button button-primary"
            disabled={pending}
            formAction={action}
          >
            {pending ? "Vérification…" : "Marquer comme prêt"}
          </button>
        ) : (
          <form action={action}>
            <button className="button button-primary" disabled={pending}>
              {pending ? "Vérification…" : "Marquer comme prêt"}
            </button>
          </form>
        )
      }
    >
      <ActionMessage state={state} />
    </AppConfirmDialog>
  );
}

function ResumeDialog({
  personId,
  reportId,
  onClose,
}: {
  personId: string;
  reportId: string;
  onClose: () => void;
}) {
  const [state, action, pending] = useActionState(
    resumeManagementReportPreparationAction.bind(null, personId, reportId),
    initialManagementReportStatusState,
  );
  return (
    <AppConfirmDialog
      open
      onClose={onClose}
      title="Reprendre la préparation ?"
      description="Le compte de gestion repassera en préparation afin de permettre de nouvelles corrections."
      actions={
        <form action={action}>
          <button className="button button-primary" disabled={pending}>
            {pending ? "Réouverture…" : "Reprendre la préparation"}
          </button>
        </form>
      }
    >
      <ActionMessage state={state} />
    </AppConfirmDialog>
  );
}

function ActionMessage({
  state,
}: {
  state: typeof initialManagementReportStatusState;
}) {
  if (!state.message) return null;
  return (
    <p
      role="status"
      className={`text-xs font-semibold ${state.status === "error" ? "text-red-700" : "text-green-700"}`}
    >
      {state.message}
    </p>
  );
}
