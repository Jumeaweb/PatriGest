create or replace function public.get_infrastructure_usage_metrics()
returns table (
  database_size_bytes bigint,
  storage_size_bytes bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    pg_database_size(current_database())::bigint,
    coalesce(sum(
      case
        when objects.metadata ->> 'size' ~ '^\d+$'
          then (objects.metadata ->> 'size')::bigint
        else 0
      end
    ), 0)::bigint
  from storage.objects as objects;
$$;

revoke all on function public.get_infrastructure_usage_metrics() from public, anon, authenticated;
grant execute on function public.get_infrastructure_usage_metrics() to service_role;

comment on function public.get_infrastructure_usage_metrics() is
  'Métriques agrégées server-only pour la supervision platform_admin.';
