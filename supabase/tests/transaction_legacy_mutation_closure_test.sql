begin;
create extension if not exists pgtap with schema extensions;
select plan(31);

select extensions.ok(not has_table_privilege('authenticated', 'public.transactions', 'INSERT'), 'authenticated ne peut plus inserer directement une operation');
select extensions.ok(not has_table_privilege('authenticated', 'public.transactions', 'UPDATE'), 'authenticated ne peut plus corriger directement une operation');
select extensions.ok(not has_table_privilege('authenticated', 'public.transactions', 'DELETE'), 'authenticated ne peut plus supprimer physiquement une operation');
select extensions.ok(has_table_privilege('authenticated', 'public.transactions', 'SELECT'), 'la consultation des operations reste autorisee');

select extensions.ok(not has_table_privilege('anon', 'public.transactions', 'INSERT'), 'anon ne peut pas inserer directement une operation');
select extensions.ok(not has_table_privilege('anon', 'public.transactions', 'UPDATE'), 'anon ne peut pas corriger directement une operation');
select extensions.ok(not has_table_privilege('anon', 'public.transactions', 'DELETE'), 'anon ne peut pas supprimer directement une operation');
select extensions.ok(not has_table_privilege('service_role', 'public.transactions', 'INSERT'), 'service_role ne peut pas inserer directement une operation');
select extensions.ok(not has_table_privilege('service_role', 'public.transactions', 'UPDATE'), 'service_role ne peut pas corriger directement une operation');
select extensions.ok(not has_table_privilege('service_role', 'public.transactions', 'DELETE'), 'service_role ne peut pas supprimer directement une operation');
select extensions.ok(not exists (
  select 1
  from aclexplode(coalesce((select relacl from pg_class where oid = 'public.transactions'::regclass), acldefault('r', (select relowner from pg_class where oid = 'public.transactions'::regclass)))) acl
  where acl.grantee = 0 and acl.privilege_type = 'INSERT'
), 'PUBLIC ne dispose pas du privilege direct INSERT');
select extensions.ok(not exists (
  select 1
  from aclexplode(coalesce((select relacl from pg_class where oid = 'public.transactions'::regclass), acldefault('r', (select relowner from pg_class where oid = 'public.transactions'::regclass)))) acl
  where acl.grantee = 0 and acl.privilege_type = 'UPDATE'
), 'PUBLIC ne dispose pas du privilege direct UPDATE');
select extensions.ok(not exists (
  select 1
  from aclexplode(coalesce((select relacl from pg_class where oid = 'public.transactions'::regclass), acldefault('r', (select relowner from pg_class where oid = 'public.transactions'::regclass)))) acl
  where acl.grantee = 0 and acl.privilege_type = 'DELETE'
), 'PUBLIC ne dispose pas du privilege direct DELETE');

select extensions.ok(not has_function_privilege('authenticated', 'public.create_internal_transfer(uuid,uuid,uuid,date,numeric,text,text)', 'EXECUTE'), 'ancienne creation de virement fermee');
select extensions.ok(not has_function_privilege('authenticated', 'public.delete_internal_transfer(uuid)', 'EXECUTE'), 'ancienne suppression de virement fermee');
select extensions.ok(not has_function_privilege('authenticated', 'public.delete_transaction_with_document(uuid)', 'EXECUTE'), 'ancienne suppression physique avec document fermee');
select extensions.ok(not has_function_privilege('anon', 'public.delete_internal_transfer(uuid)', 'EXECUTE'), 'ancienne suppression de virement fermee a anon');
select extensions.ok(not has_function_privilege('service_role', 'public.delete_internal_transfer(uuid)', 'EXECUTE'), 'ancienne suppression de virement sans exemption service_role');
select extensions.ok(not has_function_privilege('anon', 'public.create_internal_transfer(uuid,uuid,uuid,date,numeric,text,text)', 'EXECUTE'), 'ancienne creation de virement fermee a anon');
select extensions.ok(not has_function_privilege('service_role', 'public.create_internal_transfer(uuid,uuid,uuid,date,numeric,text,text)', 'EXECUTE'), 'ancienne creation de virement fermee a service_role');
select extensions.ok(not has_function_privilege('anon', 'public.delete_transaction_with_document(uuid)', 'EXECUTE'), 'ancienne suppression physique fermee a anon');
select extensions.ok(not has_function_privilege('service_role', 'public.delete_transaction_with_document(uuid)', 'EXECUTE'), 'ancienne suppression physique fermee a service_role');

select extensions.ok(has_function_privilege('authenticated', 'public.create_financial_transaction(uuid,uuid,date,text,text,numeric,uuid,uuid,text,text,uuid)', 'EXECUTE'), 'creation auditee conservee');
select extensions.ok(has_function_privilege('authenticated', 'public.correct_financial_transaction(uuid,uuid,bigint,uuid,date,text,text,numeric,uuid,uuid,text,text,text,uuid)', 'EXECUTE'), 'correction auditee conservee');
select extensions.ok(has_function_privilege('authenticated', 'public.cancel_financial_transaction(uuid,uuid,bigint,text,uuid)', 'EXECUTE'), 'annulation auditee conservee');
select extensions.ok(has_function_privilege('authenticated', 'public.create_internal_transfer_v2(uuid,uuid,uuid,date,numeric,text,text,uuid)', 'EXECUTE'), 'creation idempotente de virement conservee');
select extensions.ok(has_function_privilege('authenticated', 'public.correct_internal_transfer(uuid,uuid,bigint,uuid,uuid,date,numeric,text,text,text,uuid)', 'EXECUTE'), 'correction atomique de virement conservee');
select extensions.ok(has_function_privilege('authenticated', 'public.cancel_internal_transfer_v2(uuid,uuid,bigint,text,uuid)', 'EXECUTE'), 'annulation atomique de virement conservee');

select extensions.ok(not has_function_privilege('anon', 'public.create_financial_transaction(uuid,uuid,date,text,text,numeric,uuid,uuid,text,text,uuid)', 'EXECUTE'), 'anon ne peut pas appeler la creation auditee');
select extensions.ok(not has_function_privilege('service_role', 'public.create_financial_transaction(uuid,uuid,date,text,text,numeric,uuid,uuid,text,text,uuid)', 'EXECUTE'), 'service_role ne contourne pas l autorisation metier de creation');
select extensions.ok(not exists (
  select 1 from aclexplode(coalesce(
    (select proacl from pg_proc where oid = 'public.create_financial_transaction(uuid,uuid,date,text,text,numeric,uuid,uuid,text,text,uuid)'::regprocedure),
    acldefault('f', (select proowner from pg_proc where oid = 'public.create_financial_transaction(uuid,uuid,date,text,text,numeric,uuid,uuid,text,text,uuid)'::regprocedure))
  )) acl where acl.grantee = 0 and acl.privilege_type = 'EXECUTE'
), 'PUBLIC ne peut pas appeler la creation auditee');

select * from extensions.finish();
rollback;
