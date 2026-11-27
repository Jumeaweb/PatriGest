-- PAT-STRIPE-02D. Apply only after the compatible application is available.
-- The bank-statement bucket retains its existing rules until legacy writes
-- can preserve the original through the SQL transition.
drop policy if exists crg_and_proofs_require_server_read on storage.objects;
create policy crg_and_proofs_require_server_read
on storage.objects as restrictive for select to authenticated, anon
using (bucket_id not in ('management-reports', 'transaction-proofs'));

drop policy if exists transaction_proofs_require_reserved_insert on storage.objects;
create policy transaction_proofs_require_reserved_insert
on storage.objects as restrictive for insert to authenticated
with check (bucket_id <> 'transaction-proofs'
  or public.can_upload_reserved_transaction_proof_version(bucket_id, name));
