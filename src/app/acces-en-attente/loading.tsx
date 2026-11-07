export default function AccessWaitingLoading() {
  return (
    <main className="flex min-h-screen items-center justify-center bg-[#F8FAFC] px-5 py-10">
      <section
        role="status"
        aria-live="polite"
        className="w-full max-w-lg rounded-2xl border border-[#E2E8F0] bg-white p-6 text-center shadow-[0_12px_36px_rgba(15,23,42,0.08)] sm:p-8"
      >
        <p className="text-sm font-semibold text-[#2563EB]">PatriGest</p>
        <h1 className="mt-2 text-2xl font-bold tracking-tight">
          Vérification en cours…
        </h1>
        <div className="mt-5 flex justify-center">
          <span
            aria-hidden="true"
            className="size-7 animate-spin rounded-full border-2 border-blue-200 border-t-blue-600"
          />
        </div>
        <p className="mt-4 text-sm text-[#64748B]">
          Nous vérifions si votre accès a été activé.
        </p>
      </section>
    </main>
  );
}