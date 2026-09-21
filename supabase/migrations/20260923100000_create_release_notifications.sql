create table public.release_notifications (
  id uuid primary key default gen_random_uuid(),
  version text not null check (length(trim(version)) > 0),
  user_id uuid not null references auth.users(id) on delete cascade,
  email_snapshot text not null check (length(trim(email_snapshot)) > 0),
  delivery_kind text not null check (delivery_kind in ('test', 'global')),
  status text not null default 'pending' check (status in ('pending', 'sending', 'sent', 'failed')),
  provider_message_id text,
  attempt_count integer not null default 0 check (attempt_count >= 0),
  last_error_safe text,
  requested_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint release_notifications_sent_at_check
    check (status <> 'sent' or sent_at is not null)
);

create unique index release_notifications_global_version_user_idx
on public.release_notifications (version, user_id)
where delivery_kind = 'global';

create index release_notifications_version_status_idx
on public.release_notifications (version, delivery_kind, status);

create trigger release_notifications_set_updated_at
before update on public.release_notifications
for each row execute function public.set_updated_at();

alter table public.release_notifications enable row level security;

revoke all on public.release_notifications from public, anon, authenticated;
grant select, insert, update on public.release_notifications to service_role;

comment on table public.release_notifications is
  'Audit server-only des e-mails de release envoyés individuellement.';
