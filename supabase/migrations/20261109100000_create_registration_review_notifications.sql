-- PAT-ADMIN-NOTIF-01
-- Suivi serveur des alertes envoyées à Jumeaweb après confirmation d'une
-- inscription autonome. Une ligne unique par demande empêche les doublons.

create table public.registration_review_notifications (
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
  constraint registration_review_notifications_sent_check check (
    (status = 'sent' and sent_at is not null)
    or (status <> 'sent' and sent_at is null)
  )
);

create trigger registration_review_notifications_set_updated_at
before update on public.registration_review_notifications
for each row execute function public.set_updated_at();

alter table public.registration_review_notifications enable row level security;

revoke all on table public.registration_review_notifications
from public, anon, authenticated, service_role;
grant select, insert, update on table public.registration_review_notifications
to service_role;

comment on table public.registration_review_notifications is
  'Registre serveur idempotent des alertes de nouvelles inscriptions autonomes confirmees.';
