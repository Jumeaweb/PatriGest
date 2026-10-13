"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { AppConfirmDialog } from "@/components/ui/app-confirm-dialog";
import type { ManagementReportStatus } from "@/types/database";

type DialogKind = "generate" | "resume" | "finalize";

export function ReportDocumentActions({ personId, reportId, status, canManage, hasDocument, refreshRequiredAt }: { personId: string; reportId: string; status: ManagementReportStatus; canManage: boolean; hasDocument: boolean; refreshRequiredAt: string | null }) {
  const [dialog, setDialog] = useState<DialogKind | null>(null);
  const endpoint = `/api/dossiers/${personId}/comptes-de-gestion/${reportId}/document`;
  if (status === "ready" && canManage) return <><button type="button" className="button button-primary mt-3" onClick={() => setDialog("generate")}>Générer le projet PDF</button>{dialog === "generate" && <DocumentDialog kind="generate" endpoint={endpoint} onClose={() => setDialog(null)} />}</>;
  if (status === "generated" && hasDocument) return <div className="mt-3">{refreshRequiredAt&&<div role="status" className="mb-3 rounded-xl border border-amber-300 bg-amber-50 p-3"><p className="text-sm font-bold text-amber-900">Compte de gestion à actualiser</p><p className="mt-1 text-xs text-amber-800">Une information patrimoniale du projet a été corrigée. Reprenez la préparation puis générez un nouveau projet avant de pouvoir finaliser.</p></div>}<div className="flex flex-wrap items-center gap-2"><span className="rounded-full bg-amber-50 px-2 py-1 text-xs font-bold text-amber-700">Projet</span><span className="text-sm font-bold text-slate-700">Projet du compte de gestion généré</span></div><div className="mt-2 flex flex-wrap gap-2"><a className="button button-secondary" href={endpoint} target="_blank" rel="noreferrer">Voir le PDF projet</a><a className="button button-secondary" href={`${endpoint}?download=1`}>Télécharger le PDF projet</a>{canManage && <><button type="button" className="button button-secondary" onClick={() => setDialog("resume")}>Reprendre la préparation</button>{!refreshRequiredAt&&<button type="button" className="button button-primary" onClick={() => setDialog("finalize")}>Finaliser le compte de gestion</button>}</>}</div>{dialog && <DocumentDialog kind={dialog} endpoint={endpoint} onClose={() => setDialog(null)} />}</div>;
  if (["finalized", "transmitted", "approved", "difficulty"].includes(status) && hasDocument) { const label = status === "approved" ? "Approuvé" : status === "difficulty" ? "Difficulté signalée" : status === "transmitted" ? "Transmis" : "Finalisé"; return <div className="mt-3"><div className="flex flex-wrap items-center gap-2"><span className="rounded-full bg-emerald-50 px-2 py-1 text-xs font-bold text-emerald-700">{label}</span><span className="text-sm font-bold text-emerald-700">Compte de gestion {label.toLocaleLowerCase("fr-FR")}</span></div><div className="mt-2 flex flex-wrap gap-2"><a className="button button-secondary" href={endpoint} target="_blank" rel="noreferrer">Voir le PDF</a><a className="button button-secondary" href={`${endpoint}?download=1`}>Télécharger le PDF</a></div></div>; }
  return null;
}

const dialogs = {
  generate: { title: "Générer un projet du compte de gestion ?", description: "Un PDF portant le filigrane PROJET sera créé pour relecture. Vous pourrez encore reprendre la préparation et le régénérer.", action: "Générer le projet", pending: "Génération…", method: "POST" },
  resume: { title: "Reprendre la préparation ?", description: "Le PDF projet actuellement généré sera supprimé. Le compte de gestion repassera en préparation afin de permettre des corrections. Vous devrez ensuite le marquer de nouveau comme prêt et générer un nouveau projet.", action: "Reprendre la préparation", pending: "Reprise…", method: "DELETE" },
  finalize: { title: "Finaliser le compte de gestion ?", description: "Le PDF projet sera remplacé par la version officielle sans filigrane. Cette version sera figée et ne pourra plus être reprise en préparation dans le flux normal. Vérifiez attentivement le projet avant de continuer.", action: "Finaliser", pending: "Finalisation…", method: "PATCH" },
} as const;

function DocumentDialog({ kind, endpoint, onClose }: { kind: DialogKind; endpoint: string; onClose: () => void }) {
  const router = useRouter();
  const [pending, setPending] = useState(false);
  const [message, setMessage] = useState("");
  const copy = dialogs[kind];
  async function submit() {
    setPending(true);
    setMessage("");
    try {
      const response = await fetch(endpoint, { method: copy.method });
      const contentType = response.headers.get("content-type") ?? "";
      const text = await response.text();
      let result: { message?: string } = {};
      if (text && contentType.includes("application/json")) {
        try {
          result = JSON.parse(text) as { message?: string };
        } catch {
          result = {};
        }
      }
      if (!response.ok) throw new Error(result.message || "Impossible de générer le projet du compte de gestion.");
      if (!text) throw new Error("Impossible de générer le projet du compte de gestion.");
      onClose();
      router.refresh();
    } catch (error) {
      setMessage(error instanceof Error && error.message !== "Unexpected end of JSON input" ? error.message : "Impossible de générer le projet du compte de gestion.");
    } finally {
      setPending(false);
    }
  }
  return <AppConfirmDialog open onClose={onClose} title={copy.title} description={copy.description} actions={<button className="button button-primary" type="button" onClick={submit} disabled={pending}>{pending ? copy.pending : copy.action}</button>}>{message && <p role="alert" className="rounded-lg bg-red-50 px-3 py-2 text-xs text-red-700">{message}</p>}</AppConfirmDialog>;
}
