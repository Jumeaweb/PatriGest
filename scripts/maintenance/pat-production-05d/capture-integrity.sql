\set ON_ERROR_STOP on

begin;

create temporary table maintenance_integrity_snapshot (
  scope text not null,
  object_name text not null,
  row_count bigint not null,
  content_fingerprint text not null
);

do $capture_public_tables$
declare
  table_record record;
  table_count bigint;
  table_fingerprint text;
begin
  for table_record in
    select schemaname, tablename
    from pg_tables
    where schemaname = 'public'
    order by tablename
  loop
    execute format(
      'select count(*), md5(coalesce(string_agg(row_hash, '','' order by row_hash), ''''))
       from (
         select md5(to_jsonb(source_row)::text) row_hash
         from %I.%I source_row
       ) hashed_rows',
      table_record.schemaname,
      table_record.tablename
    )
    into table_count, table_fingerprint;

    insert into maintenance_integrity_snapshot
    values ('table', table_record.tablename, table_count, table_fingerprint);
  end loop;
end;
$capture_public_tables$;

insert into maintenance_integrity_snapshot (
  scope,
  object_name,
  row_count,
  content_fingerprint
)
select
  'storage',
  bucket_id,
  count(*),
  md5(coalesce(string_agg(
    md5(concat_ws('|', id::text, name, owner_id::text, version, metadata::text)),
    ',' order by id
  ), ''))
from storage.objects
group by bucket_id;

select
  scope,
  object_name,
  row_count,
  content_fingerprint
from maintenance_integrity_snapshot
order by scope, object_name;

commit;
