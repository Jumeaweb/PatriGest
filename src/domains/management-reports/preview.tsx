import Link from "next/link";
import type { ManagementReportPreview } from "./preview-model";
import {
  formatCurrency,
  formatFinancialDate,
} from "@/domains/financial-accounts/utils/financial-account-utils";

const yesNo = (value: boolean | null) =>
  value === null ? "Non renseigné" : value ? "Oui" : "Non";
const value = (input: string | null | undefined) => input || "—";
const money = (input: number | null) =>
  input === null ? "Indisponible" : formatCurrency(input);
const date = (input: string | null | undefined) =>
  input ? formatFinancialDate(input) : "—";
const address = (parts: Array<string | null | undefined>) =>
  parts.filter(Boolean).join(", ") || "—";

export function ManagementReportPreviewView({
  preview,
  pinnedStatementVersions = new Map<string, string>(),
}: {
  preview: ManagementReportPreview;
  pinnedStatementVersions?: ReadonlyMap<string, string>;
}) {
  const { report, person, measure } = preview;
  return (
    <div className="mt-5 space-y-4 print:mt-0">
      {!preview.checks.consistent && (
        <div role="alert" className="rounded-xl border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900">
          <strong>Incohérence détectée.</strong> Vérifiez le référentiel et le classement des opérations avant toute utilisation documentaire.
          {preview.checks.unclassifiedOperations > 0 && (
            <span> {preview.checks.unclassifiedOperations} opération(s) ne sont pas classées.</span>
          )}
        </div>
      )}

      <section className="rounded-xl border border-[#CBD5E1] bg-white p-4">
        <p className="text-xs font-bold uppercase tracking-wider text-blue-600">Compte de gestion</p>
        <div className="mt-2 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <Datum label="Personne protégée" text={`${person.first_name} ${person.last_name}`} />
          <Datum label="Année" text={String(report.report_year)} />
          <Datum label="Période exacte" text={`${date(report.period_start)} → ${date(report.period_end)}`} />
          <Datum label="Statut" text={report.status === "ready" ? "Prêt" : "En préparation"} />
          <Datum label="Type de mesure" text={preview.measureCorrespondence?.direct ? preview.measureCorrespondence.officialLabel : "Sans correspondance officielle directe"} />
          <Datum label="Personne en charge" text={measure ? address([measure.representative_first_name, measure.representative_last_name]) : "—"} />
        </div>
      </section>

      <PreviewSection title="I — Personne protégée">
        <DataGrid>
          <Datum label="Prénom" text={person.first_name} />
          <Datum label="Nom" text={person.last_name} />
          <Datum label="Nom de naissance" text={value(person.birth_name)} />
          <Datum label="Date de naissance" text={date(person.birth_date)} />
          <Datum label="Lieu de naissance" text={value(person.birth_place)} />
          <Datum label="Domicile" text={address([person.address_line1, person.address_line2, person.postal_code, person.city, person.country])} />
          {(person.residence_address_line1 || person.residence_city) && (
            <Datum label="Résidence distincte" text={address([person.residence_address_line1, person.residence_address_line2, person.residence_postal_code, person.residence_city, person.residence_country])} />
          )}
          <Datum label="Téléphone" text={value(person.phone)} />
          <Datum label="Email" text={value(person.email)} />
          <Datum label="Résidence modifiée pendant la période" text={yesNo(preview.confirmations.residenceChanged)} />
        </DataGrid>
      </PreviewSection>

      <PreviewSection title="II — Mesure de protection">
        {measure ? (
          <DataGrid>
            <Datum label="Type" text={preview.measureCorrespondence?.direct ? preview.measureCorrespondence.officialLabel : "Type sans correspondance officielle directe"} />
            <Datum label="Ouverture / renouvellement" text={date(measure.start_date)} />
            <Datum label="Date de décision" text={date(measure.decision_date)} />
            <Datum label="Juridiction" text={value(measure.court_name)} />
            <Datum label="Ville de juridiction" text={value(measure.court_city)} />
            {(measure.measure_type !== "future_protection_mandate" || measure.case_reference) && <Datum label="Numéro RG" text={value(measure.case_reference)} />}
            {(measure.measure_type !== "future_protection_mandate" || measure.court_cabinet) && <Datum label="Cabinet" text={value(measure.court_cabinet)} />}
            <Datum label="Personne en charge" text={address([measure.representative_first_name, measure.representative_last_name])} />
            <Datum label="Date de nomination" text={date(measure.representative_appointment_date)} />
            <Datum label="Adresse" text={address([measure.representative_address_line1, measure.representative_address_line2, measure.representative_postal_code, measure.representative_city, measure.representative_country])} />
            <Datum label="Téléphone" text={value(measure.representative_phone)} />
            <Datum label="Email" text={value(measure.representative_email)} />
            <Datum label="Adresse modifiée pendant la période" text={yesNo(preview.confirmations.representativeAddressChanged)} />
          </DataGrid>
        ) : <Empty text="Mesure de protection indisponible." />}
      </PreviewSection>

      <OfficialTable title="III — Ressources" sections={preview.resources.sections} totalLabel="TOTAL RESSOURCES" total={preview.resources.total} />
      <OfficialTable title="IV — Dépenses" sections={preview.expenses.sections} totalLabel="TOTAL DÉPENSES" total={preview.expenses.total} />

      <section className="rounded-xl border-2 border-[#94A3B8] bg-white p-4">
        <h2 className="text-base font-bold">Résultat de la période</h2>
        <div className="mt-3 grid gap-2 text-sm sm:grid-cols-3">
          <Metric label="Total ressources" amount={preview.resources.total} />
          <Metric label="Total dépenses" amount={preview.expenses.total} />
          <Metric label="Résultat" amount={preview.result} strong />
        </div>
      </section>

      <PreviewSection title="V — Comptes financiers">
        <div className="overflow-x-auto">
          <table className="w-full min-w-[700px] text-left text-xs">
            <thead className="bg-slate-50 text-[11px] uppercase text-slate-500"><tr><th className="px-2 py-2">Compte</th><th className="px-2 py-2">Type</th><th className="px-2 py-2 text-right">Début</th><th className="px-2 py-2 text-right">Fin</th><th className="px-2 py-2">Fiabilité</th></tr></thead>
            <tbody className="divide-y">{preview.accounts.map((account) => <tr key={account.id}><td className="px-2 py-2"><strong>{account.name}</strong><br/><span className="text-slate-500">{account.institution}{account.reference ? ` · ${account.reference}` : ""}</span></td><td className="px-2 py-2">{account.type}</td><td className="px-2 py-2 text-right font-semibold tabular-nums">{money(account.startBalance)}</td><td className="px-2 py-2 text-right font-semibold tabular-nums">{money(account.endBalance)}</td><td className="px-2 py-2">{account.reliable ? "Disponible" : "Indisponible"}</td></tr>)}</tbody>
          </table>
        </div>
      </PreviewSection>

      <PreviewSection title="VI — Placements">
        {preview.placements.length ? <div className="grid gap-3 md:grid-cols-2">{preview.placements.map((placement) => <article key={placement.id} className="rounded-lg bg-slate-50 p-3 text-xs"><h3 className="text-sm font-bold">{placement.name}</h3><p className="text-slate-500">{placement.institution} · {placement.type}</p><div className="mt-2 grid grid-cols-2 gap-2"><Datum label={`Début${placement.startValueDate ? ` au ${date(placement.startValueDate)}` : ""}`} text={money(placement.startValue)} /><Datum label={`Fin${placement.endValueDate ? ` au ${date(placement.endValueDate)}` : ""}`} text={money(placement.endValue)} /></div><p className="mt-2 font-semibold">{placement.reliable ? "Valeurs disponibles" : "Valeur indisponible"}</p></article>)}</div> : <Empty text="Aucun placement pertinent." />}
      </PreviewSection>

      <PreviewSection title="VII — Relevés et pièces">
        <div className="space-y-2">{preview.statements.map((statement) => { const pinnedVersion = statement.statementId ? pinnedStatementVersions.get(statement.statementId) : null; const endpoint = statement.statementId ? `/api/dossiers/${report.protected_person_id}/comptes/${statement.accountId}/releves/${statement.statementId}${pinnedVersion ? `/versions/${pinnedVersion}` : ""}` : null; return <div key={statement.accountId} className="flex flex-wrap items-center justify-between gap-2 border-t pt-2 text-xs"><span><strong>{statement.accountName}</strong> — {statement.endDate ? `relevé au ${date(statement.endDate)}` : "relevé indisponible"}{statement.startDate && statement.endDate ? ` (${date(statement.startDate)} → ${date(statement.endDate)})` : ""} · {statement.hasDocument ? "PDF présent" : "PDF absent"}</span>{endpoint && <span className="flex gap-2"><Link className="text-blue-600" target="_blank" href={endpoint}>Voir</Link><Link className="text-blue-600" href={`${endpoint}?download=1`}>Télécharger</Link></span>}</div>; })}</div>
      </PreviewSection>

      <PreviewSection title="VIII — Patrimoine immobilier et actes de gestion">
        <p className="mb-3 text-xs">Patrimoine immobilier confirmé : <strong>{yesNo(preview.confirmations.realEstateConfirmed)}</strong> · Placements financiers confirmés : <strong>{yesNo(preview.confirmations.financialInvestmentsConfirmed)}</strong></p>
        {preview.properties.length ? <div className="grid gap-3 md:grid-cols-2">{preview.properties.map((property) => <article key={property.id} className="rounded-lg bg-slate-50 p-3 text-xs"><h3 className="text-sm font-bold">{property.designation}</h3><p>{property.type} · {property.status}</p><p className="text-slate-500">{value(property.address)}</p><p className="mt-2">Valeur estimée : <strong>{money(property.estimatedValue)}</strong>{property.valuationDate ? ` au ${date(property.valuationDate)}` : ""}</p>{property.disposalDate && <p>Cession : {date(property.disposalDate)}</p>}</article>)}</div> : <Empty text="Aucun bien pertinent." />}
        {preview.propertyEvents.length > 0 && <div className="mt-4"><h3 className="text-sm font-bold">Événements significatifs de la période</h3>{preview.propertyEvents.map((event) => <p key={event.id} className="mt-2 border-t pt-2 text-xs">{date(event.date)} — <strong>{event.property}</strong> — {event.type}{event.amount !== null ? ` · ${formatCurrency(event.amount)}` : ""}{event.description ? ` · ${event.description}` : ""}</p>)}</div>}
      </PreviewSection>

      <PreviewSection title="IX — Dettes et emprunts">
        {preview.debts.length ? <div className="grid gap-3 md:grid-cols-2">{preview.debts.map((debt) => <article key={debt.id} className="rounded-lg bg-slate-50 p-3 text-xs"><h3 className="text-sm font-bold">{debt.designation}</h3><p>{debt.creditor} · {debt.type} · {debt.status}</p><p className="mt-2">Montant initial : <strong>{money(debt.initialAmount)}</strong> · Mensualité : <strong>{money(debt.monthlyPayment)}</strong></p><p>Situation retenue : <strong>{date(debt.balanceDate)}</strong> · Solde restant : <strong>{money(debt.remainingBalance)}</strong>{debt.remainingDurationMonths !== null ? ` · ${debt.remainingDurationMonths} mois` : ""}</p></article>)}</div> : <Empty text="Aucune dette pertinente." />}
      </PreviewSection>

      <PreviewSection title="X — Observations">
        {preview.observations && <Datum label="Observations" text={preview.observations} />}
        {preview.signaturePlace && <div className="mt-3"><Datum label="Lieu de signature" text={preview.signaturePlace} /></div>}
        {!preview.observations && !preview.signaturePlace && <Empty text="Aucune observation renseignée." />}
      </PreviewSection>
    </div>
  );
}

function PreviewSection({ title, children }: { title: string; children: React.ReactNode }) {
  return <section className="break-inside-avoid rounded-xl border border-[#E2E8F0] bg-white p-4"><h2 className="mb-3 text-base font-bold">{title}</h2>{children}</section>;
}
function DataGrid({ children }: { children: React.ReactNode }) { return <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">{children}</div>; }
function Datum({ label, text }: { label: string; text: string }) { return <div className="min-w-0"><p className="text-[11px] font-semibold uppercase tracking-wide text-slate-500">{label}</p><p className="mt-0.5 whitespace-pre-wrap text-sm font-medium">{text}</p></div>; }
function Empty({ text }: { text: string }) { return <p className="text-sm text-slate-500">{text}</p>; }
function Metric({ label, amount, strong = false }: { label: string; amount: number; strong?: boolean }) { return <div className={`rounded-lg p-3 ${strong ? "bg-blue-50" : "bg-slate-50"}`}><p className="text-xs text-slate-500">{label}</p><p className={`${strong ? "text-lg" : "text-base"} font-bold tabular-nums`}>{formatCurrency(amount)}</p></div>; }
function OfficialTable({ title, sections, totalLabel, total }: { title: string; sections: ManagementReportPreview["resources"]["sections"]; totalLabel: string; total: number }) { return <PreviewSection title={title}><div className="overflow-x-auto"><table className="w-full min-w-[620px] text-xs"><tbody>{sections.map((section) => <OfficialGroup key={section.label} section={section} />)}<tr className="border-t-2 border-slate-400"><td className="px-2 py-2.5 font-bold" colSpan={2}>{totalLabel}</td><td className="px-2 py-2.5 text-right text-sm font-bold tabular-nums">{formatCurrency(total)}</td></tr></tbody></table></div></PreviewSection>; }
function OfficialGroup({ section }: { section: ManagementReportPreview["resources"]["sections"][number] }) { return <><tr className="border-t bg-slate-50"><th className="px-2 py-2 text-left text-xs font-bold" colSpan={3}>{section.label}</th></tr>{section.lines.map((line) => <tr key={line.code} className="border-t border-slate-100"><td className="w-24 px-2 py-1.5 font-mono text-[11px] text-slate-500">{line.code}</td><td className="px-2 py-1.5 text-left">{line.label}</td><td className="w-32 px-2 py-1.5 text-right font-semibold tabular-nums">{formatCurrency(line.amount)}</td></tr>)}</>; }
