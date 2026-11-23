"use client";

import { useActionState, type ReactNode } from "react";
import { FormMessage } from "@/components/auth/form-controls";
import { updateManagementReportAction } from "./actions";
import { initialManagementReportStatusState } from "./state";

export function ManagementReportUpdateForm({
  personId,
  reportId,
  editable,
  actions,
  children,
}: {
  personId: string;
  reportId: string;
  editable: boolean;
  actions?: ReactNode;
  children: ReactNode;
}) {
  const [state, action, pending] = useActionState(
    updateManagementReportAction.bind(null, personId, reportId),
    initialManagementReportStatusState,
  );

  return (
    <form action={action} className="mt-4 space-y-3">
      <fieldset
        disabled={!editable || pending}
        className="space-y-3 disabled:opacity-80"
      >
        {children}
        {(editable || actions) && (
          <div className="flex flex-wrap items-center gap-2">
            {editable && (
              <button className="button button-primary" disabled={pending}>
                {pending ? "Enregistrement…" : "Enregistrer"}
              </button>
            )}
            {actions}
            {editable && (
              <div className="basis-full">
                <FormMessage state={state} />
              </div>
            )}
          </div>
        )}
      </fieldset>
    </form>
  );
}
