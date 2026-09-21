import { PrivateNavigation, type PrivateDossierContext, type PrivateSection } from "@/components/layout/private-navigation";
import { ReleaseNotice } from "@/components/releases/release-notice";
import { getPrivateAccessContext } from "@/domains/administration/services/private-access-context";
import { getAuthenticatedUser } from "@/domains/protected-persons/services/authenticated-user";
import { APP_VERSION } from "@/lib/app";
import { LATEST_RELEASE } from "@/lib/releases";

export async function PrivateShell({ children, current, dossier }: { children: React.ReactNode; current: PrivateSection; dossier?: PrivateDossierContext }) {
  const { supabase, userId } = await getAuthenticatedUser();
  const [{ data: profile, error }, accessContext] = await Promise.all([
    supabase.from("profiles").select("last_seen_version").eq("id", userId).maybeSingle(),
    getPrivateAccessContext(),
  ]);
  if (error) throw new Error("Impossible de vérifier la version lue.");
  const showReleaseNotice = profile?.last_seen_version !== APP_VERSION;
  let navigationDossier = dossier;
  if (dossier && !dossier.accessRole) {
    const { data: person } = await supabase.from("protected_persons").select("owner_id").eq("id", dossier.id).maybeSingle();
    const { data: access } = person?.owner_id === userId ? { data: null } : await supabase.from("protected_person_access").select("role").eq("protected_person_id", dossier.id).eq("user_id", userId).maybeSingle();
    navigationDossier = { ...dossier, accessRole: person?.owner_id === userId ? "owner" : access?.role ?? "read_only" };
  }

  return <div className="min-h-screen bg-brand-background lg:flex">
    <PrivateNavigation current={current} dossier={navigationDossier} isPlatformAdmin={accessContext.isPlatformAdmin} />
    <div className="min-w-0 flex-1">
      {showReleaseNotice && <ReleaseNotice release={LATEST_RELEASE} />}
      <main className="private-content mx-auto w-full max-w-7xl px-5 py-8 sm:px-8 sm:py-10 xl:px-10">{children}</main>
    </div>
  </div>;
}
