import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { AdministrationDashboard } from "@/domains/administration/components/administration-dashboard";
export const dynamic = "force-dynamic";
export default function AdministrationPage() { return <PrivateShell current="administration"><AppBreadcrumb items={[{ label: "Administration" }]} /><AdministrationDashboard /></PrivateShell>; }
