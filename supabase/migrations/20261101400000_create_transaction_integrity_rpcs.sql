create function public.financial_operation_actor_name(p_actor_id uuid)
returns text language sql stable security definer set search_path = '' as $$
  select coalesce((
    select nullif(btrim(concat_ws(' ', profile.first_name, profile.last_name)), '')
    from public.profiles profile where profile.id = p_actor_id
  ), 'Utilisateur PatriGest')
$$;

create function public.claim_financial_operation_request(
  p_actor_id uuid, p_request_id uuid, p_protected_person_id uuid,
  p_operation_kind text, p_intent jsonb
)
returns public.financial_operation_requests
language plpgsql security definer set search_path = '' as $$
declare request_row public.financial_operation_requests%rowtype;
begin
  if p_request_id is null then
    raise exception using errcode = '22023', message = 'L’identifiant de demande est obligatoire.';
  end if;
  insert into public.financial_operation_requests(
    requested_by, request_id, protected_person_id, operation_kind, intent
  ) values (p_actor_id, p_request_id, p_protected_person_id, p_operation_kind, p_intent)
  on conflict (requested_by, request_id) do nothing;

  select * into request_row from public.financial_operation_requests
  where requested_by = p_actor_id and request_id = p_request_id for update;
  if request_row.protected_person_id <> p_protected_person_id
     or request_row.operation_kind <> p_operation_kind
     or request_row.intent <> p_intent then
    raise exception using errcode = '23505', message = 'Cette clé d’idempotence correspond à une autre demande.';
  end if;
  return request_row;
end;
$$;

create function public.complete_financial_operation_request(
  p_actor_id uuid, p_request_id uuid, p_entity_type text, p_entity_id uuid, p_revision bigint
)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.financial_operation_requests set
    result_entity_type = p_entity_type, result_entity_id = p_entity_id,
    result_revision = p_revision, completed_at = clock_timestamp()
  where requested_by = p_actor_id and request_id = p_request_id and completed_at is null;
  if not found then
    raise exception using errcode = '55000', message = 'La demande financière ne peut pas être finalisée.';
  end if;
end;
$$;

create function public.invalidate_generated_management_reports_for_financial_dates(
  p_protected_person_id uuid, p_first_date date, p_second_date date default null
)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.management_reports report set refresh_required_at = clock_timestamp()
  where report.protected_person_id = p_protected_person_id
    and report.status = 'generated'
    and (
      p_first_date between report.period_start and report.period_end
      or (p_second_date is not null and p_second_date between report.period_start and report.period_end)
    );
end;
$$;

create function public.create_financial_transaction(
  p_protected_person_id uuid, p_financial_account_id uuid, p_transaction_date date,
  p_transaction_type text, p_label text, p_amount numeric, p_category_id uuid,
  p_official_category_id uuid, p_classification_precision text, p_comment text,
  p_request_id uuid
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); request_row public.financial_operation_requests%rowtype;
  intent jsonb; transaction_row public.transactions%rowtype; account_person_id uuid;
begin
  intent := jsonb_build_object('account',p_financial_account_id,'date',p_transaction_date,'type',p_transaction_type,
    'label',p_label,'amount',p_amount,'category',p_category_id,'officialCategory',p_official_category_id,
    'precision',p_classification_precision,'comment',p_comment);
  if actor_id is null or not public.can_manage_protected_person(p_protected_person_id) then
    raise exception using errcode = '42501', message = 'Dossier introuvable ou accès refusé.';
  end if;
  request_row := public.claim_financial_operation_request(actor_id,p_request_id,p_protected_person_id,'transaction_create',intent);
  if request_row.completed_at is not null then
    return jsonb_build_object('id',request_row.result_entity_id,'revision',request_row.result_revision,'replayed',true);
  end if;
  if p_transaction_type not in ('income','expense') then
    raise exception using errcode = '22023', message = 'Le type d’opération est invalide.';
  end if;
  if p_transaction_date > current_date then
    raise exception using errcode = '22007', message = 'La date d’une opération réelle ne peut pas être future.';
  end if;
  select protected_person_id into account_person_id from public.financial_accounts where id=p_financial_account_id;
  if account_person_id is distinct from p_protected_person_id then
    raise exception using errcode = '23503', message = 'Compte introuvable dans ce dossier.';
  end if;
  insert into public.transactions(
    financial_account_id,transaction_date,transaction_type,label,amount,category_id,
    accounting_nature,official_category_id,classification_precision,comment
  ) values (
    p_financial_account_id,p_transaction_date,p_transaction_type,btrim(p_label),p_amount,p_category_id,
    'ordinary',p_official_category_id,nullif(btrim(p_classification_precision),''),nullif(btrim(p_comment),'')
  ) returning * into transaction_row;
  perform public.complete_financial_operation_request(actor_id,p_request_id,'transaction',transaction_row.id,transaction_row.revision);
  return jsonb_build_object('id',transaction_row.id,'revision',transaction_row.revision,'replayed',false);
end;
$$;

create function public.correct_financial_transaction(
  p_protected_person_id uuid, p_transaction_id uuid, p_expected_revision bigint,
  p_financial_account_id uuid, p_transaction_date date, p_transaction_type text,
  p_label text, p_amount numeric, p_category_id uuid, p_official_category_id uuid,
  p_classification_precision text, p_comment text, p_reason text, p_request_id uuid
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid := auth.uid(); actor_name text; request_row public.financial_operation_requests%rowtype;
  intent jsonb; old_row public.transactions%rowtype; new_row public.transactions%rowtype;
  account_person_id uuid; change_id uuid := gen_random_uuid();
  bank_changed boolean; old_signed numeric; new_signed numeric;
begin
  intent := jsonb_build_object('transaction',p_transaction_id,'revision',p_expected_revision,'account',p_financial_account_id,
    'date',p_transaction_date,'type',p_transaction_type,'label',p_label,'amount',p_amount,'category',p_category_id,
    'officialCategory',p_official_category_id,'precision',p_classification_precision,'comment',p_comment,'reason',btrim(p_reason));
  if actor_id is null or not public.can_manage_protected_person(p_protected_person_id) then
    raise exception using errcode='42501', message='Dossier introuvable ou accès refusé.';
  end if;
  request_row := public.claim_financial_operation_request(actor_id,p_request_id,p_protected_person_id,'transaction_correct',intent);
  if request_row.completed_at is not null then
    return jsonb_build_object('id',request_row.result_entity_id,'revision',request_row.result_revision,'replayed',true);
  end if;
  if length(btrim(coalesce(p_reason,''))) < 3 then
    raise exception using errcode='22023', message='Le motif de correction est obligatoire.';
  end if;
  select transaction.* into old_row from public.transactions transaction
  join public.financial_accounts account on account.id=transaction.financial_account_id
  where transaction.id=p_transaction_id and account.protected_person_id=p_protected_person_id for update of transaction;
  if not found or old_row.transfer_id is not null then raise exception using errcode='P0002',message='Opération introuvable.'; end if;
  if old_row.cancelled_at is not null then raise exception using errcode='55000',message='Une opération annulée ne peut plus être corrigée.'; end if;
  if old_row.revision <> p_expected_revision then raise exception using errcode='40001',message='L’opération a été modifiée. Rechargez la page.'; end if;
  perform public.assert_no_active_transaction_document_operation(p_transaction_id);
  if p_transaction_type not in ('income','expense') then raise exception using errcode='22023',message='Le type d’opération est invalide.'; end if;
  if p_transaction_date > current_date then raise exception using errcode='22007',message='La date d’une opération réelle ne peut pas être future.'; end if;
  select protected_person_id into account_person_id from public.financial_accounts where id=p_financial_account_id;
  if account_person_id is distinct from p_protected_person_id then raise exception using errcode='23503',message='Compte introuvable dans ce dossier.'; end if;
  actor_name := public.financial_operation_actor_name(actor_id);
  update public.transactions set financial_account_id=p_financial_account_id,transaction_date=p_transaction_date,
    transaction_type=p_transaction_type,label=btrim(p_label),amount=p_amount,category_id=p_category_id,
    accounting_nature='ordinary',official_category_id=p_official_category_id,
    classification_precision=nullif(btrim(p_classification_precision),''),comment=nullif(btrim(p_comment),'')
  where id=p_transaction_id returning * into new_row;
  insert into public.transaction_changes(id,protected_person_id,transaction_id,request_id,change_kind,reason,
    revision_before,revision_after,previous_values,new_values,changed_by,changed_by_name)
  values(change_id,p_protected_person_id,p_transaction_id,p_request_id,'correction',btrim(p_reason),old_row.revision,
    new_row.revision,to_jsonb(old_row),to_jsonb(new_row),actor_id,actor_name);
  if old_row.transaction_type='expense' and new_row.transaction_type='income' then
    perform public.archive_current_transaction_proof(
      p_protected_person_id,p_transaction_id,change_id,actor_id,actor_name,
      'Conversion d’une dépense en recette'
    );
  end if;
  bank_changed := old_row.financial_account_id is distinct from new_row.financial_account_id
    or old_row.transaction_date is distinct from new_row.transaction_date
    or old_row.transaction_type is distinct from new_row.transaction_type
    or old_row.amount is distinct from new_row.amount;
  if bank_changed then
    old_signed := case old_row.transaction_type when 'income' then old_row.amount else -old_row.amount end;
    new_signed := case new_row.transaction_type when 'income' then new_row.amount else -new_row.amount end;
    insert into public.transaction_banking_impacts(protected_person_id,transaction_change_id,transaction_id,
      financial_account_id,effective_date,impact_kind,signed_amount) values
      (p_protected_person_id,change_id,p_transaction_id,old_row.financial_account_id,old_row.transaction_date,'reverse_previous',-old_signed),
      (p_protected_person_id,change_id,p_transaction_id,new_row.financial_account_id,new_row.transaction_date,'apply_current',new_signed);
  end if;
  perform public.invalidate_generated_management_reports_for_financial_dates(p_protected_person_id,old_row.transaction_date,new_row.transaction_date);
  perform public.complete_financial_operation_request(actor_id,p_request_id,'transaction',new_row.id,new_row.revision);
  return jsonb_build_object('id',new_row.id,'revision',new_row.revision,'replayed',false);
end;
$$;

create function public.cancel_financial_transaction(
  p_protected_person_id uuid, p_transaction_id uuid, p_expected_revision bigint,
  p_reason text, p_request_id uuid
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid:=auth.uid(); actor_name text; request_row public.financial_operation_requests%rowtype;
  intent jsonb; old_row public.transactions%rowtype; new_row public.transactions%rowtype; change_id uuid:=gen_random_uuid(); old_signed numeric;
begin
  intent:=jsonb_build_object('transaction',p_transaction_id,'revision',p_expected_revision,'reason',btrim(p_reason));
  if actor_id is null or not public.can_manage_protected_person(p_protected_person_id) then raise exception using errcode='42501',message='Dossier introuvable ou accès refusé.'; end if;
  request_row:=public.claim_financial_operation_request(actor_id,p_request_id,p_protected_person_id,'transaction_cancel',intent);
  if request_row.completed_at is not null then return jsonb_build_object('id',request_row.result_entity_id,'revision',request_row.result_revision,'replayed',true); end if;
  if length(btrim(coalesce(p_reason,'')))<3 then raise exception using errcode='22023',message='Le motif d’annulation est obligatoire.'; end if;
  select transaction.* into old_row from public.transactions transaction join public.financial_accounts account on account.id=transaction.financial_account_id
    where transaction.id=p_transaction_id and account.protected_person_id=p_protected_person_id for update of transaction;
  if not found or old_row.transfer_id is not null then raise exception using errcode='P0002',message='Opération introuvable.'; end if;
  if old_row.cancelled_at is not null then raise exception using errcode='55000',message='Cette opération est déjà annulée.'; end if;
  if old_row.revision<>p_expected_revision then raise exception using errcode='40001',message='L’opération a été modifiée. Rechargez la page.'; end if;
  perform public.assert_no_active_transaction_document_operation(p_transaction_id);
  actor_name:=public.financial_operation_actor_name(actor_id);
  update public.transactions set cancelled_at=clock_timestamp(),cancelled_by=actor_id where id=p_transaction_id returning * into new_row;
  insert into public.transaction_changes(id,protected_person_id,transaction_id,request_id,change_kind,reason,revision_before,revision_after,previous_values,new_values,changed_by,changed_by_name)
    values(change_id,p_protected_person_id,p_transaction_id,p_request_id,'cancellation',btrim(p_reason),old_row.revision,new_row.revision,to_jsonb(old_row),to_jsonb(new_row),actor_id,actor_name);
  old_signed:=case old_row.transaction_type when 'income' then old_row.amount else -old_row.amount end;
  insert into public.transaction_banking_impacts(protected_person_id,transaction_change_id,transaction_id,financial_account_id,effective_date,impact_kind,signed_amount)
    values(p_protected_person_id,change_id,p_transaction_id,old_row.financial_account_id,old_row.transaction_date,'reverse_previous',-old_signed);
  perform public.invalidate_generated_management_reports_for_financial_dates(p_protected_person_id,old_row.transaction_date);
  perform public.complete_financial_operation_request(actor_id,p_request_id,'transaction',new_row.id,new_row.revision);
  return jsonb_build_object('id',new_row.id,'revision',new_row.revision,'replayed',false);
end;
$$;

create function public.create_internal_transfer_v2(
  p_protected_person_id uuid,p_source_account_id uuid,p_destination_account_id uuid,
  p_transfer_date date,p_amount numeric,p_label text,p_comment text,p_request_id uuid
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid:=auth.uid(); request_row public.financial_operation_requests%rowtype; intent jsonb;
  transfer_row public.transfers%rowtype; account_count integer;
begin
  intent:=jsonb_build_object('source',p_source_account_id,'destination',p_destination_account_id,'date',p_transfer_date,'amount',p_amount,'label',p_label,'comment',p_comment);
  if actor_id is null or not public.can_manage_protected_person(p_protected_person_id) then raise exception using errcode='42501',message='Dossier introuvable ou accès refusé.'; end if;
  request_row:=public.claim_financial_operation_request(actor_id,p_request_id,p_protected_person_id,'transfer_create',intent);
  if request_row.completed_at is not null then return jsonb_build_object('id',request_row.result_entity_id,'revision',request_row.result_revision,'replayed',true); end if;
  if p_transfer_date>current_date then raise exception using errcode='22007',message='La date d’une opération réelle ne peut pas être future.'; end if;
  select count(*) into account_count from public.financial_accounts where protected_person_id=p_protected_person_id and id in(p_source_account_id,p_destination_account_id);
  if account_count<>2 or p_source_account_id=p_destination_account_id then raise exception using errcode='23503',message='Les comptes du virement sont invalides.'; end if;
  insert into public.transfers(protected_person_id,source_account_id,destination_account_id,transfer_date,amount,label,comment)
    values(p_protected_person_id,p_source_account_id,p_destination_account_id,p_transfer_date,p_amount,nullif(btrim(p_label),''),nullif(btrim(p_comment),'')) returning * into transfer_row;
  insert into public.transactions(financial_account_id,transaction_date,transaction_type,label,amount,transfer_id,comment)
    values(p_source_account_id,p_transfer_date,'transfer_out',coalesce(nullif(btrim(p_label),''),'Virement interne'),p_amount,transfer_row.id,nullif(btrim(p_comment),'')),
          (p_destination_account_id,p_transfer_date,'transfer_in',coalesce(nullif(btrim(p_label),''),'Virement interne'),p_amount,transfer_row.id,nullif(btrim(p_comment),''));
  perform public.complete_financial_operation_request(actor_id,p_request_id,'transfer',transfer_row.id,transfer_row.revision);
  return jsonb_build_object('id',transfer_row.id,'revision',transfer_row.revision,'replayed',false);
end;
$$;

create function public.correct_internal_transfer(
  p_protected_person_id uuid,p_transfer_id uuid,p_expected_revision bigint,
  p_source_account_id uuid,p_destination_account_id uuid,p_transfer_date date,p_amount numeric,
  p_label text,p_comment text,p_reason text,p_request_id uuid
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid:=auth.uid(); actor_name text; request_row public.financial_operation_requests%rowtype; intent jsonb;
  old_row public.transfers%rowtype; new_row public.transfers%rowtype; change_id uuid:=gen_random_uuid(); account_count integer; bank_changed boolean;
begin
  intent:=jsonb_build_object('transfer',p_transfer_id,'revision',p_expected_revision,'source',p_source_account_id,'destination',p_destination_account_id,'date',p_transfer_date,'amount',p_amount,'label',p_label,'comment',p_comment,'reason',btrim(p_reason));
  if actor_id is null or not public.can_manage_protected_person(p_protected_person_id) then raise exception using errcode='42501',message='Dossier introuvable ou accès refusé.'; end if;
  request_row:=public.claim_financial_operation_request(actor_id,p_request_id,p_protected_person_id,'transfer_correct',intent);
  if request_row.completed_at is not null then return jsonb_build_object('id',request_row.result_entity_id,'revision',request_row.result_revision,'replayed',true); end if;
  if length(btrim(coalesce(p_reason,'')))<3 then raise exception using errcode='22023',message='Le motif de correction est obligatoire.'; end if;
  select * into old_row from public.transfers where id=p_transfer_id and protected_person_id=p_protected_person_id for update;
  if not found then raise exception using errcode='P0002',message='Virement introuvable.'; end if;
  if old_row.cancelled_at is not null then raise exception using errcode='55000',message='Un virement annulé ne peut plus être corrigé.'; end if;
  if old_row.revision<>p_expected_revision then raise exception using errcode='40001',message='Le virement a été modifié. Rechargez la page.'; end if;
  if p_transfer_date>current_date then raise exception using errcode='22007',message='La date d’une opération réelle ne peut pas être future.'; end if;
  select count(*) into account_count from public.financial_accounts where protected_person_id=p_protected_person_id and id in(p_source_account_id,p_destination_account_id);
  if account_count<>2 or p_source_account_id=p_destination_account_id then raise exception using errcode='23503',message='Les comptes du virement sont invalides.'; end if;
  perform 1 from public.transactions where transfer_id=p_transfer_id for update;
  actor_name:=public.financial_operation_actor_name(actor_id);
  update public.transfers set source_account_id=p_source_account_id,destination_account_id=p_destination_account_id,
    transfer_date=p_transfer_date,amount=p_amount,label=nullif(btrim(p_label),''),comment=nullif(btrim(p_comment),'')
    where id=p_transfer_id returning * into new_row;
  update public.transactions set financial_account_id=case transaction_type when 'transfer_out' then p_source_account_id else p_destination_account_id end,
    transaction_date=p_transfer_date,label=coalesce(nullif(btrim(p_label),''),'Virement interne'),amount=p_amount,comment=nullif(btrim(p_comment),'')
    where transfer_id=p_transfer_id;
  insert into public.transfer_changes(id,protected_person_id,transfer_id,request_id,change_kind,reason,revision_before,revision_after,previous_values,new_values,changed_by,changed_by_name)
    values(change_id,p_protected_person_id,p_transfer_id,p_request_id,'correction',btrim(p_reason),old_row.revision,new_row.revision,to_jsonb(old_row),to_jsonb(new_row),actor_id,actor_name);
  bank_changed:=old_row.source_account_id is distinct from new_row.source_account_id or old_row.destination_account_id is distinct from new_row.destination_account_id or old_row.transfer_date is distinct from new_row.transfer_date or old_row.amount is distinct from new_row.amount;
  if bank_changed then
    insert into public.transaction_banking_impacts(protected_person_id,transfer_change_id,transfer_id,financial_account_id,effective_date,impact_kind,signed_amount) values
      (p_protected_person_id,change_id,p_transfer_id,old_row.source_account_id,old_row.transfer_date,'reverse_previous',old_row.amount),
      (p_protected_person_id,change_id,p_transfer_id,old_row.destination_account_id,old_row.transfer_date,'reverse_previous',-old_row.amount),
      (p_protected_person_id,change_id,p_transfer_id,new_row.source_account_id,new_row.transfer_date,'apply_current',-new_row.amount),
      (p_protected_person_id,change_id,p_transfer_id,new_row.destination_account_id,new_row.transfer_date,'apply_current',new_row.amount);
  end if;
  perform public.invalidate_generated_management_reports_for_financial_dates(p_protected_person_id,old_row.transfer_date,new_row.transfer_date);
  perform public.complete_financial_operation_request(actor_id,p_request_id,'transfer',new_row.id,new_row.revision);
  return jsonb_build_object('id',new_row.id,'revision',new_row.revision,'replayed',false);
end;
$$;

create function public.cancel_internal_transfer_v2(
  p_protected_person_id uuid,p_transfer_id uuid,p_expected_revision bigint,p_reason text,p_request_id uuid
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor_id uuid:=auth.uid(); actor_name text; request_row public.financial_operation_requests%rowtype; intent jsonb;
  old_row public.transfers%rowtype; new_row public.transfers%rowtype; change_id uuid:=gen_random_uuid(); cancelled_time timestamptz:=clock_timestamp();
begin
  intent:=jsonb_build_object('transfer',p_transfer_id,'revision',p_expected_revision,'reason',btrim(p_reason));
  if actor_id is null or not public.can_manage_protected_person(p_protected_person_id) then raise exception using errcode='42501',message='Dossier introuvable ou accès refusé.'; end if;
  request_row:=public.claim_financial_operation_request(actor_id,p_request_id,p_protected_person_id,'transfer_cancel',intent);
  if request_row.completed_at is not null then return jsonb_build_object('id',request_row.result_entity_id,'revision',request_row.result_revision,'replayed',true); end if;
  if length(btrim(coalesce(p_reason,'')))<3 then raise exception using errcode='22023',message='Le motif d’annulation est obligatoire.'; end if;
  select * into old_row from public.transfers where id=p_transfer_id and protected_person_id=p_protected_person_id for update;
  if not found then raise exception using errcode='P0002',message='Virement introuvable.'; end if;
  if old_row.cancelled_at is not null then raise exception using errcode='55000',message='Ce virement est déjà annulé.'; end if;
  if old_row.revision<>p_expected_revision then raise exception using errcode='40001',message='Le virement a été modifié. Rechargez la page.'; end if;
  perform 1 from public.transactions where transfer_id=p_transfer_id for update;
  actor_name:=public.financial_operation_actor_name(actor_id);
  update public.transfers set cancelled_at=cancelled_time,cancelled_by=actor_id where id=p_transfer_id returning * into new_row;
  update public.transactions set cancelled_at=cancelled_time,cancelled_by=actor_id where transfer_id=p_transfer_id;
  insert into public.transfer_changes(id,protected_person_id,transfer_id,request_id,change_kind,reason,revision_before,revision_after,previous_values,new_values,changed_by,changed_by_name)
    values(change_id,p_protected_person_id,p_transfer_id,p_request_id,'cancellation',btrim(p_reason),old_row.revision,new_row.revision,to_jsonb(old_row),to_jsonb(new_row),actor_id,actor_name);
  insert into public.transaction_banking_impacts(protected_person_id,transfer_change_id,transfer_id,financial_account_id,effective_date,impact_kind,signed_amount) values
    (p_protected_person_id,change_id,p_transfer_id,old_row.source_account_id,old_row.transfer_date,'reverse_previous',old_row.amount),
    (p_protected_person_id,change_id,p_transfer_id,old_row.destination_account_id,old_row.transfer_date,'reverse_previous',-old_row.amount);
  perform public.invalidate_generated_management_reports_for_financial_dates(p_protected_person_id,old_row.transfer_date);
  perform public.complete_financial_operation_request(actor_id,p_request_id,'transfer',new_row.id,new_row.revision);
  return jsonb_build_object('id',new_row.id,'revision',new_row.revision,'replayed',false);
end;
$$;

revoke all on function public.financial_operation_actor_name(uuid) from public,anon,authenticated,service_role;
revoke all on function public.claim_financial_operation_request(uuid,uuid,uuid,text,jsonb) from public,anon,authenticated,service_role;
revoke all on function public.complete_financial_operation_request(uuid,uuid,text,uuid,bigint) from public,anon,authenticated,service_role;
revoke all on function public.invalidate_generated_management_reports_for_financial_dates(uuid,date,date) from public,anon,authenticated,service_role;

revoke all on function public.create_financial_transaction(uuid,uuid,date,text,text,numeric,uuid,uuid,text,text,uuid) from public,anon,authenticated,service_role;
revoke all on function public.correct_financial_transaction(uuid,uuid,bigint,uuid,date,text,text,numeric,uuid,uuid,text,text,text,uuid) from public,anon,authenticated,service_role;
revoke all on function public.cancel_financial_transaction(uuid,uuid,bigint,text,uuid) from public,anon,authenticated,service_role;
revoke all on function public.create_internal_transfer_v2(uuid,uuid,uuid,date,numeric,text,text,uuid) from public,anon,authenticated,service_role;
revoke all on function public.correct_internal_transfer(uuid,uuid,bigint,uuid,uuid,date,numeric,text,text,text,uuid) from public,anon,authenticated,service_role;
revoke all on function public.cancel_internal_transfer_v2(uuid,uuid,bigint,text,uuid) from public,anon,authenticated,service_role;

grant execute on function public.create_financial_transaction(uuid,uuid,date,text,text,numeric,uuid,uuid,text,text,uuid) to authenticated;
grant execute on function public.correct_financial_transaction(uuid,uuid,bigint,uuid,date,text,text,numeric,uuid,uuid,text,text,text,uuid) to authenticated;
grant execute on function public.cancel_financial_transaction(uuid,uuid,bigint,text,uuid) to authenticated;
grant execute on function public.create_internal_transfer_v2(uuid,uuid,uuid,date,numeric,text,text,uuid) to authenticated;
grant execute on function public.correct_internal_transfer(uuid,uuid,bigint,uuid,uuid,date,numeric,text,text,text,uuid) to authenticated;
grant execute on function public.cancel_internal_transfer_v2(uuid,uuid,bigint,text,uuid) to authenticated;
