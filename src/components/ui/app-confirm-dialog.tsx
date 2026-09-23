"use client";

import { useEffect, useId, useRef } from "react";
import { X } from "lucide-react";

type AppConfirmDialogProps = {
  open: boolean;
  title: string;
  description: string;
  subject?: string;
  children?: React.ReactNode;
  actions: React.ReactNode;
  onClose: () => void;
  size?: "default" | "wide";
  cancelLabel?: string;
};

export function AppConfirmDialog({ open, title, description, subject, children, actions, onClose, size = "default", cancelLabel = "Annuler" }: AppConfirmDialogProps) {
  const dialogRef = useRef<HTMLDialogElement>(null);
  const cancelButtonRef = useRef<HTMLButtonElement>(null);
  const titleId = useId();
  const descriptionId = useId();

  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) return;

    if (open && !dialog.open) {
      dialog.showModal();
      cancelButtonRef.current?.focus();
    } else if (!open && dialog.open) {
      dialog.close();
    }
  }, [open]);

  return (
    <dialog
      ref={dialogRef}
      aria-labelledby={titleId}
      aria-describedby={descriptionId}
      className={`m-auto max-h-[calc(100dvh-2rem)] w-[calc(100%-2rem)] ${size === "wide" ? "max-w-3xl" : "max-w-md"} overflow-y-auto rounded-2xl border border-[#E2E8F0] bg-white p-0 text-[#0F172A] shadow-2xl backdrop:bg-slate-950/45`}
      onCancel={(event) => { event.preventDefault(); onClose(); }}
      onClose={onClose}
    >
      <div className="p-4 sm:p-5">
        <div className="flex items-start justify-between gap-3">
          <div><h2 id={titleId} className="text-lg font-bold tracking-tight sm:text-xl">{title}</h2><p id={descriptionId} className="mt-2 text-sm leading-5 text-[#64748B]">{description}</p></div>
          <button type="button" className="focus-ring flex size-9 shrink-0 items-center justify-center rounded-lg text-[#64748B] hover:bg-slate-100" aria-label="Fermer la boîte de dialogue" onClick={onClose}><X aria-hidden="true" size={19} /></button>
        </div>
        {subject && <p className="mt-3 rounded-lg bg-[#F8FAFC] px-3 py-2 text-sm font-bold text-[#334155]">{subject}</p>}
        {children && <div className="mt-3">{children}</div>}
        <div className="mt-5 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
          <button ref={cancelButtonRef} type="button" className="button button-secondary" onClick={onClose}>{cancelLabel}</button>
          {actions}
        </div>
      </div>
    </dialog>
  );
}
