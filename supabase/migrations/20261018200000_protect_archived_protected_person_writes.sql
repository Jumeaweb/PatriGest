-- PAT-DOSSIERS-ARCHIVAGE-01B-2D-1
-- Interdit toute écriture métier rattachée à un dossier archivé.
-- Les accès, invitations et objets Storage sont volontairement hors périmètre.

create function public.assert_protected_person_active_for_write(
  p_protected_person_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  dossier_status text;
begin
  if p_protected_person_id is null then
    return;
  end if;

  -- FOR KEY SHARE sérialise l’écriture enfant avec archive/restore et delete,
  -- sans imposer de verrou plus fort entre écritures métier concurrentes.
  select person.status
  into dossier_status
  from public.protected_persons person
  where person.id = p_protected_person_id
  for key share;

  if not found then
    return;
  end if;

  if dossier_status = 'archived' then
    raise exception using
      errcode = 'P4R01',
      message = 'Ce dossier est archivé. Restaurez-le avant toute modification.';
  end if;
end;
$$;

create function public.resolve_business_row_protected_person_id(
  p_table_name text,
  p_row jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  protected_person_id uuid;
begin
  case p_table_name
    when 'protection_measures',
         'management_periods',
         'financial_accounts',
         'transfers',
         'proof_reference_assignments',
         'real_estate_properties',
         'property_events',
         'property_event_changes',
         'property_archive_changes',
         'property_sale_price_corrections',
         'patrimony_absence_confirmations',
         'debts',
         'management_reports'
    then
      protected_person_id := (p_row ->> 'protected_person_id')::uuid;

    when 'account_valuations', 'bank_statements'
    then
      select account.protected_person_id
      into protected_person_id
      from public.financial_accounts account
      where account.id = (p_row ->> 'financial_account_id')::uuid;

    when 'transactions'
    then
      select account.protected_person_id
      into protected_person_id
      from public.financial_accounts account
      where account.id = (p_row ->> 'financial_account_id')::uuid;

    when 'transaction_documents'
    then
      select account.protected_person_id
      into protected_person_id
      from public.transactions transaction_row
      join public.financial_accounts account
        on account.id = transaction_row.financial_account_id
      where transaction_row.id = (p_row ->> 'transaction_id')::uuid;

    when 'debt_balances'
    then
      select debt.protected_person_id
      into protected_person_id
      from public.debts debt
      where debt.id = (p_row ->> 'debt_id')::uuid;

    when 'bank_reconciliations'
    then
      select account.protected_person_id
      into protected_person_id
      from public.bank_statements statement
      join public.financial_accounts account
        on account.id = statement.financial_account_id
      where statement.id = (p_row ->> 'bank_statement_id')::uuid;

    when 'bank_reconciliation_outstanding_transactions'
    then
      select account.protected_person_id
      into protected_person_id
      from public.bank_reconciliations reconciliation
      join public.bank_statements statement
        on statement.id = reconciliation.bank_statement_id
      join public.financial_accounts account
        on account.id = statement.financial_account_id
      where reconciliation.id = (p_row ->> 'bank_reconciliation_id')::uuid;

    when 'management_report_documents',
         'management_report_account_selections',
         'management_report_transmissions',
         'management_report_approvals',
         'management_report_difficulties'
    then
      select report.protected_person_id
      into protected_person_id
      from public.management_reports report
      where report.id = (p_row ->> 'management_report_id')::uuid;

    else
      raise exception 'Table métier non prise en charge : %', p_table_name;
  end case;

  return protected_person_id;
end;
$$;

create function public.enforce_active_protected_person_business_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  old_protected_person_id uuid;
  new_protected_person_id uuid;
begin
  if tg_op in ('UPDATE', 'DELETE') then
    old_protected_person_id := public.resolve_business_row_protected_person_id(
      tg_table_name,
      to_jsonb(old)
    );
    perform public.assert_protected_person_active_for_write(old_protected_person_id);
  end if;

  if tg_op in ('INSERT', 'UPDATE') then
    new_protected_person_id := public.resolve_business_row_protected_person_id(
      tg_table_name,
      to_jsonb(new)
    );
    if new_protected_person_id is distinct from old_protected_person_id then
      perform public.assert_protected_person_active_for_write(new_protected_person_id);
    end if;
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create function public.enforce_active_protected_person_row_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  lifecycle_changed boolean;
  archive_revision_only_changed boolean;
  old_business_values jsonb;
  new_business_values jsonb;
begin
  if tg_op = 'DELETE' then
    -- La suppression physique reste exclusivement régie par la RPC contrôlée.
    return old;
  end if;

  if tg_op = 'INSERT' then
    return new;
  end if;

  -- Conserve l’erreur dédiée du trigger de cycle de vie lorsqu’un appelant
  -- tente uniquement de forcer la révision gérée par PostgreSQL.
  archive_revision_only_changed :=
    new.archive_revision is distinct from old.archive_revision
    and (to_jsonb(new) - array['archive_revision', 'updated_at'])
      is not distinct from
        (to_jsonb(old) - array['archive_revision', 'updated_at']);

  if archive_revision_only_changed then
    return new;
  end if;

  lifecycle_changed := (new.status, new.archived_at)
    is distinct from (old.status, old.archived_at);

  if lifecycle_changed then
    old_business_values := to_jsonb(old)
      - array['status', 'archived_at', 'archive_revision', 'updated_at'];
    new_business_values := to_jsonb(new)
      - array['status', 'archived_at', 'archive_revision', 'updated_at'];

    if old_business_values is distinct from new_business_values then
      raise exception using
        errcode = 'P4R01',
        message = 'Ce dossier est archivé. Restaurez-le avant toute modification.';
    end if;

    -- Les triggers du lot 2A continuent d’autoriser uniquement les RPC dédiées.
    return new;
  end if;

  if old.status = 'archived' then
    raise exception using
      errcode = 'P4R01',
      message = 'Ce dossier est archivé. Restaurez-le avant toute modification.';
  end if;

  return new;
end;
$$;

create trigger protected_persons_00_require_active_for_business_write
before insert or update or delete on public.protected_persons
for each row execute function public.enforce_active_protected_person_row_write();

do $$
declare
  protected_table text;
begin
  foreach protected_table in array array[
    'protection_measures',
    'management_periods',
    'financial_accounts',
    'account_valuations',
    'transfers',
    'transactions',
    'proof_reference_assignments',
    'transaction_documents',
    'real_estate_properties',
    'property_events',
    'property_event_changes',
    'property_archive_changes',
    'property_sale_price_corrections',
    'patrimony_absence_confirmations',
    'debts',
    'debt_balances',
    'bank_statements',
    'bank_reconciliations',
    'bank_reconciliation_outstanding_transactions',
    'management_reports',
    'management_report_documents',
    'management_report_account_selections',
    'management_report_transmissions',
    'management_report_approvals',
    'management_report_difficulties'
  ]
  loop
    execute format(
      'create trigger %I before insert or update or delete on public.%I '
      'for each row execute function public.enforce_active_protected_person_business_write()',
      protected_table || '_00_require_active_dossier',
      protected_table
    );
  end loop;
end;
$$;

revoke all on function public.assert_protected_person_active_for_write(uuid)
from public, anon, authenticated, service_role;
revoke all on function public.resolve_business_row_protected_person_id(text,jsonb)
from public, anon, authenticated, service_role;
revoke all on function public.enforce_active_protected_person_business_write()
from public, anon, authenticated, service_role;
revoke all on function public.enforce_active_protected_person_row_write()
from public, anon, authenticated, service_role;

comment on function public.assert_protected_person_active_for_write(uuid) is
  'Verrouille le dossier et refuse avec P4R01 toute mutation métier lorsqu’il est archivé.';
comment on function public.enforce_active_protected_person_business_write() is
  'Garde transactionnelle commune des tables métier rattachées à un dossier.';
