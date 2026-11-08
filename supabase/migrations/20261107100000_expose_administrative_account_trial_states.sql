-- PAT-ADMIN-USERS-04
-- Expose uniquement l'etat calcule des essais aux administrateurs de la
-- plateforme. Les tables techniques restent fermees et aucune mutation n'est
-- introduite.

create function public.list_administrative_account_trial_states(
  p_user_ids uuid[]
)
returns table (
  user_id uuid,
  state text,
  started_at timestamptz,
  ends_at timestamptz,
  deletion_eligible_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  observed_at timestamptz := statement_timestamp();
begin
  if auth.uid() is null or not exists (
    select 1
    from public.platform_administrators administrator
    where administrator.user_id = auth.uid()
  ) then
    raise exception using errcode = '42501', message = 'Acces administrateur requis.';
  end if;

  if p_user_ids is null
     or cardinality(p_user_ids) > 25
     or array_position(p_user_ids, null) is not null then
    raise exception using errcode = '22023', message = 'Liste de comptes invalide.';
  end if;

  return query
  select
    requested.user_id,
    trial_state.state,
    trial_state.started_at,
    trial_state.ends_at,
    trial_state.deletion_eligible_at
  from (
    select distinct requested_id as user_id
    from unnest(p_user_ids) requested_id
  ) requested
  join auth.users existing_user on existing_user.id = requested.user_id
  cross join lateral public.compute_account_trial_state(requested.user_id, observed_at) trial_state
  order by requested.user_id;
end;
$$;

revoke all on function public.list_administrative_account_trial_states(uuid[])
from public, anon, authenticated, service_role;

grant execute on function public.list_administrative_account_trial_states(uuid[])
to authenticated;

comment on function public.list_administrative_account_trial_states(uuid[]) is
  'Lecture paginee des etats d essai, reservee a un administrateur PatriGest authentifie.';
