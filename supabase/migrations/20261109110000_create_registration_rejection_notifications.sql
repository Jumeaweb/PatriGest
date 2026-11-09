-- PAT-INSCRIPTION-REFUS-01
-- Registre prive et idempotent des notifications envoyees apres le refus
-- administratif d'une inscription autonome.

create table public.registration_rejection_notifications (
  user_id uuid primary key references auth.users(id) on delete cascade,
  status text not null default 'sending'
    check (status in ('sending', 'sent', 'failed')),
  attempt_count integer not null default 1 check (attempt_count > 0),
  provider_message_id text,
  last_error_safe text,
  last_attempt_at timestamptz not null default clock_timestamp(),
  sent_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint registration_rejection_notifications_sent_check check (
    (status = 'sent' and sent_at is not null)
    or (status <> 'sent' and sent_at is null)
  )
);

create trigger registration_rejection_notifications_set_updated_at
before update on public.registration_rejection_notifications
for each row execute function public.set_updated_at();

alter table public.registration_rejection_notifications enable row level security;

revoke all on table public.registration_rejection_notifications
from public, anon, authenticated, service_role;
grant select, insert, update on table public.registration_rejection_notifications
to service_role;

comment on table public.registration_rejection_notifications is
  'Registre serveur idempotent des notifications de refus des inscriptions autonomes.';
