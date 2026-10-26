-- PAT-DOSSIERS-ARCHIVAGE-01B-2D-3C-3H-2C5B
-- Inventaire historique strictement en lecture seule et garde préalable des
-- décisions de réparation connues comme destructives. Aucun trigger n'est
-- installé sur storage.objects et aucun octet Storage n'est lu ou modifié.

-- L'inventaire rapproche les objets avec l'historique durable par leur
-- identité canonique. Cet index évite un parcours répété de toutes les cibles
-- pour chaque référence métier inspectée.
create index document_operation_targets_inventory_object_idx
on public.document_operation_targets(bucket_id, object_path);

create function public.get_administrative_document_inventory(
  p_limit integer default 50,
  p_after_key text default null,
  p_document_category text default null,
  p_anomaly_type text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  result_items jsonb;
  next_cursor text;
  has_more boolean;
begin
  if caller_id is null or not public.is_platform_admin() then
    raise exception using errcode = 'P4I01',
      message = 'Inventaire documentaire non autorisé.';
  end if;
  if p_limit not between 1 and 100 then
    raise exception using errcode = 'P4I02',
      message = 'Limite d’inventaire invalide.';
  end if;
  if p_after_key is not null and (
    char_length(p_after_key) not between 1 and 200
    or p_after_key !~ '^[a-z0-9_:-]+$'
  ) then
    raise exception using errcode = 'P4I02',
      message = 'Curseur d’inventaire invalide.';
  end if;
  if p_document_category is not null and p_document_category not in (
    'transaction_proof', 'bank_statement', 'management_report', 'backup',
    'document_operation', 'account_neutralization', 'repair'
  ) then
    raise exception using errcode = 'P4I02',
      message = 'Catégorie d’inventaire invalide.';
  end if;
  if p_anomaly_type is not null and p_anomaly_type not in (
    'business_reference_without_catalog_object',
    'catalog_object_without_business_reference',
    'unresolved_catalog_path',
    'historical_noncanonical_path', 'business_attachment_mismatch',
    'storage_identity_incomplete', 'storage_owner_unrecorded',
    'no_durable_operation_history', 'backup_catalog_object_missing',
    'backup_physical_verification_required', 'terminal_operation_residual',
    'non_terminal_operation', 'attention_required_operation',
    'incomplete_account_neutralization', 'expired_repair_authorization',
    'repair_renewals_exhausted'
  ) then
    raise exception using errcode = 'P4I02',
      message = 'Filtre d’inventaire invalide.';
  end if;

  with business_documents as materialized (
    select 'transaction_proof'::text as document_category,
      'transaction-proofs'::text as bucket_id, document.id as reference_id,
      account.protected_person_id, 'transaction'::text as business_entity_type,
      document.transaction_id as business_entity_id, document.storage_path,
      document.created_at
    from public.transaction_documents document
    join public.transactions transaction on transaction.id = document.transaction_id
    join public.financial_accounts account on account.id = transaction.financial_account_id
    union all
    select 'bank_statement', 'bank-statements', statement.id,
      account.protected_person_id, 'bank_statement', statement.id,
      statement.storage_path, statement.created_at
    from public.bank_statements statement
    join public.financial_accounts account on account.id = statement.financial_account_id
    union all
    select 'management_report', 'management-reports', document.id,
      report.protected_person_id, 'management_report', report.id,
      document.storage_path, document.created_at
    from public.management_report_documents document
    join public.management_reports report on report.id = document.management_report_id
  ),
  resolved_business as materialized (
    select document.*, resolution.is_canonical,
      resolution.protected_person_id as path_protected_person_id,
      resolution.business_entity_type as path_business_entity_type,
      resolution.business_entity_id as path_business_entity_id
    from business_documents document
    cross join lateral public.resolve_canonical_document_storage_path(
      document.bucket_id, document.storage_path
    ) resolution
  ),
  inventory_candidates as (
    select document.document_category || ':business_reference_without_catalog_object:' || document.reference_id as inventory_key,
      document.document_category, 'business_reference_without_catalog_object'::text as anomaly_type,
      'sql_fact'::text as finding_status, document.protected_person_id,
      document.business_entity_type, document.business_entity_id,
      null::uuid as operation_id, false as catalog_object_present,
      true as physical_verification_required, true as action_blocked,
      false as storage_guard_required, 'CATALOG_OBJECT_ABSENT'::text as detail_code,
      document.created_at as source_created_at
    from resolved_business document
    left join storage.objects object
      on object.bucket_id = document.bucket_id and object.name = document.storage_path
    where object.id is null

    union all
    select document.document_category || ':historical_noncanonical_path:' || document.reference_id,
      document.document_category, 'historical_noncanonical_path',
      'historical_legitimate', document.protected_person_id,
      document.business_entity_type, document.business_entity_id, null::uuid,
      object.id is not null, true, false, false, 'PATH_REVIEW_REQUIRED',
      document.created_at
    from resolved_business document
    left join storage.objects object
      on object.bucket_id = document.bucket_id and object.name = document.storage_path
    where not document.is_canonical

    union all
    select document.document_category || ':business_attachment_mismatch:' || document.reference_id,
      document.document_category, 'business_attachment_mismatch',
      'sql_fact', document.protected_person_id,
      document.business_entity_type, document.business_entity_id, null::uuid,
      object.id is not null, true, true, false, 'CANONICAL_SCOPE_DIVERGED',
      document.created_at
    from resolved_business document
    left join storage.objects object
      on object.bucket_id = document.bucket_id and object.name = document.storage_path
    where document.is_canonical and (
      document.path_protected_person_id is distinct from document.protected_person_id
      or document.path_business_entity_type is distinct from document.business_entity_type
      or document.path_business_entity_id is distinct from document.business_entity_id
    )

    union all
    select case object.bucket_id
        when 'transaction-proofs' then 'transaction_proof'
        when 'bank-statements' then 'bank_statement'
        else 'management_report'
      end || ':catalog_object_without_business_reference:' || object.id,
      case object.bucket_id
        when 'transaction-proofs' then 'transaction_proof'
        when 'bank-statements' then 'bank_statement'
        else 'management_report'
      end,
      'catalog_object_without_business_reference', 'possible_anomaly',
      resolution.protected_person_id, resolution.business_entity_type,
      resolution.business_entity_id, null::uuid, true, true, true, true,
      'DIRECT_REFERENCE_ABSENT', object.created_at
    from storage.objects object
    cross join lateral public.resolve_canonical_document_storage_path(
      object.bucket_id, object.name
    ) resolution
    left join business_documents document
      on document.bucket_id = object.bucket_id and document.storage_path = object.name
    where object.bucket_id in ('transaction-proofs','bank-statements','management-reports')
      and document.reference_id is null
      and resolution.is_canonical

    union all
    select case object.bucket_id
        when 'transaction-proofs' then 'transaction_proof'
        when 'bank-statements' then 'bank_statement'
        else 'management_report'
      end || ':unresolved_catalog_path:' || object.id,
      case object.bucket_id
        when 'transaction-proofs' then 'transaction_proof'
        when 'bank-statements' then 'bank_statement'
        else 'management_report'
      end,
      'unresolved_catalog_path', 'possible_anomaly',
      null::uuid, null::text, null::uuid, null::uuid, true, true, true, true,
      'CATALOG_PATH_UNRESOLVED', object.created_at
    from storage.objects object
    cross join lateral public.resolve_canonical_document_storage_path(
      object.bucket_id, object.name
    ) resolution
    left join business_documents document
      on document.bucket_id = object.bucket_id and document.storage_path = object.name
    where object.bucket_id in ('transaction-proofs','bank-statements','management-reports')
      and document.reference_id is null
      and not resolution.is_canonical

    union all
    select case object.bucket_id
        when 'transaction-proofs' then 'transaction_proof'
        when 'bank-statements' then 'bank_statement'
        else 'management_report'
      end || ':storage_identity_incomplete:' || object.id,
      case object.bucket_id
        when 'transaction-proofs' then 'transaction_proof'
        when 'bank-statements' then 'bank_statement'
        else 'management_report'
      end,
      'storage_identity_incomplete', 'sql_fact', resolution.protected_person_id,
      resolution.business_entity_type, resolution.business_entity_id, null::uuid,
      true, true, true, true, 'CATALOG_IDENTITY_INCOMPLETE', object.created_at
    from storage.objects object
    cross join lateral public.resolve_canonical_document_storage_path(
      object.bucket_id, object.name
    ) resolution
    where object.bucket_id in ('transaction-proofs','bank-statements','management-reports')
      and (object.version is null or btrim(object.version) = '' or object.metadata is null)

    union all
    select case object.bucket_id
        when 'transaction-proofs' then 'transaction_proof'
        when 'bank-statements' then 'bank_statement'
        else 'management_report'
      end || ':storage_owner_unrecorded:' || object.id,
      case object.bucket_id
        when 'transaction-proofs' then 'transaction_proof'
        when 'bank-statements' then 'bank_statement'
        else 'management_report'
      end,
      'storage_owner_unrecorded', case when neutralization_state.owner_neutralized
        then 'historical_legitimate' else 'possible_anomaly' end,
      resolution.protected_person_id, resolution.business_entity_type,
      resolution.business_entity_id, null::uuid, true, true, false, false,
      case when neutralization_state.owner_neutralized
        then 'OWNER_NEUTRALIZED' else 'OWNER_NOT_RECORDED' end,
      object.created_at
    from storage.objects object
    cross join lateral public.resolve_canonical_document_storage_path(
      object.bucket_id, object.name
    ) resolution
    cross join lateral (
      select exists (
        select 1
        from public.document_operation_targets neutralized_target
        join public.account_storage_neutralizations neutralization
          on neutralization.operation_id = neutralized_target.operation_id
         and neutralization.target_id = neutralized_target.id
        where neutralized_target.bucket_id = object.bucket_id
          and neutralized_target.object_path = object.name
          and neutralization.phase = 'finalized'
      ) as owner_neutralized
    ) neutralization_state
    where object.bucket_id in ('transaction-proofs','bank-statements','management-reports')
      and object.owner_id is null

    union all
    select document.document_category || ':no_durable_operation_history:' || document.reference_id,
      document.document_category, 'no_durable_operation_history',
      'historical_legitimate', document.protected_person_id,
      document.business_entity_type, document.business_entity_id, null::uuid,
      object.id is not null, object.id is not null, false, false,
      'DURABLE_HISTORY_ABSENT', document.created_at
    from resolved_business document
    left join storage.objects object
      on object.bucket_id = document.bucket_id and object.name = document.storage_path
    where not exists (
      select 1 from public.document_operation_targets target
      where target.bucket_id = document.bucket_id
        and target.object_path = document.storage_path
    )

    union all
    select 'backup:backup_catalog_object_missing:' || backup.id,
      'backup', 'backup_catalog_object_missing', 'sql_fact',
      backup.protected_person_id, operation.business_entity_type,
      operation.business_entity_id, operation.id, false, true, true, false,
      'BACKUP_CATALOG_OBJECT_ABSENT', backup.created_at
    from public.document_operation_backups backup
    join public.document_operations operation on operation.id = backup.operation_id
    left join storage.objects object
      on object.bucket_id = 'document-operation-backups'
     and object.name = backup.recovery_object_path
    where backup.state <> 'deleted' and object.id is null

    union all
    select 'backup:backup_physical_verification_required:' || backup.id,
      'backup', 'backup_physical_verification_required', 'possible_anomaly',
      backup.protected_person_id, operation.business_entity_type,
      operation.business_entity_id, operation.id, true, true, false, false,
      'PHYSICAL_BYTES_NOT_CHECKED', backup.created_at
    from public.document_operation_backups backup
    join public.document_operations operation on operation.id = backup.operation_id
    join storage.objects object
      on object.bucket_id = 'document-operation-backups'
     and object.name = backup.recovery_object_path
    where backup.state <> 'deleted'

    union all
    select 'document_operation:terminal_operation_residual:' || operation.id,
      'document_operation', 'terminal_operation_residual', 'sql_fact',
      operation.protected_person_id, operation.business_entity_type,
      operation.business_entity_id, operation.id, null::boolean, true, true, true,
      'TERMINAL_OPERATION_HAS_RESIDUE', operation.created_at
    from public.document_operations operation
    where operation.state in ('completed','compensated','cancelled','administratively_resolved')
      and (
        exists (select 1 from public.document_object_locks object_lock where object_lock.operation_id = operation.id)
        or exists (
          select 1 from public.document_operation_backups backup
          left join storage.objects object
            on object.bucket_id = 'document-operation-backups'
           and object.name = backup.recovery_object_path
          where backup.operation_id = operation.id
            and (backup.state <> 'deleted' or object.id is not null)
        )
      )

    union all
    select 'document_operation:non_terminal_operation:' || operation.id,
      'document_operation', 'non_terminal_operation', 'sql_fact',
      operation.protected_person_id, operation.business_entity_type,
      operation.business_entity_id, operation.id, null::boolean, false, false, false,
      'OPERATION_IN_PROGRESS', operation.created_at
    from public.document_operations operation
    where operation.state in ('reserved','executing','compensating')

    union all
    select 'document_operation:attention_required_operation:' || operation.id,
      'document_operation', 'attention_required_operation', 'sql_fact',
      operation.protected_person_id, operation.business_entity_type,
      operation.business_entity_id, operation.id, null::boolean, true, true, false,
      'ADMINISTRATIVE_REVIEW_REQUIRED', operation.created_at
    from public.document_operations operation
    where operation.state = 'attention_required'

    union all
    select 'account_neutralization:incomplete_account_neutralization:' || neutralization.operation_id,
      'account_neutralization', 'incomplete_account_neutralization', 'sql_fact',
      operation.protected_person_id, operation.business_entity_type,
      operation.business_entity_id, operation.id, null::boolean, true, true, true,
      'ACCOUNT_NEUTRALIZATION_INCOMPLETE', operation.created_at
    from public.account_storage_neutralizations neutralization
    join public.document_operations operation on operation.id = neutralization.operation_id
    where neutralization.phase <> 'finalized'

    union all
    select 'repair:expired_repair_authorization:' || repair_authorization.id,
      'repair', 'expired_repair_authorization', 'sql_fact',
      operation.protected_person_id, operation.business_entity_type,
      operation.business_entity_id, operation.id, null::boolean, false, true, false,
      'REPAIR_AUTHORIZATION_EXPIRED', repair_authorization.issued_at
    from public.document_repair_authorizations repair_authorization
    join public.document_operations operation on operation.id = repair_authorization.operation_id
    where repair_authorization.state = 'active'
      and coalesce(repair_authorization.recovery_expires_at, repair_authorization.expires_at) <= statement_timestamp()

    union all
    select 'repair:repair_renewals_exhausted:' || repair_authorization.id,
      'repair', 'repair_renewals_exhausted', 'sql_fact',
      operation.protected_person_id, operation.business_entity_type,
      operation.business_entity_id, operation.id, null::boolean, false, true, false,
      'REPAIR_RENEWALS_EXHAUSTED', repair_authorization.issued_at
    from public.document_repair_authorizations repair_authorization
    join public.document_operations operation on operation.id = repair_authorization.operation_id
    where repair_authorization.state = 'active' and repair_authorization.renewal_count = 6
  ),
  filtered as materialized (
    select * from inventory_candidates candidate
    where (p_after_key is null or candidate.inventory_key > p_after_key)
      and (p_document_category is null or candidate.document_category = p_document_category)
      and (p_anomaly_type is null or candidate.anomaly_type = p_anomaly_type)
    order by candidate.inventory_key
    limit p_limit + 1
  ),
  page as (
    select * from filtered order by inventory_key limit p_limit
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'inventoryKey', page.inventory_key,
      'documentCategory', page.document_category,
      'anomalyType', page.anomaly_type,
      'findingStatus', page.finding_status,
      'protectedPersonId', page.protected_person_id,
      'businessEntityType', page.business_entity_type,
      'businessEntityId', page.business_entity_id,
      'operationId', page.operation_id,
      'catalogObjectPresent', page.catalog_object_present,
      'physicalVerification', 'not_performed',
      'physicalVerificationRequired', page.physical_verification_required,
      'actionBlocked', page.action_blocked,
      'storageGuardRequired', page.storage_guard_required,
      'detailCode', page.detail_code,
      'sourceCreatedAt', page.source_created_at
    ) order by page.inventory_key), '[]'::jsonb),
    (select inventory_key from page order by inventory_key desc limit 1),
    (select count(*) > p_limit from filtered)
  into result_items, next_cursor, has_more
  from page;

  return jsonb_build_object(
    'items', result_items,
    'nextCursor', case when has_more then next_cursor else null end,
    'hasMore', has_more,
    'limit', p_limit,
    'physicalInspectionPerformed', false,
    'consistency', 'keyset_without_snapshot'
  );
end;
$$;

create function public.get_administrative_document_repair_capabilities()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.is_platform_admin() then
    raise exception using errcode = 'P4R01',
      message = 'Capacités de réparation non autorisées.';
  end if;
  return jsonb_build_object(
    'storageGuardEnabled', public.is_document_storage_guard_enabled()
  );
end;
$$;

create function public.reject_unguarded_administrative_document_repair_item()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_row public.document_operation_targets%rowtype;
  object_exists boolean;
begin
  if public.is_document_storage_guard_enabled() then
    return new;
  end if;
  select * into target_row from public.document_operation_targets
  where id = new.target_id and operation_id = new.operation_id;
  if not found then
    raise exception using errcode = 'P4R04',
      message = 'La cible documentaire a changé.';
  end if;
  select exists(
    select 1 from storage.objects object
    where object.bucket_id = target_row.bucket_id
      and object.name = target_row.object_path
  ) into object_exists;
  if new.action = 'complete_backup_cleanup'
     or (new.action = 'resume_compensation'
       and target_row.compensation_action = 'delete')
     or (new.action in ('restore_original','resume_compensation') and object_exists) then
    raise exception using errcode = 'P4R08',
      message = 'Cette action exige la garde Storage conditionnelle.';
  end if;
  return new;
end;
$$;

create trigger document_repair_items_reject_unguarded_action
before insert on public.document_repair_items
for each row execute function public.reject_unguarded_administrative_document_repair_item();

revoke all on function public.get_administrative_document_inventory(integer,text,text,text),
  public.get_administrative_document_repair_capabilities(),
  public.reject_unguarded_administrative_document_repair_item()
from public, anon, authenticated, service_role;
grant execute on function public.get_administrative_document_inventory(integer,text,text,text),
  public.get_administrative_document_repair_capabilities()
to authenticated;

comment on function public.get_administrative_document_inventory(integer,text,text,text) is
  'Inventaire administratif paginé du catalogue SQL. Ne lit jamais les octets Storage et ne retourne aucun chemin.';
comment on function public.reject_unguarded_administrative_document_repair_item() is
  'Refuse transactionnellement un plan de réparation déjà connu comme destructif tant que la garde Storage est inactive.';
