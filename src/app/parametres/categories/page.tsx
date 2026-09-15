import type { Metadata } from "next";
import { PrivateShell } from "@/components/layout/private-shell";
import { AppBreadcrumb } from "@/components/ui/app-breadcrumb";
import { CategoryManager } from "@/domains/categories/components/category-manager";
import { getCategories } from "@/domains/categories/services/category-service";
export const metadata: Metadata = { title: "Catégories" };
export const dynamic = "force-dynamic";
export default async function CategoriesPage() { const categories = await getCategories(); return <PrivateShell current="settings"><AppBreadcrumb items={[{ label: "Tableau de bord", href: "/tableau-de-bord" }, { label: "Catégories" }]} /><div><h1 className="mt-1 text-2xl font-bold sm:text-[28px]">Catégories</h1><p className="mt-1 text-sm text-[#64748B]">Classez vos recettes et dépenses avec les catégories PatriGest ou les vôtres.</p></div><CategoryManager categories={categories} /></PrivateShell>; }
