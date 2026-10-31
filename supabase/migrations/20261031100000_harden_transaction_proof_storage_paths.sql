-- PAT-PRODUCTION-07H
-- Rend les quatre politiques Storage des justificatifs strictes sur le chemin
-- canonique, sans modifier les droits métier ni activer la garde expérimentale.
-- Le résolveur canonique existant reste interne : l'expression régulière est
-- volontairement intégrée aux politiques pour ne modifier aucun droit EXECUTE.

drop policy if exists "transaction_proofs_select_accessible" on storage.objects;
drop policy if exists "transaction_proofs_insert_manage" on storage.objects;
drop policy if exists "transaction_proofs_update_manage" on storage.objects;
drop policy if exists "transaction_proofs_delete_manage" on storage.objects;

create policy "transaction_proofs_select_accessible" on storage.objects
for select to authenticated using (
  bucket_id = 'transaction-proofs'
  and exists (
    select 1
    from pg_catalog.regexp_match(
      name,
      '^protected-persons/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/transactions/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/proof$'
    ) path_match
    join public.transactions transaction
      on transaction.id = path_match[2]::uuid
    join public.financial_accounts account
      on account.id = transaction.financial_account_id
    where account.protected_person_id = path_match[1]::uuid
      and public.can_read_protected_person(path_match[1]::uuid)
  )
);

create policy "transaction_proofs_insert_manage" on storage.objects
for insert to authenticated with check (
  bucket_id = 'transaction-proofs'
  and exists (
    select 1
    from pg_catalog.regexp_match(
      name,
      '^protected-persons/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/transactions/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/proof$'
    ) path_match
    join public.transactions transaction
      on transaction.id = path_match[2]::uuid
    join public.financial_accounts account
      on account.id = transaction.financial_account_id
    where transaction.transaction_type = 'expense'
      and account.protected_person_id = path_match[1]::uuid
      and public.can_manage_protected_person(path_match[1]::uuid)
  )
);

create policy "transaction_proofs_update_manage" on storage.objects
for update to authenticated using (
  bucket_id = 'transaction-proofs'
  and exists (
    select 1
    from pg_catalog.regexp_match(
      name,
      '^protected-persons/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/transactions/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/proof$'
    ) path_match
    join public.transactions transaction
      on transaction.id = path_match[2]::uuid
    join public.financial_accounts account
      on account.id = transaction.financial_account_id
    where transaction.transaction_type = 'expense'
      and account.protected_person_id = path_match[1]::uuid
      and public.can_manage_protected_person(path_match[1]::uuid)
  )
) with check (
  bucket_id = 'transaction-proofs'
  and exists (
    select 1
    from pg_catalog.regexp_match(
      name,
      '^protected-persons/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/transactions/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/proof$'
    ) path_match
    join public.transactions transaction
      on transaction.id = path_match[2]::uuid
    join public.financial_accounts account
      on account.id = transaction.financial_account_id
    where transaction.transaction_type = 'expense'
      and account.protected_person_id = path_match[1]::uuid
      and public.can_manage_protected_person(path_match[1]::uuid)
  )
);

create policy "transaction_proofs_delete_manage" on storage.objects
for delete to authenticated using (
  bucket_id = 'transaction-proofs'
  and exists (
    select 1
    from pg_catalog.regexp_match(
      name,
      '^protected-persons/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/transactions/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/proof$'
    ) path_match
    join public.transactions transaction
      on transaction.id = path_match[2]::uuid
    join public.financial_accounts account
      on account.id = transaction.financial_account_id
    where transaction.transaction_type = 'expense'
      and transaction.transfer_id is null
      and account.protected_person_id = path_match[1]::uuid
      and public.can_manage_protected_person(path_match[1]::uuid)
  )
);
