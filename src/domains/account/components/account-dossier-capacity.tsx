import { AlertCircle, FolderKanban } from "lucide-react";
import {
  ACCOUNT_DOSSIER_CAPACITY_ERROR_MESSAGE,
  getAccountDossierCapacityPresentation,
  type AccountDossierCapacityResult,
} from "../account-dossier-capacity";

export function AccountDossierCapacity({ result }: { result: AccountDossierCapacityResult }) {
  if (result.status === "error") {
    return (
      <section aria-labelledby="dossier-capacity-title" className="mt-5 rounded-xl border border-amber-200 bg-amber-50/70 p-4">
        <div className="flex items-start gap-3">
          <AlertCircle aria-hidden="true" className="mt-0.5 shrink-0 text-amber-700" size={18} />
          <div>
            <h3 id="dossier-capacity-title" className="text-sm font-bold text-amber-950">Capacité de dossiers</h3>
            <p className="mt-1 text-sm leading-6 text-amber-950">{ACCOUNT_DOSSIER_CAPACITY_ERROR_MESSAGE}</p>
          </div>
        </div>
      </section>
    );
  }

  const presentation = getAccountDossierCapacityPresentation(result.capacity);

  return (
    <section aria-labelledby="dossier-capacity-title" className="mt-5 rounded-xl border border-[#E2E8F0] bg-slate-50 p-4">
      <div className="flex items-start gap-3">
        <FolderKanban aria-hidden="true" className="mt-0.5 shrink-0 text-brand-accent" size={19} />
        <div className="min-w-0">
          <h3 id="dossier-capacity-title" className="text-sm font-bold">Capacité de dossiers</h3>
          <dl className="mt-3 grid gap-2 text-sm sm:grid-cols-2">
            <div>
              <dt className="sr-only">Dossiers actifs</dt>
              <dd className="font-semibold text-[#334155]">{presentation.activeDossiersLabel}</dd>
            </div>
            {presentation.capacityLabel && (
              <div>
                <dt className="sr-only">Capacité autorisée</dt>
                <dd className="font-semibold text-[#334155]">{presentation.capacityLabel}</dd>
              </div>
            )}
            {presentation.remainingPlacesLabel && (
              <div>
                <dt className="sr-only">Places restantes</dt>
                <dd className="font-semibold text-[#334155]">{presentation.remainingPlacesLabel}</dd>
              </div>
            )}
          </dl>
          {presentation.notice && <p className="mt-3 text-xs font-semibold text-amber-800">{presentation.notice}</p>}
          {presentation.exceededLabel && <p className="mt-3 text-xs font-bold text-[#B45309]">{presentation.exceededLabel}</p>}
        </div>
      </div>
    </section>
  );
}
