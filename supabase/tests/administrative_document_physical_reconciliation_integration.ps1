param([string]$ContainerName = "supabase_db_PatriGest", [string]$SupabaseCli = "")
$ErrorActionPreference = "Stop"
$docker = (Get-Command docker -ErrorAction Stop).Source
$utf8 = [System.Text.UTF8Encoding]::new($false)
if (-not $SupabaseCli) {
  $installed = Get-Command supabase -ErrorAction SilentlyContinue
  if ($installed) { $SupabaseCli = $installed.Source } else {
    $npmCache = Join-Path $env:USERPROFILE "AppData\Local\npm-cache"
    $SupabaseCli = Get-ChildItem -LiteralPath "$npmCache\_npx" -Recurse -Filter "supabase.exe" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
  }
}
if (-not $SupabaseCli) { throw "CLI Supabase introuvable." }
function Invoke-Psql([string]$Sql) {
  $start = [System.Diagnostics.ProcessStartInfo]::new($docker, "exec -i `"$ContainerName`" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -At -f -")
  $start.UseShellExecute=$false; $start.CreateNoWindow=$true; $start.RedirectStandardInput=$true; $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
  $start.StandardInputEncoding=$utf8; $start.StandardOutputEncoding=$utf8; $start.StandardErrorEncoding=$utf8
  $process=[System.Diagnostics.Process]::new(); $process.StartInfo=$start; [void]$process.Start(); $process.StandardInput.Write($Sql); $process.StandardInput.Close()
  $output=$process.StandardOutput.ReadToEnd(); $errors=$process.StandardError.ReadToEnd(); $process.WaitForExit(); if($process.ExitCode -ne 0){throw $errors}; $output.Trim()
}
$status=& $SupabaseCli status -o env 2>$null; $config=@{}; foreach($line in $status){if($line -match '^([A-Z0-9_]+)="?(.*?)"?$'){$config[$Matches[1]]=$Matches[2].TrimEnd('"')}}
foreach($required in @("API_URL","ANON_KEY","SERVICE_ROLE_KEY","DB_URL")){if(-not $config.ContainsKey($required)){throw "Configuration Supabase locale incomplète."}}
$api=[Uri]$config.API_URL; $db=[Uri]$config.DB_URL
if($api.Scheme -ne "http" -or $api.Host -notin @("127.0.0.1","localhost") -or $api.Port -ne 54321){throw "Refus hors API locale."}
if($db.Host -notin @("127.0.0.1","localhost") -or $db.Port -ne 54322){throw "Refus hors PostgreSQL local."}
$preexistingData = Invoke-Psql @"
select case when
  exists(select 1 from auth.users)
  or exists(select 1 from storage.objects)
  or exists(select 1 from public.protected_persons)
  or exists(select 1 from public.document_operations)
then 1 else 0 end;
"@
if($preexistingData -ne "0"){
  throw "Le harnais exige une instance locale jetable sans données préexistantes et refuse de la réinitialiser."
}
$admin="99760000-0000-4000-8000-000000000001"; $owner="99760000-0000-4000-8000-000000000002"; $person="99760000-0000-4000-8000-000000000003"; $password="Local-only-physical-reconciliation!"
try {
  & $SupabaseCli db reset --local --no-seed | Out-Null
  if($LASTEXITCODE -ne 0){throw "Impossible de préparer la base locale isolée."}
  Invoke-Psql @"
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,confirmation_token,recovery_token,email_change_token_new,email_change,email_change_token_current,reauthentication_token,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values
('00000000-0000-0000-0000-000000000000','$admin','authenticated','authenticated','physical-reconciliation-admin@example.test',extensions.crypt('$password',extensions.gen_salt('bf')),now(),'','','','','','','{`"provider`":`"email`",`"providers`" : [`"email`"]}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','$owner','authenticated','authenticated','physical-reconciliation-owner@example.test',extensions.crypt('$password',extensions.gen_salt('bf')),now(),'','','','','','','{`"provider`":`"email`",`"providers`" : [`"email`"]}','{}',now(),now());
insert into auth.identities(id,user_id,provider_id,identity_data,provider,last_sign_in_at,created_at,updated_at)
values
(gen_random_uuid(),'$admin','physical-reconciliation-admin@example.test',jsonb_build_object('sub','$admin','email','physical-reconciliation-admin@example.test'),'email',now(),now(),now()),
(gen_random_uuid(),'$owner','physical-reconciliation-owner@example.test',jsonb_build_object('sub','$owner','email','physical-reconciliation-owner@example.test'),'email',now(),now(),now());
update public.application_user_authorizations set status='active',status_changed_at=now(),account_mode='autonomous' where user_id in ('$admin','$owner');
insert into public.platform_administrators(user_id) values('$admin');
insert into public.account_subscriptions(owner_id,status,started_at) values('$owner','development',now());
insert into public.protected_persons(id,owner_id,first_name,last_name) values('$person','$owner','Réconciliation','Locale');
"@ | Out-Null
  $env:PAT_TEST_SUPABASE_URL=$config.API_URL; $env:PAT_TEST_SUPABASE_ANON_KEY=$config.ANON_KEY; $env:PAT_TEST_SUPABASE_SERVICE_ROLE_KEY=$config.SERVICE_ROLE_KEY; $env:PAT_TEST_PASSWORD=$password
  $seedRaw=node --experimental-strip-types "supabase/tests/administrative_document_physical_reconciliation_integration.mjs" seed
  if($LASTEXITCODE -ne 0){throw "Échec de préparation Storage locale."}
  $seed=$seedRaw | ConvertFrom-Json
  $env:PAT_TEST_PRESENT_OBJECT_ID=$seed.present.id
  $env:PAT_TEST_CONCURRENT_OBJECT_ID=$seed.concurrent.id
  Invoke-Psql @"
insert into storage.objects(id,bucket_id,name,metadata,version,owner_id)
values('99760000-0000-4000-8100-000000000002','transaction-proofs','legacy/reconciliation-catalog-only','{`"size`":16,`"mimetype`":`"application/pdf`"}','catalog-only-v1','$admin');
insert into public.document_operations(id,protected_person_id,initiated_by,initiator_subject_id,initiator_kind,workflow,business_entity_type,business_entity_id,client_request_id,state,target_signature,closed_at)
values
('99760000-0000-4000-8200-000000000001','$person','$admin','$admin','platform_admin','administrative_repair','transaction',gen_random_uuid(),gen_random_uuid(),'completed','[]',now()),
('99760000-0000-4000-8200-000000000002','$person','$admin','$admin','platform_admin','administrative_repair','transaction',gen_random_uuid(),gen_random_uuid(),'completed','[]',now());
insert into public.document_operation_targets(id,operation_id,ordinal,bucket_id,object_path,target_role,forward_action,compensation_action,expected_exists,expected_object_id,expected_object_version,expected_snapshot_captured_at,application_state,applied_object_id,applied_object_version,applied_at)
values
('99760000-0000-4000-8300-000000000001','99760000-0000-4000-8200-000000000001',1,'transaction-proofs','protected-persons/$person/transactions/99760000-0000-4000-8400-000000000001/proof','primary','update','update',true,gen_random_uuid(),'original-v1',now(),'applied',gen_random_uuid(),'applied-v1',now()),
('99760000-0000-4000-8300-000000000002','99760000-0000-4000-8200-000000000002',1,'transaction-proofs','protected-persons/$person/transactions/99760000-0000-4000-8400-000000000002/proof','primary','update','update',true,gen_random_uuid(),'original-v1',now(),'applied',gen_random_uuid(),'applied-v1',now());
insert into public.document_operation_backups(id,operation_id,target_id,protected_person_id,initiator_subject_id,original_bucket_id,original_object_path,original_object_id,original_object_version,recovery_object_path,byte_size,mime_type,sha256,state,recovery_object_id,recovery_object_version,upload_verified_at)
values
('99760000-0000-4000-8500-000000000001','99760000-0000-4000-8200-000000000001','99760000-0000-4000-8300-000000000001','$person','$admin','transaction-proofs','protected-persons/$person/transactions/99760000-0000-4000-8400-000000000001/proof',gen_random_uuid(),'original-v1','operations/99760000-0000-4000-8200-000000000001/targets/99760000-0000-4000-8300-000000000001/backup',$($seed.validBackup.size),'application/pdf','$($seed.validBackup.sha256)','verified','$($seed.validBackup.id)','$($seed.validBackup.version)',now()),
('99760000-0000-4000-8500-000000000002','99760000-0000-4000-8200-000000000002','99760000-0000-4000-8300-000000000002','$person','$admin','transaction-proofs','protected-persons/$person/transactions/99760000-0000-4000-8400-000000000002/proof',gen_random_uuid(),'original-v1','operations/99760000-0000-4000-8200-000000000002/targets/99760000-0000-4000-8300-000000000002/backup',$($seed.divergentBackup.size),'application/pdf','$('0'*64)','verified','$($seed.divergentBackup.id)','$($seed.divergentBackup.version)',now());
"@ | Out-Null
  node --experimental-strip-types "supabase/tests/administrative_document_physical_reconciliation_integration.mjs" execute
  if($LASTEXITCODE -ne 0){throw "Échec du harnais de réconciliation physique."}
} finally {
  Remove-Item Env:PAT_TEST_SUPABASE_URL,Env:PAT_TEST_SUPABASE_ANON_KEY,Env:PAT_TEST_SUPABASE_SERVICE_ROLE_KEY,Env:PAT_TEST_PASSWORD,Env:PAT_TEST_PRESENT_OBJECT_ID,Env:PAT_TEST_CONCURRENT_OBJECT_ID -ErrorAction SilentlyContinue
  & $SupabaseCli db reset --local --no-seed | Out-Null
  if($LASTEXITCODE -ne 0){Write-Warning "La reconstruction de nettoyage Supabase local a échoué."}
}
