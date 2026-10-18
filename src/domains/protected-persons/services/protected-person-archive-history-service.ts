import "server-only";

import type { ProtectedPersonArchiveChange } from "@/types/database";
import { getAuthenticatedUser } from "./authenticated-user";

export async function getProtectedPersonArchiveChanges(
  protectedPersonId: string,
): Promise<ProtectedPersonArchiveChange[]> {
  const { supabase } = await getAuthenticatedUser();
  const { data, error } = await supabase
    .from("protected_person_archive_changes")
    .select("*")
    .eq("protected_person_id", protectedPersonId)
    .order("changed_at", { ascending: false })
    .order("id", { ascending: false });

  if (error) throw new Error("Impossible de charger l’historique d’archivage du dossier.");
  return data;
}
