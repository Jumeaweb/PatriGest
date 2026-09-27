import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { InfrastructureDashboard } from "@/domains/administration/components/infrastructure-dashboard";
import { getInfrastructureDashboard } from "@/domains/administration/services/infrastructure-service";

export const dynamic = "force-dynamic";

export default async function AdministrationInfrastructurePage() {
  const results = await getInfrastructureDashboard();
  return <PrivateShell current="administration-infrastructure">
    <AppBreadcrumb items={[{ label: "Administration", href: "/administration" }, { label: "Infrastructure" }]} />
    <header><p className="text-xs font-bold uppercase tracking-widest text-[#2563EB]">Administration</p><h1>Infrastructure</h1><p className="mt-1 text-sm text-[#64748B]">Supervisez les services externes indispensables à PatriGest.</p></header>
    <InfrastructureDashboard results={results} />
  </PrivateShell>;
}
