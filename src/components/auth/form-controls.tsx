"use client";

import { useFormStatus } from "react-dom";
import type { AuthActionState } from "@/lib/auth/state";

export function SubmitButton({ children, pendingLabel }: { children: React.ReactNode; pendingLabel: string }) {
  const { pending } = useFormStatus();
  return <button className="auth-submit" type="submit" disabled={pending}>{pending ? pendingLabel : children}</button>;
}

export function FormMessage({ state, fieldMessages = [] }: {
  state: AuthActionState;
  fieldMessages?: { id: string; label: string; message: string }[];
}) {
  if (!state.message) return null;
  if (state.status === "error" && fieldMessages.length > 0) {
    return (
      <div className="auth-message auth-message-error" role="alert" aria-live="polite">
        <p>{state.message}</p>
        <ul className="mt-2 list-disc pl-5">
          {fieldMessages.map(({ id, label, message }) => (
            <li key={id}><a href={`#${id}`} className="underline">{label}</a> : {message}</li>
          ))}
        </ul>
      </div>
    );
  }
  return (
    <p className={`auth-message ${state.status === "success" ? "auth-message-success" : "auth-message-error"}`} role={state.status === "error" ? "alert" : "status"} aria-live="polite">
      {state.message}
    </p>
  );
}

export function FieldError({ messages }: { messages?: string[] }) {
  if (!messages?.length) return null;
  return <p className="mt-1.5 text-xs font-medium text-[#DC2626]">{messages[0]}</p>;
}
