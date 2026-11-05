-- PAT-TRANSACTIONS-01C-DOC
-- Modèle versionné des justificatifs de transactions et sécurisation des
-- conversions successives. Les chemins historiques /proof restent lisibles.

alter table public.proof_reference_assignments
  add column id uuid not null default gen_random_uuid(),
  add column started_revision bigint,
  add column ended_revision bigint,
  add column ended_at timestamptz,
  add column ended_by_change_id uuid references public.transaction_changes(id) on delete restrict;

alter table public.proof_reference_assignments
  drop constraint proof_reference_assignments_pkey;
alter table public.proof_reference_assignments
  add constraint proof_reference_assignments_pkey primary key (id),
  add constraint proof_reference_assignments_episode_consistency check (
    (ended_at is null and ended_revision is null and ended_by_change_id is null)
    or (ended_at is not null and ended_revision is not null)
  );
create index proof_reference_assignments_transaction_idx
  on public.proof_reference_assignments(transaction_id, created_at desc);
create unique index proof_reference_assignments_current_transaction_idx
  on public.proof_reference_assignments(transaction_id) where ended_at is null;
update public.proof_reference_assignments assignment
set started_revision=coalesce(assignment.started_revision,transaction.revision),
  ended_revision=case when transaction.transaction_type<>'expense'
    then transaction.revision else assignment.ended_revision end,
  ended_at=case when transaction.transaction_type<>'expense'
    then coalesce(assignment.ended_at,clock_timestamp()) else assignment.ended_at end
from public.transactions transaction
where transaction.id=assignment.transaction_id;

create table public.transaction_proof_documents (
  id uuid primary key default gen_random_uuid(),
  protected_person_id uuid not null references public.protected_persons(id) on delete restrict,
  transaction_id uuid not null references public.transactions(id) on delete restrict,
  expense_reference_assignment_id uuid not null unique
    references public.proof_reference_assignments(id) on delete restrict,
  proof_reference text not null,
  lifecycle_status text not null check (lifecycle_status in ('current','historical')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  detached_at timestamptz,
  detached_by_change_id uuid references public.transaction_changes(id) on delete restrict,
  constraint transaction_proof_documents_detachment_consistency check (
    (lifecycle_status = 'current' and detached_at is null and detached_by_change_id is null)
    or (lifecycle_status = 'historical' and detached_at is not null and detached_by_change_id is not null)
  )
);
create unique index transaction_proof_documents_current_transaction_idx
  on public.transaction_proof_documents(transaction_id) where lifecycle_status = 'current';
create index transaction_proof_documents_transaction_idx
  on public.transaction_proof_documents(transaction_id, created_at desc);

create table public.transaction_proof_versions (
  id uuid primary key default gen_random_uuid(),
  proof_document_id uuid not null references public.transaction_proof_documents(id) on delete restrict,
  version_number bigint not null check (version_number > 0),
  storage_path text not null unique,
  path_kind text not null check (path_kind in ('legacy','versioned')),
  lifecycle_state text not null check (lifecycle_state in (
    'current','historical','superseded_pending_deletion','deleted'
  )),
  availability_status text not null default 'unverified'
    check (availability_status in ('unverified','available','missing')),
  file_name text not null,
  mime_type text not null check (mime_type in ('application/pdf','image/jpeg','image/png')),
  file_size bigint not null check (file_size > 0 and file_size <= 10485760),
  sha256 text check (sha256 is null or sha256 ~ '^[0-9a-f]{64}$'),
  storage_object_id uuid,
  storage_object_version text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  superseded_at timestamptz,
  replacement_operation_id uuid references public.document_operations(id) on delete restrict,
  unique (proof_document_id, version_number),
  constraint transaction_proof_versions_path_shape check (
    (path_kind = 'legacy' and storage_path ~ '^protected-persons/[0-9a-f-]{36}/transactions/[0-9a-f-]{36}/proof$')
    or
    (path_kind = 'versioned' and storage_path ~ '^protected-persons/[0-9a-f-]{36}/transactions/[0-9a-f-]{36}/proofs/[0-9a-f-]{36}/versions/[0-9a-f-]{36}$')
  )
);
create unique index transaction_proof_versions_current_document_idx
  on public.transaction_proof_versions(proof_document_id) where lifecycle_state = 'current';
create index transaction_proof_versions_document_idx
  on public.transaction_proof_versions(proof_document_id, version_number desc);

create table public.transaction_proof_replacement_retirements (
  id uuid primary key default gen_random_uuid(),
  proof_document_id uuid not null references public.transaction_proof_documents(id) on delete restrict,
  superseded_version_id uuid not null unique references public.transaction_proof_versions(id) on delete restrict,
  replacement_version_id uuid not null references public.transaction_proof_versions(id) on delete restrict,
  operation_id uuid not null references public.document_operations(id) on delete restrict,
  state text not null default 'pending_secure_deletion'
    check (state in ('pending_secure_deletion','completed','attention_required')),
  created_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  constraint transaction_proof_retirement_distinct_versions
    check (superseded_version_id <> replacement_version_id),
  constraint transaction_proof_retirement_completion check (
    (state = 'completed' and completed_at is not null)
    or (state <> 'completed' and completed_at is null)
  )
);

alter table public.transaction_documents
  add column proof_document_id uuid references public.transaction_proof_documents(id) on delete restrict,
  add column proof_version_id uuid references public.transaction_proof_versions(id) on delete restrict;

alter table public.transaction_document_history
  drop constraint transaction_document_history_storage_path_key,
  add column proof_document_id uuid references public.transaction_proof_documents(id) on delete restrict,
  add column proof_version_id uuid references public.transaction_proof_versions(id) on delete restrict,
  add column expense_reference_assignment_id uuid references public.proof_reference_assignments(id) on delete restrict,
  add column proof_reference text,
  add column availability_status text not null default 'unverified'
    check (availability_status in ('unverified','available','missing'));
create unique index transaction_document_history_proof_version_idx
  on public.transaction_document_history(proof_version_id) where proof_version_id is not null;

alter table public.transaction_proof_documents enable row level security;
alter table public.transaction_proof_versions enable row level security;
alter table public.transaction_proof_replacement_retirements enable row level security;

create policy transaction_proof_documents_select_accessible
on public.transaction_proof_documents for select to authenticated
using (public.can_read_protected_person(protected_person_id));

create policy transaction_proof_versions_select_accessible
on public.transaction_proof_versions for select to authenticated
using (exists (
  select 1 from public.transaction_proof_documents document
  where document.id = transaction_proof_versions.proof_document_id
    and public.can_read_protected_person(document.protected_person_id)
));

create policy transaction_proof_retirements_select_accessible
on public.transaction_proof_replacement_retirements for select to authenticated
using (exists (
  select 1 from public.transaction_proof_documents document
  where document.id = transaction_proof_replacement_retirements.proof_document_id
    and public.can_read_protected_person(document.protected_person_id)
));

revoke all on table public.transaction_proof_documents,
  public.transaction_proof_versions,
  public.transaction_proof_replacement_retirements
from public, anon, authenticated, service_role;
grant select on table public.transaction_proof_documents,
  public.transaction_proof_versions,
  public.transaction_proof_replacement_retirements to authenticated;

-- L'inventaire administratif existant doit considérer chaque version conservée
-- comme une référence métier. La fonction historique est longue et stable :
-- cette transformation additive, contrôlée par une sentinelle exacte, injecte
-- uniquement la nouvelle source sans recopier ni altérer ses autres règles.
do $$
declare function_sql text; needle text; replacement text;
begin
  function_sql:=pg_get_functiondef(
    'public.get_administrative_document_inventory(integer,text,text,text)'::regprocedure
  );
  needle:=$needle$
    from public.transaction_documents document
    join public.transactions transaction on transaction.id = document.transaction_id
    join public.financial_accounts account on account.id = transaction.financial_account_id
    union all
    select 'bank_statement'$needle$;
  replacement:=$replacement$
    from public.transaction_documents document
    join public.transactions transaction on transaction.id = document.transaction_id
    join public.financial_accounts account on account.id = transaction.financial_account_id
    union all
    select 'transaction_proof', 'transaction-proofs', version.id,
      document.protected_person_id, 'transaction', document.transaction_id,
      version.storage_path, version.created_at
    from public.transaction_proof_versions version
    join public.transaction_proof_documents document on document.id = version.proof_document_id
    union all
    select 'bank_statement'$replacement$;
  if position(needle in function_sql)=0 then
    raise exception 'La structure de l inventaire administratif est inattendue.';
  end if;
  function_sql:=pg_catalog.replace(function_sql,needle,replacement);
  execute function_sql;
end;
$$;

create function public.build_transaction_proof_version_path(
  p_protected_person_id uuid, p_transaction_id uuid,
  p_document_id uuid, p_version_id uuid
) returns text language sql immutable security definer set search_path = '' as $$
  select 'protected-persons/' || p_protected_person_id || '/transactions/' || p_transaction_id
    || '/proofs/' || p_document_id || '/versions/' || p_version_id
$$;

revoke all on function public.build_transaction_proof_version_path(uuid,uuid,uuid,uuid)
from public, anon, authenticated, service_role;

create or replace function public.resolve_canonical_document_storage_path(
  p_bucket_id text,p_object_path text
) returns table(is_canonical boolean,protected_person_id uuid,business_entity_type text,
  business_entity_id uuid,parent_entity_id uuid,document_kind text)
language plpgsql immutable security definer set search_path='' as $$
declare path_match text[];
  uuid_pattern constant text:='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
begin
  is_canonical:=false; protected_person_id:=null; business_entity_type:=null;
  business_entity_id:=null; parent_entity_id:=null; document_kind:=null;
  if p_bucket_id='transaction-proofs' then
    path_match:=pg_catalog.regexp_match(p_object_path,
      '^protected-persons/('||uuid_pattern||')/transactions/('||uuid_pattern||
      ')/proofs/('||uuid_pattern||')/versions/('||uuid_pattern||')$');
    if path_match is null then
      path_match:=pg_catalog.regexp_match(p_object_path,
        '^protected-persons/('||uuid_pattern||')/transactions/('||uuid_pattern||')/proof$');
    end if;
    if path_match is not null then
      is_canonical:=true; protected_person_id:=path_match[1]::uuid;
      business_entity_type:='transaction'; business_entity_id:=path_match[2]::uuid;
      document_kind:='transaction_proof';
    end if;
  elsif p_bucket_id='bank-statements' then
    path_match:=pg_catalog.regexp_match(p_object_path,
      '^protected-persons/('||uuid_pattern||')/accounts/('||uuid_pattern||
      ')/statements/('||uuid_pattern||')/statement$');
    if path_match is not null then
      is_canonical:=true; protected_person_id:=path_match[1]::uuid;
      parent_entity_id:=path_match[2]::uuid; business_entity_type:='bank_statement';
      business_entity_id:=path_match[3]::uuid; document_kind:='bank_statement';
    end if;
  elsif p_bucket_id='management-reports' then
    path_match:=pg_catalog.regexp_match(p_object_path,
      '^protected-persons/('||uuid_pattern||')/management-reports/('||uuid_pattern||
      ')/(management-report-draft[.]pdf|management-report[.]pdf)$');
    if path_match is not null then
      is_canonical:=true; protected_person_id:=path_match[1]::uuid;
      business_entity_type:='management_report'; business_entity_id:=path_match[2]::uuid;
      document_kind:=case path_match[3] when 'management-report-draft.pdf'
        then 'management_report_draft' else 'management_report_final' end;
    end if;
  end if;
  return next;
end;
$$;

create or replace function public.next_proof_reference(
  p_protected_person_id uuid, p_transaction_date date, p_transaction_id uuid
) returns text language plpgsql security definer set search_path = '' as $$
declare v_reference_year integer := extract(year from p_transaction_date)::integer;
  next_number bigint; generated_reference text;
begin
  insert into public.proof_reference_counters(protected_person_id,reference_year,last_number,updated_at)
  values(p_protected_person_id,v_reference_year,1,now())
  on conflict (protected_person_id,reference_year) do update
    set last_number=public.proof_reference_counters.last_number+1,updated_at=now()
  returning last_number into next_number;
  generated_reference:=v_reference_year::text||'-'||lpad(next_number::text,4,'0');
  insert into public.proof_reference_assignments(
    transaction_id,protected_person_id,reference_year,reference_number,proof_reference,started_revision
  ) values(p_transaction_id,p_protected_person_id,v_reference_year,next_number,generated_reference,
    coalesce((select revision from public.transactions where id=p_transaction_id),1));
  return generated_reference;
end;
$$;

create or replace function public.manage_expense_proof_reference()
returns trigger language plpgsql security definer set search_path = '' as $$
declare person_id uuid; account_kind text;
begin
  select protected_person_id,account_type into person_id,account_kind
  from public.financial_accounts where id=new.financial_account_id;
  if person_id is null then raise exception 'Compte introuvable.'; end if;
  if new.transaction_type in ('income','expense')
     and account_kind in ('life_insurance','other_investment','securities_account') then
    raise exception 'Les recettes et dépenses nécessitent un compte transactionnel.';
  end if;
  if tg_op='INSERT' then
    new.proof_reference:=case when new.transaction_type='expense'
      then public.next_proof_reference(person_id,new.transaction_date,new.id) else null end;
  elsif new.transaction_type<>'expense' then
    new.proof_reference:=null;
  elsif old.transaction_type='expense' then
    if extract(year from new.transaction_date)<>extract(year from old.transaction_date) then
      raise exception 'Une dépense numérotée ne peut pas être déplacée vers une autre année.';
    end if;
    new.proof_reference:=old.proof_reference;
  else
    new.proof_reference:=public.next_proof_reference(person_id,new.transaction_date,new.id);
  end if;
  return new;
end;
$$;

create function public.assert_no_active_transaction_document_operation(p_transaction_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if exists (
    select 1 from public.document_operations operation
    where operation.business_entity_type='transaction'
      and operation.business_entity_id=p_transaction_id
      and operation.state in ('reserved','executing','compensating','attention_required')
  ) then
    raise exception using errcode='55000',
      message='Une opération documentaire est déjà en cours pour cette transaction.';
  end if;
end;
$$;
revoke all on function public.assert_no_active_transaction_document_operation(uuid)
from public, anon, authenticated, service_role;

create function public.archive_current_transaction_proof(
  p_protected_person_id uuid, p_transaction_id uuid, p_transaction_change_id uuid,
  p_actor_id uuid, p_actor_name text, p_reason text
) returns void language plpgsql security definer set search_path = '' as $$
declare assignment_row public.proof_reference_assignments%rowtype;
  legacy_row public.transaction_documents%rowtype;
  document_row public.transaction_proof_documents%rowtype;
  version_row public.transaction_proof_versions%rowtype;
  document_id uuid; version_id uuid;
begin
  select * into assignment_row from public.proof_reference_assignments
  where transaction_id=p_transaction_id and ended_at is null
  order by created_at desc limit 1 for update;
  if not found then
    raise exception using errcode='23514',
      message='La référence du justificatif courant est introuvable.';
  end if;

  select * into legacy_row from public.transaction_documents
  where transaction_id=p_transaction_id for update;

  select * into document_row from public.transaction_proof_documents
  where transaction_id=p_transaction_id and lifecycle_status='current' for update;

  if document_row.id is null and legacy_row.id is not null then
    document_id:=coalesce(legacy_row.proof_document_id,gen_random_uuid());
    version_id:=coalesce(legacy_row.proof_version_id,gen_random_uuid());
    insert into public.transaction_proof_documents(
      id,protected_person_id,transaction_id,expense_reference_assignment_id,
      proof_reference,lifecycle_status,created_by,created_at,detached_at,detached_by_change_id
    ) values(document_id,p_protected_person_id,p_transaction_id,assignment_row.id,
      assignment_row.proof_reference,'historical',legacy_row.created_by,legacy_row.created_at,
      clock_timestamp(),p_transaction_change_id);
    insert into public.transaction_proof_versions(
      id,proof_document_id,version_number,storage_path,path_kind,lifecycle_state,
      availability_status,file_name,mime_type,file_size,created_by,created_at
    ) values(version_id,document_id,1,legacy_row.storage_path,'legacy','historical',
      'unverified',legacy_row.file_name,legacy_row.mime_type,legacy_row.file_size,
      legacy_row.created_by,legacy_row.created_at)
    returning * into version_row;
    update public.transaction_documents
      set proof_document_id=document_id,proof_version_id=version_id
      where id=legacy_row.id;
    document_row.id:=document_id;
  elsif document_row.id is not null then
    update public.transaction_proof_documents set lifecycle_status='historical',
      detached_at=clock_timestamp(),detached_by_change_id=p_transaction_change_id
    where id=document_row.id;
    update public.transaction_proof_versions set lifecycle_state='historical'
    where proof_document_id=document_row.id and lifecycle_state='current'
    returning * into version_row;
  end if;

  if legacy_row.id is not null then
    if version_row.id is null then
      select * into version_row from public.transaction_proof_versions
      where id=legacy_row.proof_version_id;
    end if;
    insert into public.transaction_document_history(
      protected_person_id,transaction_id,transaction_change_id,original_document_id,
      storage_path,file_name,mime_type,file_size,original_created_by,original_created_at,
      original_updated_at,archived_by,archived_by_name,archive_reason,proof_document_id,
      proof_version_id,expense_reference_assignment_id,proof_reference,availability_status
    ) values(p_protected_person_id,p_transaction_id,p_transaction_change_id,legacy_row.id,
      legacy_row.storage_path,legacy_row.file_name,legacy_row.mime_type,legacy_row.file_size,
      legacy_row.created_by,legacy_row.created_at,legacy_row.updated_at,p_actor_id,p_actor_name,
      p_reason,document_row.id,version_row.id,assignment_row.id,assignment_row.proof_reference,
      coalesce(version_row.availability_status,'unverified'));
    delete from public.transaction_documents where id=legacy_row.id;
  elsif version_row.id is not null then
    insert into public.transaction_document_history(
      protected_person_id,transaction_id,transaction_change_id,original_document_id,
      storage_path,file_name,mime_type,file_size,original_created_by,original_created_at,
      original_updated_at,archived_by,archived_by_name,archive_reason,proof_document_id,
      proof_version_id,expense_reference_assignment_id,proof_reference,availability_status
    ) values(p_protected_person_id,p_transaction_id,p_transaction_change_id,version_row.id,
      version_row.storage_path,version_row.file_name,version_row.mime_type,version_row.file_size,
      version_row.created_by,version_row.created_at,version_row.created_at,p_actor_id,p_actor_name,
      p_reason,document_row.id,version_row.id,assignment_row.id,assignment_row.proof_reference,
      version_row.availability_status);
  end if;

  update public.proof_reference_assignments set ended_revision=(
      select revision from public.transactions where id=p_transaction_id
    ),ended_at=clock_timestamp(),ended_by_change_id=p_transaction_change_id
  where id=assignment_row.id;
end;
$$;
revoke all on function public.archive_current_transaction_proof(uuid,uuid,uuid,uuid,text,text)
from public, anon, authenticated, service_role;

create or replace function public.begin_transaction_proof_document_operation(
  p_protected_person_id uuid,p_transaction_id uuid,p_intent text,p_client_request_id uuid
) returns uuid language plpgsql security definer set search_path='' as $$
declare tx record; doc_path text; expected_path text; targets jsonb; workflow text;
begin
  perform public.assert_document_operation_opening_access(p_protected_person_id);
  select t.transaction_type,t.transfer_id,t.cancelled_at,a.protected_person_id into tx
  from public.transactions t join public.financial_accounts a on a.id=t.financial_account_id
  where t.id=p_transaction_id for update of t;
  if not found or tx.protected_person_id<>p_protected_person_id
     or tx.transaction_type<>'expense' or tx.transfer_id is not null
     or tx.cancelled_at is not null or p_intent not in ('create','replace','delete') then
    raise exception using errcode='P4O02',message='Justificatif ou rattachement invalide.';
  end if;
  expected_path:='protected-persons/'||p_protected_person_id||'/transactions/'||p_transaction_id||'/proof';
  select storage_path into doc_path from public.transaction_documents where transaction_id=p_transaction_id;
  if (p_intent='create' and doc_path is not null)
     or (p_intent<>'create' and doc_path is distinct from expected_path) then
    raise exception using errcode='P4O02',message='État du justificatif incompatible avec la demande.';
  end if;
  workflow:='transaction_proof_'||p_intent;
  targets:=jsonb_build_array(jsonb_build_object('ordinal',1,'bucket_id','transaction-proofs',
    'object_path',expected_path,'target_role','primary','forward_action',
    case when p_intent='create' then 'insert' when p_intent='replace' then 'update' else 'delete' end,
    'compensation_action',case when p_intent='create' then 'delete' when p_intent='replace' then 'update' else 'insert' end,
    'expected_exists',p_intent<>'create'));
  return public.create_document_operation(p_protected_person_id,workflow,'transaction',p_transaction_id,p_client_request_id,targets);
end;
$$;

-- Les chemins versionnés sont lisibles par les lecteurs du dossier, mais aucune
-- politique d'écriture directe ne leur est accordée. Leur mutation future devra
-- passer par le moteur durable et la garde Storage.
create policy transaction_proof_versions_select_accessible on storage.objects
for select to authenticated using (
  bucket_id='transaction-proofs' and exists (
    select 1
    from public.transaction_proof_versions version
    join public.transaction_proof_documents document on document.id=version.proof_document_id
    where version.storage_path=storage.objects.name
      and public.can_read_protected_person(document.protected_person_id)
  )
);

drop policy if exists transaction_proofs_insert_manage on storage.objects;
drop policy if exists transaction_proofs_update_manage on storage.objects;
drop policy if exists transaction_proofs_delete_manage on storage.objects;

create policy transaction_proofs_insert_manage on storage.objects
for insert to authenticated with check (
  bucket_id='transaction-proofs'
  and not exists(select 1 from public.transaction_proof_versions version
    where version.storage_path=storage.objects.name)
  and exists (
    select 1 from pg_catalog.regexp_match(name,
      '^protected-persons/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/transactions/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/proof$'
    ) path_match
    join public.transactions transaction on transaction.id=path_match[2]::uuid
    join public.financial_accounts account on account.id=transaction.financial_account_id
    where transaction.transaction_type='expense' and transaction.cancelled_at is null
      and account.protected_person_id=path_match[1]::uuid
      and public.can_manage_protected_person(path_match[1]::uuid)
  )
);

create policy transaction_proofs_update_manage on storage.objects
for update to authenticated using (
  bucket_id='transaction-proofs' and exists (
    select 1 from pg_catalog.regexp_match(name,
      '^protected-persons/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/transactions/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/proof$'
    ) path_match
    join public.transactions transaction on transaction.id=path_match[2]::uuid
    join public.financial_accounts account on account.id=transaction.financial_account_id
    where transaction.transaction_type='expense' and transaction.cancelled_at is null
      and account.protected_person_id=path_match[1]::uuid
      and public.can_manage_protected_person(path_match[1]::uuid)
  )
) with check (
  bucket_id='transaction-proofs' and exists (
    select 1 from pg_catalog.regexp_match(name,
      '^protected-persons/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/transactions/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/proof$'
    ) path_match
    join public.transactions transaction on transaction.id=path_match[2]::uuid
    join public.financial_accounts account on account.id=transaction.financial_account_id
    where transaction.transaction_type='expense' and transaction.cancelled_at is null
      and account.protected_person_id=path_match[1]::uuid
      and public.can_manage_protected_person(path_match[1]::uuid)
  )
);

create policy transaction_proofs_delete_manage on storage.objects
for delete to authenticated using (
  bucket_id='transaction-proofs' and exists (
    select 1 from pg_catalog.regexp_match(name,
      '^protected-persons/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/transactions/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/proof$'
    ) path_match
    join public.transactions transaction on transaction.id=path_match[2]::uuid
    join public.financial_accounts account on account.id=transaction.financial_account_id
    where transaction.transaction_type='expense' and transaction.transfer_id is null
      and transaction.cancelled_at is null
      and account.protected_person_id=path_match[1]::uuid
      and public.can_manage_protected_person(path_match[1]::uuid)
  )
);

-- Les mutations legacy restent compatibles, mais sont interdites après
-- annulation. Les politiques strictes du 31 octobre sont conservées autrement.
drop policy if exists transaction_documents_insert_manage on public.transaction_documents;
drop policy if exists transaction_documents_update_manage on public.transaction_documents;
create policy transaction_documents_insert_manage on public.transaction_documents
for insert to authenticated with check (
  created_by=auth.uid()
  and not exists(select 1 from public.transaction_proof_versions version
    where version.storage_path=transaction_documents.storage_path)
  and exists (
    select 1 from public.transactions transaction
    join public.financial_accounts account on account.id=transaction.financial_account_id
    where transaction.id=transaction_documents.transaction_id
      and transaction.transaction_type='expense' and transaction.cancelled_at is null
      and public.can_manage_protected_person(account.protected_person_id)
  )
);
create policy transaction_documents_update_manage on public.transaction_documents
for update to authenticated using (exists (
  select 1 from public.transactions transaction
  join public.financial_accounts account on account.id=transaction.financial_account_id
  where transaction.id=transaction_documents.transaction_id
    and transaction.cancelled_at is null
    and public.can_manage_protected_person(account.protected_person_id)
)) with check (exists (
  select 1 from public.transactions transaction
  join public.financial_accounts account on account.id=transaction.financial_account_id
  where transaction.id=transaction_documents.transaction_id
    and transaction.transaction_type='expense' and transaction.cancelled_at is null
    and public.can_manage_protected_person(account.protected_person_id)
));

create function public.reject_cancelled_transaction_document_mutation()
returns trigger language plpgsql security definer set search_path='' as $$
declare target_transaction_id uuid:=case when tg_op='DELETE' then old.transaction_id else new.transaction_id end;
begin
  if exists(select 1 from public.transactions transaction
    where transaction.id=target_transaction_id and transaction.cancelled_at is not null) then
    raise exception using errcode='55000',
      message='Une opération annulée ne peut plus recevoir, remplacer ou supprimer de justificatif.';
  end if;
  return case when tg_op='DELETE' then old else new end;
end;
$$;
create trigger transaction_documents_reject_cancelled_mutation
before insert or update or delete on public.transaction_documents
for each row execute function public.reject_cancelled_transaction_document_mutation();
revoke all on function public.reject_cancelled_transaction_document_mutation()
from public, anon, authenticated, service_role;

comment on table public.transaction_proof_documents is
  'Identité logique stable d un justificatif rattaché à un épisode de dépense.';
comment on table public.transaction_proof_versions is
  'Versions physiques immuables des justificatifs, y compris chemins legacy conservés.';
comment on table public.transaction_proof_replacement_retirements is
  'Contrat de suppression sécurisée différée d une version volontairement remplacée; aucune suppression n est activée ici.';
