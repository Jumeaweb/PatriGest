"use client";

import { useRef, useState } from "react";
import { Download, ExternalLink, FileUp, Trash2 } from "lucide-react";
import { useRouter } from "next/navigation";
import type { TransactionDocument } from "@/types/database";

export function TransactionProof({ personId, transactionId, reference, proof, canManage, durableOperationsEnabled, returnTo }: { personId: string; transactionId: string; reference: string; proof: TransactionDocument | null; canManage: boolean; durableOperationsEnabled: boolean; returnTo: string }) {
  const router = useRouter();
  const inputRef = useRef<HTMLInputElement>(null);
  const [pending, setPending] = useState(false);
  const [message, setMessage] = useState<{ kind: "success" | "error"; text: string } | null>(null);
  const endpoint = `/api/dossiers/${personId}/operations/${transactionId}/justificatif`;
  async function upload(formData: FormData) {
    setPending(true); setMessage(null);
    try {
      const response = await fetch(endpoint, { method: "POST", body: formData });
      const result = await response.json() as { message?: string };
      if (!response.ok) throw new Error(result.message || "Impossible d’envoyer le justificatif.");
      if (inputRef.current) inputRef.current.value = "";
      router.push(returnTo);
    } catch (error) { setMessage({ kind: "error", text: error instanceof Error ? error.message : "Impossible d’envoyer le justificatif." }); }
    finally { setPending(false); }
  }
  async function remove() {
    if (!window.confirm("Supprimer définitivement ce justificatif ?")) return;
    setPending(true); setMessage(null);
    try {
      const response = await fetch(endpoint, { method: "DELETE" });
      const result = await response.json() as { message?: string };
      if (!response.ok) throw new Error(result.message || "Impossible de supprimer le justificatif.");
      setMessage({ kind: "success", text: result.message ?? "Le justificatif a été supprimé." });
      router.refresh();
    } catch (error) { setMessage({ kind: "error", text: error instanceof Error ? error.message : "Impossible de supprimer le justificatif." }); }
    finally { setPending(false); }
  }
  return <section className="mt-4 max-w-4xl rounded-xl border border-[#E2E8F0] bg-white p-4"><h2 className="text-base font-bold">Justificatif</h2><dl className="mt-3 grid gap-3 text-xs sm:grid-cols-2"><div><dt className="font-semibold text-[#64748B]">Référence</dt><dd className="mt-0.5 text-sm font-bold">{reference}</dd></div><div><dt className="font-semibold text-[#64748B]">Pièce jointe</dt><dd className="mt-0.5 truncate text-sm font-semibold">{proof?.file_name ?? "Aucun fichier"}</dd></div></dl><div className="mt-3 flex flex-wrap gap-2">{proof && <><a className="button button-secondary gap-1.5" href={endpoint} target="_blank" rel="noreferrer"><ExternalLink size={14} />Voir</a><a className="button button-secondary gap-1.5" href={`${endpoint}?download=1`}><Download size={14} />Télécharger</a>{canManage && durableOperationsEnabled && <button className="button button-danger gap-1.5" type="button" disabled={pending} onClick={remove}><Trash2 size={14} />Supprimer le justificatif</button>}</>}{canManage && <form action={upload} className="flex flex-wrap items-center gap-2"><input ref={inputRef} className="max-w-full text-xs file:mr-2 file:rounded-md file:border-0 file:bg-slate-100 file:px-3 file:py-2 file:font-semibold" name="file" type="file" accept="application/pdf,image/jpeg,image/png" required /><button className="button button-primary gap-1.5" type="submit" disabled={pending}><FileUp size={14} />{pending ? "Envoi…" : proof ? "Remplacer" : "Ajouter un justificatif"}</button></form>}</div>{message && <p role="status" className={`mt-3 rounded-lg px-3 py-2 text-xs ${message.kind === "success" ? "bg-green-50 text-green-800" : "bg-red-50 text-red-700"}`}>{message.text}</p>}</section>;
}
