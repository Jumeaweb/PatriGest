"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";
import { BadgeCheck, CircleHelp } from "lucide-react";
import { FormMessage } from "@/components/auth/form-controls";
import { AppConfirmDialog } from "@/components/ui/app-confirm-dialog";
import {
  confirmActiveDebtAbsenceAction,
  confirmRealEstateAbsenceAction,
  withdrawActiveDebtAbsenceConfirmationAction,
  withdrawRealEstateAbsenceConfirmationAction,
} from "@/domains/assets-liabilities/actions";
import { initialAssetLiabilityState, type AssetLiabilityActionState } from "@/domains/assets-liabilities/state";
import type { PatrimonyAbsenceCategory, PatrimonyAbsenceConfirmation } from "@/types/database";

type Props = {
  personId: string;
  category: PatrimonyAbsenceCategory;
  confirmation: PatrimonyAbsenceConfirmation | null;
  canManage: boolean;
};

const content = {
  real_estate: {
    prompt: "Je confirme qu’aucun bien immobilier n’est actuellement détenu.",
    confirmed: "Absence de bien immobilier confirmée",
    confirmTitle: "Confirmer l’absence de bien immobilier ?",
    confirmDescription: "Cette confirmation indique qu’aucun bien immobilier actif et non archivé n’est actuellement détenu.",
    withdrawDescription: "La situation immobilière redeviendra non renseignée tant qu’aucun bien actif ne sera enregistré ou qu’une nouvelle confirmation ne sera donnée.",
  },
  active_debt: {
    prompt: "Je confirme qu’aucune dette n’est actuellement en cours.",
    confirmed: "Absence de dette active confirmée",
    confirmTitle: "Confirmer l’absence de dette active ?",
    confirmDescription: "Cette confirmation indique qu’aucune dette active n’est actuellement en cours.",
    withdrawDescription: "La situation des dettes redeviendra non renseignée tant qu’aucune dette active ne sera enregistrée ou qu’une nouvelle confirmation ne sera donnée.",
  },
} as const;

const dateFormatter = new Intl.DateTimeFormat("fr-FR", { dateStyle: "long", timeZone: "Europe/Paris" });

export function PatrimonyAbsenceConfirmationControl({ personId, category, confirmation, canManage }: Props) {
  const router = useRouter();
  const [dialog, setDialog] = useState<"confirm" | "withdraw" | null>(null);
  const [state, setState] = useState<AssetLiabilityActionState>(initialAssetLiabilityState);
  const [pending, startTransition] = useTransition();
  const labels = content[category];
  const confirmed = confirmation !== null;

  function closeDialog() {
    if (!pending) setDialog(null);
  }

  function openDialog() {
    setState(initialAssetLiabilityState);
    setDialog(confirmed ? "withdraw" : "confirm");
  }

  function submit() {
    const action = category === "real_estate"
      ? confirmed ? withdrawRealEstateAbsenceConfirmationAction : confirmRealEstateAbsenceAction
      : confirmed ? withdrawActiveDebtAbsenceConfirmationAction : confirmActiveDebtAbsenceAction;

    startTransition(async () => {
      const result = await action(personId);
      setState(result);
      if (result.status === "success") {
        setDialog(null);
        router.refresh();
      }
    });
  }

  return <>
    <section className="mt-3 flex flex-col gap-3 rounded-xl border border-[#BFDBFE] bg-[#EFF6FF] p-4 sm:flex-row sm:items-center sm:justify-between" aria-label="Confirmation patrimoniale">
      <div className="flex min-w-0 items-start gap-3">
        <span className="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full bg-white text-[#2563EB]" aria-hidden="true">
          {confirmed ? <BadgeCheck size={18} /> : <CircleHelp size={18} />}
        </span>
        <div className="min-w-0">
          {confirmed
            ? <p className="text-sm font-semibold text-[#1E3A8A]">{labels.confirmed} le {dateFormatter.format(new Date(confirmation.confirmed_at))}.</p>
            : <p className="text-sm text-[#1E3A8A]">Cette absence n’a pas encore été confirmée.</p>}
          <FormMessage state={state} />
        </div>
      </div>
      {canManage && <button
        type="button"
        className={`button w-full shrink-0 self-start text-center sm:w-auto sm:self-center ${confirmed ? "button-secondary" : "button-primary"}`}
        disabled={pending}
        onClick={openDialog}
      >{confirmed ? "Retirer la confirmation" : labels.prompt}</button>}
    </section>
    <AppConfirmDialog
      open={dialog !== null}
      onClose={closeDialog}
      requireExplicitClose={pending}
      title={dialog === "withdraw" ? "Retirer cette confirmation ?" : labels.confirmTitle}
      description={dialog === "withdraw" ? labels.withdrawDescription : labels.confirmDescription}
      actions={<button type="button" className="button button-primary" disabled={pending} onClick={submit}>
        {pending ? "Enregistrement…" : dialog === "withdraw" ? "Confirmer le retrait" : "Confirmer l’absence"}
      </button>}
    ><FormMessage state={state} /></AppConfirmDialog>
  </>;
}
