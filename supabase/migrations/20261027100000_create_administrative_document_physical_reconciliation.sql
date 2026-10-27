-- PAT-DOSSIERS-ARCHIVAGE-01B-2D-3C-3H-2C5D
-- Réconciliation physique strictement en lecture seule. Le navigateur ne
-- fournit jamais de bucket ni de chemin et les observations sont append-only.

create table public.administrative_document_physical_verification_requests (
  id uuid primary key default gen_random_uuid(),
  administrator_subject_id uuid not null,
  client_request_id uuid not null,
  inventory_key text not null check (
    char_length(inventory_key) between 1 and 200
    and inventory_key ~ '^[a-z0-9_:-]+$'
  ),
  document_category text not null check (document_category in (
    'transaction_proof','bank_statement','management_report','backup'
  )),
  anomaly_type text not null,
  protected_person_id uuid,
  business_entity_type text,
  business_entity_id uuid,
  bucket_id text,
  object_path text,
  initial_catalog_object_id uuid,
  initial_catalog_object_version text,
  expected_byte_size bigint check (expected_byte_size is null or expected_byte_size >= 0),
  expected_sha256 text check (expected_sha256 is null or expected_sha256 ~ '^[0-9a-f]{64}$'),
  context_fingerprint text not null check (context_fingerprint ~ '^[0-9a-f]{64}$'),
  server_capability text not null check (server_capability ~ '^[0-9a-f]{64}$'),
  state text not null default 'authorized' check (state in ('authorized','completed')),
  issued_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  completed_at timestamptz,
  unique (administrator_subject_id, client_request_id),
  check (expires_at > issued_at and expires_at <= issued_at + interval '5 minutes'),
  check ((state = 'completed') = (completed_at is not null)),
  check ((bucket_id is null) = (object_path is null))
);

create table public.administrative_document_physical_observations (
  id uuid primary key default gen_random_uuid(),
  verification_request_id uuid not null unique references public.administrative_document_physical_verification_requests(id) on delete restrict,
  administrator_subject_id uuid not null,
  inventory_key text not null,
  document_category text not null,
  anomaly_type text not null,
  protected_person_id uuid,
  business_entity_type text,
  business_entity_id uuid,
  outcome text not null check (outcome in (
    'verified_readable','missing_physical_bytes','version_mismatch',
    'hash_mismatch','verification_inconclusive','stale_inventory_finding'
  )),
  proof_level text not null check (proof_level in (
    'catalog_only','physical_readability','physical_integrity','inconclusive','stale'
  )),
  observed_catalog_object_id uuid,
  observed_catalog_object_version text,
  observed_byte_size bigint check (observed_byte_size is null or observed_byte_size between 0 and 20971520),
  observed_sha256 text check (observed_sha256 is null or observed_sha256 ~ '^[0-9a-f]{64}$'),
  limitation_code text check (limitation_code is null or limitation_code ~ '^[A-Z0-9_:-]{1,64}$'),
  observed_at timestamptz not null default clock_timestamp(),
  check ((observed_byte_size is null) = (observed_sha256 is null)),
  check (outcome <> 'hash_mismatch' or proof_level = 'physical_integrity'),
  check (outcome <> 'stale_inventory_finding' or proof_level = 'stale')
);

create index administrative_document_physical_observations_inventory_idx
on public.administrative_document_physical_observations(inventory_key, observed_at desc, id desc);

alter table public.administrative_document_physical_verification_requests enable row level security;
alter table public.administrative_document_physical_observations enable row level security;
revoke all on table public.administrative_document_physical_verification_requests,
  public.administrative_document_physical_observations
from public, anon, authenticated, service_role;

create function public.reject_administrative_document_physical_observation_mutation()
returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception using errcode = '42501', message = 'Les observations physiques sont immuables.';
end;
$$;

create trigger administrative_document_physical_observations_immutable
before update or delete on public.administrative_document_physical_observations
for each row execute function public.reject_administrative_document_physical_observation_mutation();

-- Résolveur privé. Il reconstitue le chemin depuis l'identité SQL du constat ;
-- aucune valeur de chemin provenant du client n'entre dans ce contrat.
create function public.resolve_administrative_document_physical_finding(p_inventory_key text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  category text := split_part(p_inventory_key, ':', 1);
  anomaly text := split_part(p_inventory_key, ':', 2);
  identifier uuid;
  bucket text;
  path text;
  protected_id uuid;
  entity_type text;
  entity_id uuid;
  catalog storage.objects%rowtype;
  reference_size bigint;
  reference_hash text;
  valid_finding boolean := false;
  resolution record;
begin
  if p_inventory_key is null or p_inventory_key !~ '^[a-z0-9_]+:[a-z0-9_]+:[0-9a-f-]{36}$' then
    return null;
  end if;
  begin identifier := split_part(p_inventory_key, ':', 3)::uuid;
  exception when invalid_text_representation then return null; end;

  if category in ('transaction_proof','bank_statement','management_report')
     and anomaly in ('business_reference_without_catalog_object','historical_noncanonical_path',
       'business_attachment_mismatch','no_durable_operation_history') then
    if category = 'transaction_proof' then
      select 'transaction-proofs', document.storage_path, account.protected_person_id,
        'transaction', document.transaction_id, document.file_size
      into bucket,path,protected_id,entity_type,entity_id,reference_size
      from public.transaction_documents document
      join public.transactions transaction on transaction.id=document.transaction_id
      join public.financial_accounts account on account.id=transaction.financial_account_id
      where document.id=identifier;
    elsif category = 'bank_statement' then
      select 'bank-statements', statement.storage_path, account.protected_person_id,
        'bank_statement', statement.id, statement.file_size
      into bucket,path,protected_id,entity_type,entity_id,reference_size
      from public.bank_statements statement
      join public.financial_accounts account on account.id=statement.financial_account_id
      where statement.id=identifier;
    else
      select 'management-reports', document.storage_path, report.protected_person_id,
        'management_report', report.id, document.file_size
      into bucket,path,protected_id,entity_type,entity_id,reference_size
      from public.management_report_documents document
      join public.management_reports report on report.id=document.management_report_id
      where document.id=identifier;
    end if;
    if not found then return null; end if;
    select * into catalog from storage.objects object
      where object.bucket_id=bucket and object.name=path;
    select * into resolution from public.resolve_canonical_document_storage_path(bucket,path);
    valid_finding := case anomaly
      when 'business_reference_without_catalog_object' then catalog.id is null
      when 'historical_noncanonical_path' then not resolution.is_canonical
      when 'business_attachment_mismatch' then resolution.is_canonical and (
        resolution.protected_person_id is distinct from protected_id
        or resolution.business_entity_type is distinct from entity_type
        or resolution.business_entity_id is distinct from entity_id)
      when 'no_durable_operation_history' then not exists (
        select 1 from public.document_operation_targets target
        where target.bucket_id=bucket and target.object_path=path)
      else false end;
  elsif category in ('transaction_proof','bank_statement','management_report')
     and anomaly in ('catalog_object_without_business_reference','unresolved_catalog_path',
       'storage_identity_incomplete','storage_owner_unrecorded') then
    bucket := case category when 'transaction_proof' then 'transaction-proofs'
      when 'bank_statement' then 'bank-statements' else 'management-reports' end;
    select * into catalog from storage.objects object where object.id=identifier and object.bucket_id=bucket;
    if not found then return null; end if;
    path := catalog.name;
    select * into resolution from public.resolve_canonical_document_storage_path(bucket,path);
    protected_id := resolution.protected_person_id;
    entity_type := resolution.business_entity_type;
    entity_id := resolution.business_entity_id;
    valid_finding := case anomaly
      when 'catalog_object_without_business_reference' then resolution.is_canonical and not exists (
        select 1 from public.transaction_documents d where bucket='transaction-proofs' and d.storage_path=path
        union all select 1 from public.bank_statements d where bucket='bank-statements' and d.storage_path=path
        union all select 1 from public.management_report_documents d where bucket='management-reports' and d.storage_path=path)
      when 'unresolved_catalog_path' then not resolution.is_canonical and not exists (
        select 1 from public.transaction_documents d where bucket='transaction-proofs' and d.storage_path=path
        union all select 1 from public.bank_statements d where bucket='bank-statements' and d.storage_path=path
        union all select 1 from public.management_report_documents d where bucket='management-reports' and d.storage_path=path)
      when 'storage_identity_incomplete' then catalog.version is null or btrim(catalog.version)='' or catalog.metadata is null
      when 'storage_owner_unrecorded' then catalog.owner_id is null
      else false end;
  elsif category='backup' and anomaly in ('backup_catalog_object_missing','backup_physical_verification_required') then
    select 'document-operation-backups', backup.recovery_object_path,
      backup.protected_person_id, operation.business_entity_type, operation.business_entity_id,
      backup.byte_size, backup.sha256
    into bucket,path,protected_id,entity_type,entity_id,reference_size,reference_hash
    from public.document_operation_backups backup
    join public.document_operations operation on operation.id=backup.operation_id
    where backup.id=identifier and backup.state<>'deleted';
    if not found then return null; end if;
    select * into catalog from storage.objects object where object.bucket_id=bucket and object.name=path;
    valid_finding := case anomaly
      when 'backup_catalog_object_missing' then catalog.id is null
      when 'backup_physical_verification_required' then catalog.id is not null
      else false end;
  end if;

  if not valid_finding then return null; end if;
  return jsonb_build_object(
    'inventoryKey',p_inventory_key,'documentCategory',category,'anomalyType',anomaly,
    'protectedPersonId',protected_id,'businessEntityType',entity_type,'businessEntityId',entity_id,
    'bucketId',bucket,'objectPath',path,'catalogObjectId',catalog.id,
    'catalogObjectVersion',catalog.version,'expectedByteSize',reference_size,
    'expectedSha256',reference_hash,
    'contextFingerprint',encode(extensions.digest(pg_catalog.jsonb_build_array(
      p_inventory_key,bucket,path,catalog.id,catalog.version,reference_size,reference_hash
    )::text,'sha256'),'hex')
  );
end;
$$;

create function public.begin_administrative_document_physical_verification(
  p_inventory_key text, p_client_request_id uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  caller_id uuid := auth.uid();
  descriptor jsonb;
  request_row public.administrative_document_physical_verification_requests%rowtype;
  observation_row public.administrative_document_physical_observations%rowtype;
  capability text;
begin
  if caller_id is null or not public.is_platform_admin() then
    raise exception using errcode='P4V01', message='Vérification physique non autorisée.';
  end if;
  if p_client_request_id is null or p_inventory_key is null
     or char_length(p_inventory_key) not between 1 and 200
     or p_inventory_key !~ '^[a-z0-9_:-]+$' then
    raise exception using errcode='P4V02', message='Demande de vérification invalide.';
  end if;
  if split_part(p_inventory_key,':',1) not in (
    'transaction_proof','bank_statement','management_report','backup'
  ) then
    raise exception using errcode='P4V02', message='Ce constat ne possède pas de cible physique vérifiable.';
  end if;
  -- Sérialise les autorisations afin que les plafonds de lectures simultanées
  -- ne puissent pas être dépassés par deux requêtes concurrentes.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'administrative-document-physical-verification-issuance', 0
  ));
  select * into request_row from public.administrative_document_physical_verification_requests
    where administrator_subject_id=caller_id and client_request_id=p_client_request_id;
  if found then
    if request_row.inventory_key<>p_inventory_key then
      raise exception using errcode='P4V03', message='Identifiant de demande déjà utilisé pour une autre intention.';
    end if;
    select * into observation_row from public.administrative_document_physical_observations
      where verification_request_id=request_row.id;
    return jsonb_build_object('verificationRequestId',request_row.id,'state',request_row.state,
      'observationId',observation_row.id,'outcome',observation_row.outcome,'observation',
      case when observation_row.id is null then null else jsonb_build_object(
        'id',observation_row.id,'inventoryKey',observation_row.inventory_key,
        'outcome',observation_row.outcome,'proofLevel',observation_row.proof_level,
        'observedByteSize',observation_row.observed_byte_size,
        'limitationCode',observation_row.limitation_code,'observedAt',observation_row.observed_at) end);
  end if;
  if (select count(*) from public.administrative_document_physical_verification_requests
      where administrator_subject_id=caller_id and issued_at>statement_timestamp()-interval '1 minute') >= 10 then
    raise exception using errcode='P4V04', message='Trop de vérifications demandées. Réessayez dans un instant.';
  end if;
  if (select count(*) from public.administrative_document_physical_verification_requests
      where state='authorized' and expires_at>statement_timestamp()) >= 4
     or exists (
       select 1 from public.administrative_document_physical_verification_requests
       where administrator_subject_id=caller_id and state='authorized'
         and expires_at>statement_timestamp()
     ) then
    raise exception using errcode='P4V09', message='Une autre lecture physique est déjà en cours.';
  end if;
  descriptor := public.resolve_administrative_document_physical_finding(p_inventory_key);
  capability := encode(extensions.gen_random_bytes(32),'hex');
  if descriptor is null then
    insert into public.administrative_document_physical_verification_requests(
      administrator_subject_id,client_request_id,inventory_key,document_category,anomaly_type,
      context_fingerprint,server_capability,state,expires_at,completed_at)
    values(caller_id,p_client_request_id,p_inventory_key,split_part(p_inventory_key,':',1),
      split_part(p_inventory_key,':',2),encode(extensions.digest(p_inventory_key,'sha256'),'hex'),
      capability,'completed',statement_timestamp()+interval '5 minutes',clock_timestamp())
    returning * into request_row;
    insert into public.administrative_document_physical_observations(
      verification_request_id,administrator_subject_id,inventory_key,document_category,anomaly_type,
      outcome,proof_level,limitation_code)
    values(request_row.id,caller_id,p_inventory_key,request_row.document_category,request_row.anomaly_type,
      'stale_inventory_finding','stale','INVENTORY_FINDING_CHANGED') returning * into observation_row;
    return jsonb_build_object('verificationRequestId',request_row.id,'state','completed',
      'observationId',observation_row.id,'outcome',observation_row.outcome,'observation',
      jsonb_build_object('id',observation_row.id,'inventoryKey',observation_row.inventory_key,
        'outcome',observation_row.outcome,'proofLevel',observation_row.proof_level,
        'observedByteSize',observation_row.observed_byte_size,
        'limitationCode',observation_row.limitation_code,'observedAt',observation_row.observed_at));
  end if;
  insert into public.administrative_document_physical_verification_requests(
    administrator_subject_id,client_request_id,inventory_key,document_category,anomaly_type,
    protected_person_id,business_entity_type,business_entity_id,bucket_id,object_path,
    initial_catalog_object_id,initial_catalog_object_version,expected_byte_size,expected_sha256,
    context_fingerprint,server_capability,expires_at)
  values(caller_id,p_client_request_id,p_inventory_key,descriptor->>'documentCategory',descriptor->>'anomalyType',
    (descriptor->>'protectedPersonId')::uuid,descriptor->>'businessEntityType',
    (descriptor->>'businessEntityId')::uuid,descriptor->>'bucketId',descriptor->>'objectPath',
    (descriptor->>'catalogObjectId')::uuid,descriptor->>'catalogObjectVersion',
    (descriptor->>'expectedByteSize')::bigint,descriptor->>'expectedSha256',
    descriptor->>'contextFingerprint',capability,statement_timestamp()+interval '5 minutes')
  returning * into request_row;
  return jsonb_build_object('verificationRequestId',request_row.id,'state','authorized');
end;
$$;

create function public.get_administrative_document_physical_verification_descriptor(p_verification_request_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  request_row public.administrative_document_physical_verification_requests%rowtype;
  current_descriptor jsonb;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode='P4V01', message='Contexte technique non autorisé.';
  end if;
  select * into request_row from public.administrative_document_physical_verification_requests
    where id=p_verification_request_id;
  if not found then raise exception using errcode='P4V05', message='Vérification introuvable.'; end if;
  if request_row.state<>'authorized' then
    raise exception using errcode='P4V06', message='Vérification déjà terminée.';
  end if;
  if request_row.expires_at<=statement_timestamp() then
    raise exception using errcode='P4V07', message='Autorisation de vérification expirée.';
  end if;
  current_descriptor := public.resolve_administrative_document_physical_finding(request_row.inventory_key);
  if current_descriptor is null
     or current_descriptor->>'contextFingerprint'<>request_row.context_fingerprint then
    return jsonb_build_object('verificationRequestId',request_row.id,'state','stale',
      'inventoryKey',request_row.inventory_key,'bucketId',null,'objectPath',null,
      'catalogObjectId',null,'catalogObjectVersion',null,'expectedByteSize',null,
      'expectedSha256',null,'contextFingerprint',request_row.context_fingerprint,
      'serverCapability',request_row.server_capability,'expiresAt',request_row.expires_at);
  end if;
  return jsonb_build_object('verificationRequestId',request_row.id,'state',request_row.state,
    'inventoryKey',request_row.inventory_key,'bucketId',request_row.bucket_id,'objectPath',request_row.object_path,
    'catalogObjectId',request_row.initial_catalog_object_id,'catalogObjectVersion',request_row.initial_catalog_object_version,
    'expectedByteSize',request_row.expected_byte_size,'expectedSha256',request_row.expected_sha256,
    'contextFingerprint',request_row.context_fingerprint,'serverCapability',request_row.server_capability,
    'expiresAt',request_row.expires_at);
end;
$$;

create function public.complete_administrative_document_physical_verification(
  p_verification_request_id uuid, p_server_capability text, p_outcome text,
  p_proof_level text, p_catalog_object_id uuid, p_catalog_object_version text,
  p_observed_byte_size bigint, p_observed_sha256 text, p_limitation_code text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  request_row public.administrative_document_physical_verification_requests%rowtype;
  observation_row public.administrative_document_physical_observations%rowtype;
  current_descriptor jsonb;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception using errcode='P4V01', message='Contexte technique non autorisé.';
  end if;
  select * into request_row from public.administrative_document_physical_verification_requests
    where id=p_verification_request_id for update;
  if not found or request_row.server_capability is distinct from p_server_capability then
    raise exception using errcode='P4V05', message='Vérification introuvable.';
  end if;
  select * into observation_row from public.administrative_document_physical_observations
    where verification_request_id=request_row.id;
  if found then
    return jsonb_build_object('observationId',observation_row.id,'outcome',observation_row.outcome,
      'observation',jsonb_build_object(
        'id',observation_row.id,'inventoryKey',observation_row.inventory_key,
        'outcome',observation_row.outcome,'proofLevel',observation_row.proof_level,
        'observedByteSize',observation_row.observed_byte_size,
        'limitationCode',observation_row.limitation_code,'observedAt',observation_row.observed_at));
  end if;
  if request_row.state<>'authorized' then
    raise exception using errcode='P4V06', message='Vérification déjà terminée.';
  end if;
  if request_row.expires_at<=statement_timestamp() then
    raise exception using errcode='P4V07', message='Autorisation de vérification expirée.';
  end if;
  current_descriptor := public.resolve_administrative_document_physical_finding(request_row.inventory_key);
  if current_descriptor is null or current_descriptor->>'contextFingerprint'<>request_row.context_fingerprint then
    p_outcome := 'stale_inventory_finding'; p_proof_level := 'stale';
    p_catalog_object_id := null; p_catalog_object_version := null;
    p_observed_byte_size := null; p_observed_sha256 := null;
    p_limitation_code := 'INVENTORY_FINDING_CHANGED';
  end if;
  if p_outcome not in ('verified_readable','missing_physical_bytes','version_mismatch',
      'hash_mismatch','verification_inconclusive','stale_inventory_finding')
     or p_proof_level not in ('catalog_only','physical_readability','physical_integrity','inconclusive','stale')
     or (p_observed_byte_size is null)<>(p_observed_sha256 is null)
     or (p_observed_sha256 is not null and p_observed_sha256 !~ '^[0-9a-f]{64}$')
     or (p_limitation_code is not null and p_limitation_code !~ '^[A-Z0-9_:-]{1,64}$') then
    raise exception using errcode='P4V02', message='Résultat de vérification invalide.';
  end if;
  if (p_outcome='verified_readable' and (
        p_proof_level not in ('physical_readability','physical_integrity')
        or p_observed_byte_size is null
        or p_catalog_object_id is distinct from request_row.initial_catalog_object_id
        or p_catalog_object_version is distinct from request_row.initial_catalog_object_version
      ))
     or (p_outcome='missing_physical_bytes' and (
        p_proof_level<>'catalog_only' or p_observed_byte_size is not null
      ))
     or (p_outcome='version_mismatch' and (
        p_proof_level<>'catalog_only' or p_observed_byte_size is not null
        or (p_catalog_object_id is not distinct from request_row.initial_catalog_object_id
          and p_catalog_object_version is not distinct from request_row.initial_catalog_object_version)
      ))
     or (p_outcome='hash_mismatch' and (
        p_proof_level<>'physical_integrity' or p_observed_byte_size is null
        or request_row.expected_sha256 is null
        or p_observed_sha256=request_row.expected_sha256
      ))
     or (p_outcome='stale_inventory_finding' and (
        p_proof_level<>'stale' or p_observed_byte_size is not null
      ))
     or (p_outcome='verified_readable' and request_row.expected_sha256 is not null
       and (p_proof_level<>'physical_integrity' or p_observed_sha256<>request_row.expected_sha256)) then
    raise exception using errcode='P4V02', message='Résultat de vérification incohérent.';
  end if;
  insert into public.administrative_document_physical_observations(
    verification_request_id,administrator_subject_id,inventory_key,document_category,anomaly_type,
    protected_person_id,business_entity_type,business_entity_id,outcome,proof_level,
    observed_catalog_object_id,observed_catalog_object_version,observed_byte_size,observed_sha256,limitation_code)
  values(request_row.id,request_row.administrator_subject_id,request_row.inventory_key,
    request_row.document_category,request_row.anomaly_type,request_row.protected_person_id,
    request_row.business_entity_type,request_row.business_entity_id,p_outcome,p_proof_level,
    p_catalog_object_id,p_catalog_object_version,p_observed_byte_size,p_observed_sha256,p_limitation_code)
  returning * into observation_row;
  update public.administrative_document_physical_verification_requests
    set state='completed',completed_at=clock_timestamp() where id=request_row.id;
  return jsonb_build_object('observationId',observation_row.id,'outcome',observation_row.outcome,
    'observation',jsonb_build_object(
      'id',observation_row.id,'inventoryKey',observation_row.inventory_key,
      'outcome',observation_row.outcome,'proofLevel',observation_row.proof_level,
      'observedByteSize',observation_row.observed_byte_size,
      'limitationCode',observation_row.limitation_code,'observedAt',observation_row.observed_at));
end;
$$;

create function public.get_administrative_document_physical_observations(
  p_inventory_key text, p_limit integer default 20, p_before_observed_at timestamptz default null
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result_items jsonb;
begin
  if auth.uid() is null or not public.is_platform_admin() then
    raise exception using errcode='P4V01', message='Historique physique non autorisé.';
  end if;
  if p_inventory_key is null or p_inventory_key !~ '^[a-z0-9_:-]{1,200}$' or p_limit not between 1 and 50 then
    raise exception using errcode='P4V02', message='Demande d’historique invalide.';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',observation.id,'inventoryKey',observation.inventory_key,'outcome',observation.outcome,
    'proofLevel',observation.proof_level,'observedByteSize',observation.observed_byte_size,
    'limitationCode',observation.limitation_code,'observedAt',observation.observed_at
  ) order by observation.observed_at desc,observation.id desc),'[]'::jsonb)
  into result_items from (
    select * from public.administrative_document_physical_observations observation
    where observation.inventory_key=p_inventory_key
      and (p_before_observed_at is null or observation.observed_at<p_before_observed_at)
    order by observation.observed_at desc,observation.id desc limit p_limit
  ) observation;
  return jsonb_build_object('items',result_items,'limit',p_limit);
end;
$$;

revoke all on function public.resolve_administrative_document_physical_finding(text),
  public.reject_administrative_document_physical_observation_mutation(),
  public.begin_administrative_document_physical_verification(text,uuid),
  public.get_administrative_document_physical_verification_descriptor(uuid),
  public.complete_administrative_document_physical_verification(uuid,text,text,text,uuid,text,bigint,text,text),
  public.get_administrative_document_physical_observations(text,integer,timestamptz)
from public, anon, authenticated, service_role;
grant execute on function public.begin_administrative_document_physical_verification(text,uuid),
  public.get_administrative_document_physical_observations(text,integer,timestamptz)
to authenticated;
grant execute on function public.get_administrative_document_physical_verification_descriptor(uuid),
  public.complete_administrative_document_physical_verification(uuid,text,text,text,uuid,text,bigint,text,text)
to service_role;

comment on table public.administrative_document_physical_observations is
  'Observations append-only de lectures physiques Storage, sans chemin, octets, URL ni secret.';
comment on function public.resolve_administrative_document_physical_finding(text) is
  'Résolveur privé des constats SQL vers un chemin Storage autoritatif ; aucun droit API direct.';
