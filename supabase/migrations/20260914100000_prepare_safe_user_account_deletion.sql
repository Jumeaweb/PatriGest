-- SEC-02B1: prepare referential cleanup for a future controlled user deletion.

create or replace function public.list_current_user_owned_storage_objects()
returns table (
  bucket_id text,
  name text,
  metadata jsonb,
  user_metadata jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select object.bucket_id, object.name, object.metadata, object.user_metadata
  from storage.objects object
  where (select auth.uid()) is not null
    and object.bucket_id in ('transaction-proofs', 'bank-statements', 'management-reports')
    and (
      object.owner_id = (select auth.uid())::text
      or object.owner = (select auth.uid())
    )
  order by object.bucket_id, object.name;
$$;

revoke all on function public.list_current_user_owned_storage_objects() from public;
revoke all on function public.list_current_user_owned_storage_objects() from anon;
grant execute on function public.list_current_user_owned_storage_objects() to authenticated;

comment on function public.list_current_user_owned_storage_objects() is
  'Énumère les seules métadonnées Storage PatriGest appartenant à la session courante en préparation de SEC-02B2.';

create or replace function public.is_referential_transaction_category_cleanup(
  previous_row public.transactions,
  next_row public.transactions
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select pg_trigger_depth() > 1
    and previous_row.category_id is not null
    and next_row.category_id is null
    and not exists (
      select 1
      from public.categories category
      where category.id = previous_row.category_id
    )
    and (
      to_jsonb(next_row) - 'category_id' - 'updated_at'
      = to_jsonb(previous_row) - 'category_id' - 'updated_at'
    );
$$;

revoke all on function public.is_referential_transaction_category_cleanup(public.transactions, public.transactions) from public;
revoke all on function public.is_referential_transaction_category_cleanup(public.transactions, public.transactions) from anon;
revoke all on function public.is_referential_transaction_category_cleanup(public.transactions, public.transactions) from authenticated;

create or replace function public.normalize_transaction_classification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  resolved_official_category_id uuid;
begin
  if tg_op = 'UPDATE'
     and public.is_referential_transaction_category_cleanup(old, new) then
    return new;
  end if;

  new.classification_precision := nullif(btrim(new.classification_precision), '');

  if new.transaction_type in ('transfer_in', 'transfer_out') then
    return new;
  end if;

  if new.accounting_nature is null then
    new.accounting_nature := 'ordinary';
  end if;

  if new.accounting_nature <> 'ordinary' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.official_category_id is not null or new.category_id is null then
      return new;
    end if;
  elsif new.category_id is distinct from old.category_id then
    if new.official_category_id is distinct from old.official_category_id then
      return new;
    end if;

    new.classification_precision := null;

    if new.category_id is null then
      new.official_category_id := null;
      return new;
    end if;
  elsif new.official_category_id is not null or new.category_id is null then
    return new;
  end if;

  select case
    when category.is_system
      and category.official_code is not null
      and category.official_category_id is null
      then category.id
    when not category.is_system then category.official_category_id
    else null
  end
  into resolved_official_category_id
  from public.categories category
  where category.id = new.category_id;

  new.official_category_id := resolved_official_category_id;
  return new;
end;
$$;

create or replace function public.prevent_closed_period_transaction_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  old_person_id uuid;
  new_person_id uuid;
begin
  if tg_op = 'UPDATE'
     and public.is_referential_transaction_category_cleanup(old, new) then
    return new;
  end if;

  if tg_op in ('UPDATE', 'DELETE') then
    select protected_person_id into old_person_id
    from public.financial_accounts where id = old.financial_account_id;

    if exists (
      select 1 from public.management_periods
      where protected_person_id = old_person_id and status = 'closed'
        and old.transaction_date between start_date and end_date
    ) then
      raise exception 'Cette opération appartient à un exercice clôturé.';
    end if;
  end if;

  if tg_op in ('INSERT', 'UPDATE') then
    select protected_person_id into new_person_id
    from public.financial_accounts where id = new.financial_account_id;

    if tg_op = 'UPDATE' and old_person_id <> new_person_id then
      raise exception 'Une opération ne peut pas être déplacée vers un autre dossier.';
    end if;

    if exists (
      select 1 from public.management_periods
      where protected_person_id = new_person_id and status = 'closed'
        and new.transaction_date between start_date and end_date
    ) then
      raise exception 'Cette date appartient à un exercice clôturé.';
    end if;
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create or replace function public.set_transaction_updated_at()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if public.is_referential_transaction_category_cleanup(old, new) then
    new.updated_at := old.updated_at;
  else
    new.updated_at := now();
  end if;
  return new;
end;
$$;

drop trigger transactions_set_updated_at on public.transactions;
create trigger transactions_set_updated_at
before update on public.transactions
for each row execute function public.set_transaction_updated_at();

revoke all on function public.normalize_transaction_classification() from public;
revoke all on function public.prevent_closed_period_transaction_change() from public;
revoke all on function public.set_transaction_updated_at() from public;

alter table public.transactions
  drop constraint transactions_category_id_fkey;

alter table public.transactions
  add constraint transactions_category_id_fkey
  foreign key (category_id)
  references public.categories(id)
  on delete set null;

create or replace function public.protect_transaction_document_identity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if pg_trigger_depth() > 1
     and old.created_by is not null
     and new.created_by is null
     and (
       to_jsonb(new) - 'created_by' - 'updated_at'
       = to_jsonb(old) - 'created_by' - 'updated_at'
     ) then
    if not exists (select 1 from auth.users where id = old.created_by) then
      new.updated_at := old.updated_at;
      return new;
    end if;
  end if;

  if new.id is distinct from old.id
     or new.transaction_id is distinct from old.transaction_id
     or new.storage_path is distinct from old.storage_path
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at then
    raise exception 'Le rattachement du justificatif ne peut pas être modifié.';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.protect_bank_statement_identity()
returns trigger language plpgsql set search_path = '' as $$
begin
  if pg_trigger_depth() > 1
     and old.created_by is not null
     and new.created_by is null
     and (
       to_jsonb(new) - 'created_by' - 'updated_at'
       = to_jsonb(old) - 'created_by' - 'updated_at'
     ) then
    if not exists (select 1 from auth.users where id = old.created_by) then
      new.updated_at := old.updated_at;
      return new;
    end if;
  end if;

  if new.id is distinct from old.id
     or new.financial_account_id is distinct from old.financial_account_id
     or new.storage_path is distinct from old.storage_path
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at then
    raise exception 'Le rattachement du relevé ne peut pas être modifié.';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.protect_management_report_identity()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE'
     and pg_trigger_depth() > 1
     and old.created_by is not null
     and new.created_by is null
     and (
       to_jsonb(new) - 'created_by' - 'updated_at'
       = to_jsonb(old) - 'created_by' - 'updated_at'
     ) then
    if not exists (select 1 from auth.users where id = old.created_by) then
      new.updated_at := old.updated_at;
      return new;
    end if;
  end if;

  if tg_op = 'INSERT' and (
    new.status::text in ('transmitted', 'approved', 'difficulty')
    or new.transmitted_at is not null or new.approved_at is not null
    or new.difficulty_reported_at is not null
  ) then
    raise exception 'Ce statut doit utiliser le flux contrôlé.';
  end if;
  if tg_op = 'UPDATE' and old.status::text in ('approved', 'difficulty') then
    raise exception 'Ce compte de gestion est définitivement figé.';
  end if;
  if tg_op = 'UPDATE' and old.status::text = 'transmitted' and not (
    current_user = 'patrigest_management_report_transmission_executor'
    and (
      (new.status::text = 'approved' and new.approved_at is not null
       and new.difficulty_reported_at is not distinct from old.difficulty_reported_at)
      or
      (new.status::text = 'difficulty' and new.difficulty_reported_at is not null
       and new.approved_at is not distinct from old.approved_at)
    )
    and new.residence_changed is not distinct from old.residence_changed
    and new.representative_address_changed is not distinct from old.representative_address_changed
    and new.real_estate_confirmed is not distinct from old.real_estate_confirmed
    and new.financial_investments_confirmed is not distinct from old.financial_investments_confirmed
    and new.observations is not distinct from old.observations
    and new.signature_place is not distinct from old.signature_place
    and new.generated_at is not distinct from old.generated_at
    and new.finalized_at is not distinct from old.finalized_at
    and new.transmitted_at is not distinct from old.transmitted_at
  ) then
    raise exception 'Un compte de gestion transmis est figé.';
  end if;
  if tg_op = 'UPDATE' and old.status::text = 'finalized' and not (
    current_user = 'patrigest_management_report_transmission_executor'
    and new.status::text = 'transmitted'
    and new.transmitted_at is not null
    and new.residence_changed is not distinct from old.residence_changed
    and new.representative_address_changed is not distinct from old.representative_address_changed
    and new.real_estate_confirmed is not distinct from old.real_estate_confirmed
    and new.financial_investments_confirmed is not distinct from old.financial_investments_confirmed
    and new.observations is not distinct from old.observations
    and new.signature_place is not distinct from old.signature_place
    and new.generated_at is not distinct from old.generated_at
    and new.finalized_at is not distinct from old.finalized_at
    and new.approved_at is not distinct from old.approved_at
    and new.difficulty_reported_at is not distinct from old.difficulty_reported_at
  ) then
    raise exception 'Un compte de gestion finalisé est figé.';
  end if;
  if tg_op = 'UPDATE' and old.status::text = 'generated' and (
    new.residence_changed is distinct from old.residence_changed
    or new.representative_address_changed is distinct from old.representative_address_changed
    or new.real_estate_confirmed is distinct from old.real_estate_confirmed
    or new.financial_investments_confirmed is distinct from old.financial_investments_confirmed
    or new.observations is distinct from old.observations
    or new.signature_place is distinct from old.signature_place
  ) then
    raise exception 'Reprenez la préparation avant de modifier le compte de gestion.';
  end if;
  if tg_op = 'UPDATE' and current_user = 'authenticated' and (
    new.generated_at is distinct from old.generated_at
    or new.finalized_at is distinct from old.finalized_at
    or new.transmitted_at is distinct from old.transmitted_at
    or new.approved_at is distinct from old.approved_at
    or new.difficulty_reported_at is distinct from old.difficulty_reported_at
  ) then
    raise exception 'Les jalons documentaires sont gérés par le flux contrôlé.';
  end if;
  if tg_op = 'UPDATE' and current_user = 'authenticated' and not (
    (old.status::text = 'draft' and new.status::text = 'ready')
    or (old.status::text = 'ready' and new.status::text = 'draft')
    or old.status = new.status
  ) then
    raise exception 'Cette transition doit utiliser le flux documentaire contrôlé.';
  end if;
  if new.status::text = 'generated' then
    if new.generated_at is null or new.finalized_at is not null or new.transmitted_at is not null
       or new.approved_at is not null or new.difficulty_reported_at is not null then
      raise exception 'Les dates du projet généré sont invalides.';
    end if;
  elsif new.status::text = 'finalized' then
    if new.generated_at is null or new.finalized_at is null or new.transmitted_at is not null
       or new.approved_at is not null or new.difficulty_reported_at is not null then
      raise exception 'Les dates de finalisation sont invalides.';
    end if;
  elsif new.status::text = 'transmitted' then
    if new.generated_at is null or new.finalized_at is null or new.transmitted_at is null
       or new.approved_at is not null or new.difficulty_reported_at is not null then
      raise exception 'Les dates de transmission sont invalides.';
    end if;
  elsif new.status::text = 'approved' then
    if new.generated_at is null or new.finalized_at is null or new.transmitted_at is null
       or new.approved_at is null or new.difficulty_reported_at is not null then
      raise exception 'Les dates d''approbation sont invalides.';
    end if;
  elsif new.status::text = 'difficulty' then
    if new.generated_at is null or new.finalized_at is null or new.transmitted_at is null
       or new.difficulty_reported_at is null or new.approved_at is not null then
      raise exception 'Les dates du signalement sont invalides.';
    end if;
  elsif new.generated_at is not null or new.finalized_at is not null
     or new.transmitted_at is not null or new.approved_at is not null
     or new.difficulty_reported_at is not null then
    raise exception 'Les dates documentaires ne correspondent pas au statut.';
  end if;
  if tg_op = 'UPDATE' and (
    new.id is distinct from old.id or new.protected_person_id is distinct from old.protected_person_id
    or new.management_period_id is distinct from old.management_period_id
    or new.period_start is distinct from old.period_start or new.period_end is distinct from old.period_end
    or new.report_year is distinct from old.report_year or new.created_by is distinct from old.created_by
    or new.created_at is distinct from old.created_at
  ) then
    raise exception 'La période et le rattachement du compte de gestion ne peuvent pas être modifiés.';
  end if;
  if new.management_period_id is not null and not exists (
    select 1 from public.management_periods period
    where period.id = new.management_period_id
      and period.protected_person_id = new.protected_person_id
      and period.start_date = new.period_start
      and period.end_date = new.period_end
  ) then
    raise exception 'L''exercice ne correspond pas à la période du compte de gestion.';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.reject_management_report_document_update()
returns trigger language plpgsql set search_path = '' as $$
begin
  if pg_trigger_depth() > 1
     and old.generated_by is not null
     and new.generated_by is null
     and to_jsonb(new) - 'generated_by' = to_jsonb(old) - 'generated_by' then
    if not exists (select 1 from auth.users where id = old.generated_by) then
      return new;
    end if;
  end if;

  raise exception 'Un document de compte de gestion ne peut pas être modifié.';
end;
$$;

create or replace function public.protect_management_report_transmission_identity()
returns trigger language plpgsql set search_path = '' as $$
begin
  if pg_trigger_depth() > 1
     and old.declared_by is not null
     and new.declared_by is null
     and (
       to_jsonb(new) - 'declared_by' - 'updated_at'
       = to_jsonb(old) - 'declared_by' - 'updated_at'
     ) then
    if not exists (select 1 from auth.users where id = old.declared_by) then
      new.updated_at := old.updated_at;
      return new;
    end if;
  end if;

  if new.id is distinct from old.id
     or new.management_report_id is distinct from old.management_report_id
     or new.declared_by is distinct from old.declared_by
     or new.created_at is distinct from old.created_at then
    raise exception 'Le rattachement de la transmission ne peut pas être modifié.';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.protect_management_report_outcome_identity()
returns trigger language plpgsql set search_path = '' as $$
begin
  if pg_trigger_depth() > 1
     and old.declared_by is not null
     and new.declared_by is null
     and (
       to_jsonb(new) - 'declared_by' - 'updated_at'
       = to_jsonb(old) - 'declared_by' - 'updated_at'
     ) then
    if not exists (select 1 from auth.users where id = old.declared_by) then
      new.updated_at := old.updated_at;
      return new;
    end if;
  end if;

  if new.id is distinct from old.id
     or new.management_report_id is distinct from old.management_report_id
     or new.declared_by is distinct from old.declared_by
     or new.created_at is distinct from old.created_at then
    raise exception 'Le rattachement du retour ne peut pas être modifié.';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.protect_management_report_account_selection()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_report public.management_reports%rowtype;
  v_account public.financial_accounts%rowtype;
  v_report_id uuid;
begin
  if tg_op = 'UPDATE'
     and pg_trigger_depth() > 1
     and old.created_by is not null
     and new.created_by is null
     and (
       to_jsonb(new) - 'created_by' - 'updated_at'
       = to_jsonb(old) - 'created_by' - 'updated_at'
     ) then
    if not exists (select 1 from auth.users where id = old.created_by) then
      new.updated_at := old.updated_at;
      return new;
    end if;
  end if;

  if tg_op = 'DELETE' then
    v_report_id := old.management_report_id;
  else
    v_report_id := new.management_report_id;
  end if;

  select * into v_report
  from public.management_reports
  where id = v_report_id
  for update;

  if not found or v_report.status <> 'draft' then
    raise exception 'La sélection des comptes est modifiable uniquement pendant la préparation.';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  select * into v_account
  from public.financial_accounts
  where id = new.financial_account_id;

  if not found or v_account.protected_person_id <> v_report.protected_person_id then
    raise exception 'Le compte et le compte de gestion doivent appartenir au même dossier.';
  end if;

  if tg_op = 'UPDATE' and (
    new.id is distinct from old.id
    or new.management_report_id is distinct from old.management_report_id
    or new.financial_account_id is distinct from old.financial_account_id
    or new.created_by is distinct from old.created_by
    or new.created_at is distinct from old.created_at
  ) then
    raise exception 'Le rattachement de la sélection ne peut pas être modifié.';
  end if;

  new.reason := trim(new.reason);
  new.updated_at := now();
  return new;
end;
$$;

revoke all on function public.protect_transaction_document_identity() from public;
revoke all on function public.protect_bank_statement_identity() from public;
revoke all on function public.protect_management_report_identity() from public;
revoke all on function public.reject_management_report_document_update() from public;
revoke all on function public.protect_management_report_transmission_identity() from public;
revoke all on function public.protect_management_report_outcome_identity() from public;
revoke all on function public.protect_management_report_account_selection() from public;

alter table public.transaction_documents
  drop constraint transaction_documents_created_by_fkey,
  alter column created_by drop not null,
  add constraint transaction_documents_created_by_fkey
    foreign key (created_by) references auth.users(id) on delete set null;

alter table public.bank_statements
  drop constraint bank_statements_created_by_fkey,
  alter column created_by drop not null,
  add constraint bank_statements_created_by_fkey
    foreign key (created_by) references auth.users(id) on delete set null;

alter table public.management_reports
  drop constraint management_reports_created_by_fkey,
  alter column created_by drop not null,
  add constraint management_reports_created_by_fkey
    foreign key (created_by) references auth.users(id) on delete set null;

alter table public.management_report_documents
  drop constraint management_report_documents_generated_by_fkey,
  alter column generated_by drop not null,
  add constraint management_report_documents_generated_by_fkey
    foreign key (generated_by) references auth.users(id) on delete set null;

alter table public.management_report_transmissions
  drop constraint management_report_transmissions_declared_by_fkey,
  alter column declared_by drop not null,
  add constraint management_report_transmissions_declared_by_fkey
    foreign key (declared_by) references auth.users(id) on delete set null;

alter table public.management_report_approvals
  drop constraint management_report_approvals_declared_by_fkey,
  alter column declared_by drop not null,
  add constraint management_report_approvals_declared_by_fkey
    foreign key (declared_by) references auth.users(id) on delete set null;

alter table public.management_report_difficulties
  drop constraint management_report_difficulties_declared_by_fkey,
  alter column declared_by drop not null,
  add constraint management_report_difficulties_declared_by_fkey
    foreign key (declared_by) references auth.users(id) on delete set null;

alter table public.management_report_account_selections
  drop constraint management_report_account_selections_created_by_fkey,
  alter column created_by drop not null,
  add constraint management_report_account_selections_created_by_fkey
    foreign key (created_by) references auth.users(id) on delete set null;

alter table public.platform_administrators
  drop constraint platform_administrators_appointed_by_fkey,
  add constraint platform_administrators_appointed_by_fkey
    foreign key (appointed_by) references auth.users(id) on delete set null;
