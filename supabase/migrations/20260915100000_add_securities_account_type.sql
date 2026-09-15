alter table public.financial_accounts
  drop constraint financial_accounts_account_type_check;

alter table public.financial_accounts
  add constraint financial_accounts_account_type_check check (
    account_type in (
      'checking',
      'livret_a',
      'ldds',
      'csl',
      'lep',
      'pel',
      'term_account',
      'life_insurance',
      'other_investment',
      'securities_account'
    )
  );

create or replace function public.manage_expense_proof_reference()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  person_id uuid;
  account_kind text;
begin
  select protected_person_id, account_type
  into person_id, account_kind
  from public.financial_accounts
  where id = new.financial_account_id;

  if person_id is null then
    raise exception 'Compte introuvable.';
  end if;

  if new.transaction_type in ('income', 'expense')
     and account_kind in ('life_insurance', 'other_investment', 'securities_account') then
    raise exception 'Les recettes et dépenses nécessitent un compte transactionnel.';
  end if;

  if tg_op = 'INSERT' then
    if new.transaction_type = 'expense' then
      new.proof_reference := public.next_proof_reference(person_id, new.transaction_date, new.id);
    else
      new.proof_reference := null;
    end if;
    return new;
  end if;

  if old.transaction_type = 'expense' and old.proof_reference is not null then
    if extract(year from new.transaction_date) <> extract(year from old.transaction_date) then
      raise exception 'Une dépense numérotée ne peut pas être déplacée vers une autre année.';
    end if;
    new.proof_reference := old.proof_reference;
  elsif new.transaction_type = 'expense' and old.transaction_type <> 'expense' then
    new.proof_reference := public.next_proof_reference(person_id, new.transaction_date, new.id);
  else
    new.proof_reference := null;
  end if;

  return new;
end;
$$;
