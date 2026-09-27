import type { InfrastructureResult, InfrastructureStatus } from "../infrastructure-monitoring";

const statusPresentation: Record<InfrastructureStatus, { label: string; classes: string }> = {
  normal: { label: "Normal", classes: "bg-green-50 text-green-800" },
  warning: { label: "Attention", classes: "bg-amber-50 text-amber-800" },
  critical: { label: "Critique", classes: "bg-red-50 text-red-800" },
  unavailable: { label: "Indisponible", classes: "bg-slate-100 text-slate-700" },
};

const providerNames = { supabase: "Supabase", vercel: "Vercel", resend: "Resend", gandi: "Gandi" } as const;

export function InfrastructureDashboard({ results }: { results: InfrastructureResult[] }) {
  return <section className="mt-5 grid gap-4 md:grid-cols-2" aria-label="État des services externes">
    {results.map((result) => <InfrastructureCard key={result.provider} result={result} />)}
  </section>;
}

function InfrastructureCard({ result }: { result: InfrastructureResult }) {
  const presentation = statusPresentation[result.status];
  return <article className="rounded-xl border border-[#E2E8F0] bg-white p-4 shadow-[0_6px_18px_rgba(15,23,42,0.035)]">
    <div className="flex items-start justify-between gap-3">
      <div><h2 className="text-base font-bold">{providerNames[result.provider]}</h2><p className="mt-1 text-xs text-[#64748B]">Dernière vérification : {formatDateTime(result.checkedAt)}</p></div>
      <span className={`rounded-full px-2.5 py-1 text-xs font-bold ${presentation.classes}`}>{presentation.label}</span>
    </div>
    {result.status === "unavailable" ? <p className="mt-4 rounded-lg bg-slate-50 px-3 py-2 text-sm text-slate-700">{result.message}</p> : <InfrastructureDetails result={result} />}
  </article>;
}

function InfrastructureDetails({ result }: { result: InfrastructureResult }) {
  if (result.provider === "supabase") return <dl className="mt-4 grid gap-3 sm:grid-cols-2"><Metric label="Base de données" value={`${formatBytes(result.databaseBytes)} / 500 MB`} detail={`${formatPercent(result.databasePercent)} utilisés`} /><Metric label="Storage" value={`${formatBytes(result.storageBytes)} / 1 GB`} detail={`${formatPercent(result.storagePercent)} utilisés`} /></dl>;
  if (result.provider === "vercel") return <dl className="mt-4 grid gap-3 sm:grid-cols-2"><Metric label="Dernier déploiement Production" value={formatVercelState(result.deploymentState)} detail={result.deployedAt ? formatDateTime(result.deployedAt) : "Date indisponible"} /><Metric label="Commit Git" value={result.commitSha ?? "Indisponible"} /></dl>;
  if (result.provider === "resend") return <><p className="mt-3 text-xs font-semibold text-[#64748B]">E-mails transactionnels · 30 derniers jours</p><dl className="mt-3 grid grid-cols-2 gap-3"><Metric label="Envoyés" value={String(result.sent ?? 0)} /><Metric label="Délivrabilité" value={formatPercent(result.deliveryRate)} /><Metric label="Rebonds" value={formatPercent(result.bounceRate)} /><Metric label="Plaintes" value={formatPercent(result.complaintRate)} /></dl></>;
  return <dl className="mt-4 grid gap-3 sm:grid-cols-2"><Metric label="Domaine" value={result.domain} /><Metric label="Expiration" value={result.expiresAt ? formatDate(result.expiresAt) : "Indisponible"} detail={result.daysUntilExpiration === null ? undefined : `${result.daysUntilExpiration} jour(s)`} /><Metric label="Renouvellement automatique" value={result.autoRenew ? "Activé" : "Désactivé"} /></dl>;
}

function Metric({ label, value, detail }: { label: string; value: string; detail?: string }) {
  return <div className="rounded-lg bg-[#F8FAFC] px-3 py-2"><dt className="text-xs font-semibold text-[#64748B]">{label}</dt><dd className="mt-1 text-sm font-bold">{value}</dd>{detail && <dd className="mt-0.5 text-xs text-[#64748B]">{detail}</dd>}</div>;
}

function formatBytes(value: number | null) {
  if (value === null) return "Indisponible";
  const unit = value >= 1024 ** 3 ? "GB" : "MB";
  const divisor = unit === "GB" ? 1024 ** 3 : 1024 ** 2;
  return `${new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 1 }).format(value / divisor)} ${unit}`;
}

function formatPercent(value: number | null) {
  return value === null ? "Indisponible" : `${new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 1 }).format(value)} %`;
}

function formatDate(value: string) { return new Intl.DateTimeFormat("fr-FR", { dateStyle: "long", timeZone: "Europe/Paris" }).format(new Date(value)); }
function formatDateTime(value: string) { return new Intl.DateTimeFormat("fr-FR", { dateStyle: "short", timeStyle: "short", timeZone: "Europe/Paris" }).format(new Date(value)); }
function formatVercelState(value: string | null) {
  const labels: Record<string, string> = { READY: "Réussi", BUILDING: "En cours", QUEUED: "En attente", INITIALIZING: "Initialisation", ERROR: "Échec", CANCELED: "Annulé", BLOCKED: "Bloqué" };
  return value ? labels[value.toUpperCase()] ?? "Indéterminé" : "Indisponible";
}
