import type { BankStatement } from "@/types/database";
import { getAuthenticatedUser } from "@/domains/protected-persons/services/authenticated-user";
import {
  BANK_STATEMENT_PAGE_SIZE,
  getBankStatementPageMetadata,
} from "./bank-statement-pagination";

export type BankStatementPage = ReturnType<typeof getBankStatementPageMetadata> & {
  items: BankStatement[];
};

export async function getBankStatements(accountId: string) {
  const { supabase } = await getAuthenticatedUser();
  const { data, error } = await supabase
    .from("bank_statements")
    .select("*")
    .eq("financial_account_id", accountId)
    .order("statement_end_date", { ascending: false })
    .order("created_at", { ascending: false });
  if (error) throw new Error("Impossible de charger les relevés.");
  return data;
}

export async function getBankStatementPage(
  accountId: string,
  requestedPage: number,
): Promise<BankStatementPage> {
  const { supabase } = await getAuthenticatedUser();
  const countResult = await supabase
    .from("bank_statements")
    .select("id", { count: "exact", head: true })
    .eq("financial_account_id", accountId);
  if (countResult.error) throw new Error("Impossible de charger les relevés.");

  const metadata = getBankStatementPageMetadata(countResult.count ?? 0, requestedPage);
  if (metadata.totalCount === 0) return { items: [], ...metadata };

  const offset = (metadata.page - 1) * BANK_STATEMENT_PAGE_SIZE;
  const pageResult = await supabase
    .from("bank_statements")
    .select("*")
    .eq("financial_account_id", accountId)
    .order("statement_end_date", { ascending: false })
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .range(offset, offset + BANK_STATEMENT_PAGE_SIZE - 1);
  if (pageResult.error) throw new Error("Impossible de charger les relevés.");

  return { items: pageResult.data ?? [], ...metadata };
}

export async function getBankStatement(accountId: string, statementId: string) {
  const { supabase } = await getAuthenticatedUser();
  const { data, error } = await supabase
    .from("bank_statements")
    .select("*")
    .eq("id", statementId)
    .eq("financial_account_id", accountId)
    .maybeSingle();
  if (error) throw new Error("Impossible de charger le relevé.");
  return data;
}

export async function getLatestBankStatementAtOrBefore(accountId: string, date: string) {
  const { supabase } = await getAuthenticatedUser();
  const { data, error } = await supabase
    .from("bank_statements")
    .select("*")
    .eq("financial_account_id", accountId)
    .lte("statement_end_date", date)
    .order("statement_end_date", { ascending: false })
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) throw new Error("Impossible de rechercher le dernier relevé.");
  return data;
}
