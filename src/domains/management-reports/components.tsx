import Link from "next/link";
import { CheckCircle2, TriangleAlert } from "lucide-react";
import {
  formatCurrency,
  formatFinancialDate,
} from "@/domains/financial-accounts/utils/financial-account-utils";
import { ReportStatusActions } from "./report-status-actions";
import { AccountSelectionManager } from "./account-selection-manager";
import { ManagementReportUpdateForm } from "./management-report-update-form";
import type { getManagementReportSnapshot } from "./services";
import { getClassificationIssueActions } from "./classification-issue-actions";
type Snapshot = NonNullable<
  Awaited<ReturnType<typeof getManagementReportSnapshot>>
>;
const choice = (name: string, value: boolean | null) => (
  <select
    className="auth-input"
    name={name}
    defaultValue={value === null ? "" : String(value)}
  >
    <option value="">À confirmer</option>
    <option value="false">Non</option>
    <option value="true">Oui</option>
  </select>
);

function startAbsenceLabel(
  account: Snapshot["situations"][number]["account"],
  periodStart: string,
) {
  if (account.opening_date && account.opening_date > periodStart) {
    return "En cours de période";
  }
  if (account.closing_date && account.closing_date < periodStart) {
    return "Clôturé avant";
  }
  return "Non présent";
}

export function ManagementReportDashboard({
  snapshot,
  canManage,
}: {
  snapshot: Snapshot;
  canManage: boolean;
}) {
  const { report, completeness } = snapshot;
  const issueActions = getClassificationIssueActions(report.protected_person_id, report.id, report.status, snapshot.classificationIssueCounts, canManage);
  const totals = {
    resources: snapshot.aggregation.resources.reduce(
      (sum, line) => sum + line.amount,
      0,
    ),
    expenses: snapshot.aggregation.expenses.reduce(
      (sum, line) => sum + line.amount,
      0,
    ),
  };
  const startSituations = snapshot.situations.filter((item) => item.selection.presentAtPeriodStart);
  const unavailableStartAccounts = startSituations.filter((item) => !item.startReliable);
  const start = unavailableStartAccounts.length === 0
    ? startSituations.reduce(
        (sum, item) => sum + (item.startBalance ?? 0),
        0,
      )
    : null;
  return (
    <>
      <div className="mt-4 grid items-start gap-3 md:grid-cols-2 xl:grid-cols-3">
        {completeness.sections.map((section) => (
          <a
            key={section.key}
            href={`#${section.key}`}
            className="focus-ring rounded-xl border border-[#E2E8F0] bg-white p-3"
          >
            <div className="flex items-center justify-between gap-2">
              <h2 className="text-sm font-bold">{section.label}</h2>
              {section.complete ? (
                <span className="flex items-center gap-1 text-xs font-semibold text-emerald-700">
                  <CheckCircle2 size={14} />
                  Complet
                </span>
              ) : (
                <span className="flex items-center gap-1 text-xs font-semibold text-amber-700">
                  <TriangleAlert size={14} />
                  {section.missing.length} à compléter
                </span>
              )}
            </div>
            {!section.complete && (
              <p className="mt-1 text-[11px] text-[#64748B]">
                {section.missing.join(" · ")}
              </p>
            )}
          </a>
        ))}
      </div>
      <div className="mt-4">
        <AccountSelectionManager
          personId={report.protected_person_id}
          reportId={report.id}
          canManage={canManage && report.status === "draft"}
          accounts={snapshot.accountSelections.map((selection) => ({
            accountId: selection.account.id,
            name: selection.account.account_name,
            type: selection.account.account_type,
            openingDate: selection.account.opening_date,
            closingDate: selection.account.closing_date,
            included: selection.included,
            presentAtPeriodStart: selection.presentAtPeriodStart,
            presentAtPeriodEnd: selection.presentAtPeriodEnd,
            selectionSource: selection.selectionSource,
            automaticReason: selection.automaticReason,
            manualMode: selection.manualMode,
            manualReason: selection.manualReason,
          }))}
        />
      </div>
      <ManagementReportUpdateForm
        personId={report.protected_person_id}
        reportId={report.id}
        editable={canManage && report.status === "draft"}
      >
          <section id="person" className="rounded-xl border bg-white p-4">
            <h2 className="font-bold">I. Personne protégée</h2>
            <p className="mt-1 text-sm">
              {snapshot.person.first_name} {snapshot.person.last_name}
            </p>
            <label className="auth-label mt-3">
              La résidence a-t-elle changé pendant la période ?
            </label>
            {choice("residenceChanged", report.residence_changed)}
          </section>
          <section id="measure" className="rounded-xl border bg-white p-4">
            <h2 className="font-bold">II. Mesure de protection</h2>
            <p className="mt-1 text-sm">
              {snapshot.measureCorrespondence?.direct
                ? snapshot.measureCorrespondence.officialLabel
                : "Type sans correspondance officielle directe — vérification requise"}
            </p>
            <label className="auth-label mt-3">
              L’adresse de la personne en charge a-t-elle changé ?
            </label>
            {choice(
              "representativeAddressChanged",
              report.representative_address_changed,
            )}
          </section>
          <section id="acts" className="rounded-xl border bg-white p-4">
            <h2 className="font-bold">III. Actes de gestion de l’année</h2>
            <p className="mt-2 text-xs">
              Patrimoine immobilier à la fin de période :{" "}
              <strong>
                {snapshot.properties.some(
                  (property) =>
                    property.status === "active" &&
                    (!property.entry_date ||
                      property.entry_date <= report.period_end),
                )
                  ? "Oui"
                  : "Non"}
              </strong>{" "}
              · {snapshot.propertyEvents.length} événement(s) détecté(s)
            </p>
            {snapshot.propertyEvents.map(({ property, event }) => (
              <p key={event.id} className="mt-1 text-xs">
                {formatFinancialDate(event.event_date)} — {property.designation}{" "}
                — {event.description}
              </p>
            ))}
            <label className="auth-label mt-3">
              Informations immobilières confirmées
            </label>
            {choice("realEstateConfirmed", report.real_estate_confirmed)}
            <p className="mt-3 text-xs">
              Placements détectés :{" "}
              <strong>{snapshot.placementAccounts.length}</strong>
            </p>
            <label className="auth-label mt-2">
              Informations sur les placements confirmées
            </label>
            {choice(
              "financialInvestmentsConfirmed",
              report.financial_investments_confirmed,
            )}
          </section>
          <section id="operations" className="rounded-xl border bg-white p-4">
            <h2 className="font-bold">Ressources, dépenses et balance</h2>
            <div className="mt-2 grid gap-3 sm:grid-cols-3">
              <Metric
                label="Solde de départ"
                value={start === null ? "Indisponible" : formatCurrency(start)}
              />
              <Metric
                label="Ressources"
                value={formatCurrency(totals.resources)}
              />
              <Metric
                label="Dépenses"
                value={formatCurrency(totals.expenses)}
              />
            </div>
            <p className="mt-2 text-sm font-bold">
              Solde résultant :{" "}
              {start === null
                ? "À compléter"
                : formatCurrency(start + totals.resources - totals.expenses)}
            </p>
            {unavailableStartAccounts.length > 0 && (
              <p className="mt-2 rounded-lg bg-amber-50 px-3 py-2 text-xs text-amber-800">
                Solde de départ incomplet : {unavailableStartAccounts.length} compte(s) sans situation fiable au début de la période. Le détail figure dans le bloc de complétude « Comptes et placements ».
              </p>
            )}
            <ReportLines
              title="Ressources"
              lines={snapshot.aggregation.resources}
            />
            <ReportLines
              title="Dépenses"
              lines={snapshot.aggregation.expenses}
            />
            {issueActions.length > 0 && (
              <div className="mt-3 flex flex-wrap gap-2">
                {issueActions.map((action) => (
                  <Link key={action.issue} className="button button-secondary text-xs" href={action.href}>
                    {action.label} ({action.count})
                  </Link>
                ))}
              </div>
            )}
          </section>
          <section id="accounts" className="rounded-xl border bg-white p-4">
            <h2 className="font-bold">Comptes et placements</h2>
            {snapshot.situations.map((item) => (
              <div
                key={item.account.id}
                className="mt-2 grid gap-1 border-t pt-2 text-xs sm:grid-cols-5"
              >
                <strong>{item.account.account_name}</strong>
                <span>
                  Départ{" "}
                  {!item.selection.presentAtPeriodStart
                    ? startAbsenceLabel(item.account, report.period_start)
                    : item.startBalance === null
                    ? "—"
                    : formatCurrency(item.startBalance)}
                </span>
                <span>Recettes {formatCurrency(item.income)}</span>
                <span>Dépenses {formatCurrency(item.expense)}</span>
                <span>
                  Fin{" "}
                  {!item.selection.presentAtPeriodEnd
                    ? item.account.closing_date
                      ? `Clôturé le ${formatFinancialDate(item.account.closing_date)}${item.endBalance === null ? "" : ` · ${formatCurrency(item.endBalance)}`}`
                      : "Non présent"
                    : item.endBalance === null
                    ? "—"
                    : formatCurrency(item.endBalance)}
                </span>
              </div>
            ))}
          </section>
          <section id="statements" className="rounded-xl border bg-white p-4">
            <h2 className="font-bold">Relevés / pièces</h2>
            {snapshot.latestStatements.map(({ account, statement }) => (
              <div
                key={account.id}
                className="mt-2 flex flex-wrap items-center justify-between gap-2 border-t pt-2 text-xs"
              >
                <span>
                  <strong>{account.account_name}</strong> —{" "}
                  {statement
                    ? `${formatFinancialDate(statement.statement_end_date)}${statement.statement_balance === null ? "" : ` · ${formatCurrency(statement.statement_balance)}`}`
                    : "Relevé manquant"}
                </span>
                {statement && (
                  <span className="flex gap-2">
                    <Link
                      className="text-blue-600"
                      href={`/api/dossiers/${report.protected_person_id}/comptes/${account.id}/releves/${statement.id}`}
                      target="_blank"
                    >
                      Voir
                    </Link>
                    <Link
                      className="text-blue-600"
                      href={`/api/dossiers/${report.protected_person_id}/comptes/${account.id}/releves/${statement.id}?download=1`}
                    >
                      Télécharger
                    </Link>
                  </span>
                )}
              </div>
            ))}
          </section>
          <section id="debts" className="rounded-xl border bg-white p-4">
            <h2 className="font-bold">Dettes</h2>
            {snapshot.relevantDebts.length ? (
              snapshot.relevantDebts.map(({ debt, balance }) => (
                <p key={debt.id} className="mt-2 border-t pt-2 text-xs">
                  <strong>{debt.creditor}</strong> — {debt.designation} ·
                  Mensualité{" "}
                  {debt.monthly_payment === null
                    ? "—"
                    : formatCurrency(debt.monthly_payment)}{" "}
                  · Situation{" "}
                  {balance
                    ? `${formatFinancialDate(balance.balance_date)} · ${formatCurrency(balance.remaining_balance)} · ${balance.remaining_duration_months ?? "—"} mois`
                    : "manquante"}
                </p>
              ))
            ) : (
              <p className="mt-2 text-xs text-[#64748B]">
                Aucune dette pertinente.
              </p>
            )}
          </section>
          <section id="observations" className="rounded-xl border bg-white p-4">
            <h2 className="font-bold">IV. Observations</h2>
            <label className="auth-label mt-2" htmlFor="observations">
              Observations patrimoniales
            </label>
            <textarea
              id="observations"
              name="observations"
              className="auth-input min-h-24"
              defaultValue={report.observations ?? ""}
            />
            <label className="auth-label mt-3" htmlFor="signaturePlace">
              V. Lieu de signature
            </label>
            <input
              id="signaturePlace"
              name="signaturePlace"
              className="auth-input"
              defaultValue={report.signature_place ?? ""}
            />
          </section>
      </ManagementReportUpdateForm>
      {canManage && (
        <div className="mt-3">
          <ReportStatusActions
            personId={report.protected_person_id}
            reportId={report.id}
            status={report.status}
            complete={completeness.complete}
          />
        </div>
      )}
    </>
  );
}
function Metric({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg bg-slate-50 p-2">
      <p className="text-[11px] text-slate-500">{label}</p>
      <p className="font-bold">{value}</p>
    </div>
  );
}
function ReportLines({
  title,
  lines,
}: {
  title: string;
  lines: Snapshot["aggregation"]["resources"];
}) {
  return (
    <div className="mt-3">
      <h3 className="text-xs font-bold uppercase text-slate-500">{title}</h3>
      {lines.map((line) => (
        <div
          key={line.officialCode}
          className="flex justify-between gap-3 py-1 text-xs"
        >
          <span>
            {line.officialCode} — {line.label}
          </span>
          <strong>{formatCurrency(line.amount)}</strong>
        </div>
      ))}
    </div>
  );
}
