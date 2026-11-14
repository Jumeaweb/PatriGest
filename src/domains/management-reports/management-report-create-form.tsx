"use client";

import { useActionState, useState } from "react";
import { FormMessage } from "@/components/auth/form-controls";
import { formatFinancialDate } from "@/domains/financial-accounts/utils/financial-account-utils";
import { createManagementReportAction } from "./actions";
import type { ManagementReportPeriodOption } from "./report-preparation-guidance";
import { initialManagementReportStatusState } from "./state";

export function ManagementReportCreateForm({
  personId,
  periods,
}: {
  personId: string;
  periods: ManagementReportPeriodOption[];
}) {
  const [selectedPeriodId, setSelectedPeriodId] = useState("");
  const [state, action, pending] = useActionState(
    createManagementReportAction.bind(null, personId),
    initialManagementReportStatusState,
  );
  const selectedPeriod = periods.find(
    (period) => period.id === selectedPeriodId && !period.covered,
  ) ?? null;

  return (
    <form action={action} className="mt-4 grid gap-2 rounded-xl border bg-white p-4 sm:grid-cols-4">
      <div className="sm:col-span-4">
        <label className="auth-label" htmlFor="management-report-period">
          Exercice de gestion
        </label>
        <select
          className="auth-input"
          id="management-report-period"
          name="managementPeriodId"
          required
          value={selectedPeriodId}
          onChange={(event) => setSelectedPeriodId(event.target.value)}
        >
          <option value="">Sélectionnez un exercice</option>
          {periods.map((period) => (
            <option key={period.id} value={period.id} disabled={period.covered}>
              {formatFinancialDate(period.start_date)} → {formatFinancialDate(period.end_date)}
              {period.status === "closed" ? " · clôturé" : " · ouvert"}
              {period.covered ? " · déjà couvert" : ""}
            </option>
          ))}
        </select>
        {periods.some((period) => period.covered) && (
          <p className="mt-1 text-[11px] text-slate-500">
            Les exercices déjà couverts, même partiellement, ne peuvent pas être sélectionnés.
          </p>
        )}
      </div>
      <div>
        <label className="auth-label" htmlFor="management-report-period-start">Début</label>
        <input id="management-report-period-start" className="auth-input" type="date" readOnly value={selectedPeriod?.start_date ?? ""} />
      </div>
      <div>
        <label className="auth-label" htmlFor="management-report-period-end">Fin</label>
        <input id="management-report-period-end" className="auth-input" type="date" readOnly value={selectedPeriod?.end_date ?? ""} />
      </div>
      <div>
        <label className="auth-label" htmlFor="management-report-year">Année</label>
        <input id="management-report-year" className="auth-input" type="number" readOnly value={selectedPeriod ? Number(selectedPeriod.end_date.slice(0, 4)) : ""} />
      </div>
      <button className="button button-primary self-end" disabled={pending || !selectedPeriod}>
        {pending ? "Préparation…" : "Préparer un compte de gestion"}
      </button>
      <div className="sm:col-span-4"><FormMessage state={state} /></div>
    </form>
  );
}
