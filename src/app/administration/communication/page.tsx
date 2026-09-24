import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { ReleaseNotificationPanel } from "@/domains/administration/components/release-notification-panel";
import { getReleaseNotificationDashboard } from "@/domains/administration/services/release-notification-service";
import { APP_VERSION } from "@/lib/app";

export const dynamic = "force-dynamic";

export default async function AdministrationCommunicationPage() {
  const releaseNotifications = await getReleaseNotificationDashboard(APP_VERSION);
  return (
    <PrivateShell current="administration-communications">
      <AppBreadcrumb items={[{ label: "Administration", href: "/administration" }, { label: "Communication utilisateurs" }]} />
      <header>
        <p className="text-xs font-bold uppercase tracking-widest text-[#2563EB]">Administration</p>
        <h1>Communication utilisateurs</h1>
        <p className="mt-1 text-sm text-[#64748B]">Informez les utilisateurs actifs des nouveautés de PatriGest.</p>
      </header>
      <ReleaseNotificationPanel {...releaseNotifications} />
    </PrivateShell>
  );
}
