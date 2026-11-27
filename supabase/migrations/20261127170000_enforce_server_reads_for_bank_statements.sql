-- The application using staged bank writes must be available before this file.
create function public.can_upload_reserved_bank_statement_file(p_path text)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.can_upload_unreconciled_bank_statement_file(p_path) or exists (
    select 1 from public.bank_statement_document_corrections correction
    join public.bank_statements statement on statement.id = correction.bank_statement_id
    join public.financial_accounts account on account.id = statement.financial_account_id
    join public.protected_persons person on person.id = account.protected_person_id
    where correction.proposed_storage_path = p_path and correction.requested_by = auth.uid()
      and correction.state = 'reserved' and person.status = 'active' and person.archived_at is null
      and public.can_manage_protected_person(person.id)
  );
$$;
revoke all on function public.can_upload_reserved_bank_statement_file(text) from public, anon, authenticated, service_role;
grant execute on function public.can_upload_reserved_bank_statement_file(text) to authenticated;

create policy bank_statement_files_require_server_read on storage.objects
as restrictive for select to authenticated, anon using (bucket_id <> 'bank-statements');

create policy bank_statement_files_require_reservation on storage.objects
as restrictive for insert to authenticated with check (bucket_id <> 'bank-statements'
  or public.can_upload_reserved_bank_statement_file(name));

create policy bank_statement_files_no_direct_update on storage.objects
as restrictive for update to authenticated using (bucket_id <> 'bank-statements')
with check (bucket_id <> 'bank-statements');

create policy bank_statement_files_no_direct_delete on storage.objects
as restrictive for delete to authenticated using (bucket_id <> 'bank-statements');

create function public.guard_bank_statement_legacy_file_metadata()
returns trigger language plpgsql set search_path = '' as $$
begin
  if current_user = 'authenticated' and (
    (tg_op = 'INSERT' and (new.original_file_name is not null or new.mime_type is not null or new.file_size is not null))
    or (tg_op = 'UPDATE' and (new.original_file_name,new.mime_type,new.file_size)
      is distinct from (old.original_file_name,old.mime_type,old.file_size))
  ) then
    raise exception using errcode = '42501', message = 'Utilisez la publication versionnée pour modifier le PDF du relevé.';
  end if;
  return new;
end;
$$;

create trigger bank_statement_guard_legacy_file_metadata before insert or update on public.bank_statements
for each row execute function public.guard_bank_statement_legacy_file_metadata();
revoke all on function public.guard_bank_statement_legacy_file_metadata() from public, anon, authenticated, service_role;
