begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(8);

select extensions.has_function('public', 'get_infrastructure_usage_metrics', array[]::text[], 'infrastructure metrics function exists');
select extensions.ok(not has_function_privilege('anon', 'public.get_infrastructure_usage_metrics()', 'EXECUTE'), 'anon cannot execute infrastructure metrics');
select extensions.ok(not has_function_privilege('authenticated', 'public.get_infrastructure_usage_metrics()', 'EXECUTE'), 'authenticated cannot execute infrastructure metrics');
select extensions.ok(has_function_privilege('service_role', 'public.get_infrastructure_usage_metrics()', 'EXECUTE'), 'service role can execute infrastructure metrics');

insert into storage.buckets (id, name, public)
values ('infrastructure-test', 'infrastructure-test', false)
on conflict (id) do nothing;

insert into storage.objects (id, bucket_id, name, metadata)
values ('27000000-0000-4000-8000-000000000001', 'infrastructure-test', 'aggregate-size.bin', '{"size":12345}'::jsonb);

set local role service_role;

select extensions.is((select count(*) from public.get_infrastructure_usage_metrics()), 1::bigint, 'function returns one aggregate row');
select extensions.ok((select database_size_bytes > 0 from public.get_infrastructure_usage_metrics()), 'database size is positive');
select extensions.ok((select storage_size_bytes >= 12345 from public.get_infrastructure_usage_metrics()), 'storage size includes object metadata');
select extensions.is((select pg_typeof(storage_size_bytes)::text from public.get_infrastructure_usage_metrics()), 'bigint', 'storage aggregate is a bigint');

select * from extensions.finish();
rollback;
