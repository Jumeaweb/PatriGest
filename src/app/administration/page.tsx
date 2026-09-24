import { PrivateShell } from "@/components/layout/private-shell";
import { AdministrationDashboard } from "@/domains/administration/components/administration-dashboard";
export const dynamic = "force-dynamic";
export default function AdministrationPage() { return <PrivateShell current="administration"><AdministrationDashboard /></PrivateShell>; }
