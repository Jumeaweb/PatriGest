-- Financial mutations must go through the audited, idempotent RPCs.
-- Keep SELECT available through the existing RLS policies.
revoke insert, update, delete on table public.transactions
from public, anon, authenticated, service_role;
