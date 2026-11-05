-- PAT-TRANSACTIONS-01E
-- Ferme les anciens chemins de mutation après raccordement aux RPC auditées.

revoke insert, update, delete on table public.transactions from authenticated;

revoke all on function public.create_internal_transfer(uuid, uuid, uuid, date, numeric, text, text)
from public, anon, authenticated, service_role;

revoke all on function public.delete_internal_transfer(uuid)
from public, anon, authenticated, service_role;

revoke all on function public.delete_transaction_with_document(uuid)
from public, anon, authenticated, service_role;

