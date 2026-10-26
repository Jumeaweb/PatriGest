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
$admin="9b500000-0000-4000-8000-000000000001"; $owner="9b500000-0000-4000-8000-000000000002"; $person="9b500000-0000-4000-8100-000000000001"
$operations=1..3|ForEach-Object{"9b500000-0000-4000-8200-{0:D12}" -f $_}; $targets=1..3|ForEach-Object{"9b500000-0000-4000-8500-{0:D12}" -f $_}; $transactions=1..3|ForEach-Object{"9b500000-0000-4000-8300-{0:D12}" -f $_}; $backups=1..3|ForEach-Object{"9b500000-0000-4000-8800-{0:D12}" -f $_}
$password="Local-only-repair-3H2C4B2!"
$cleanup=@"
select set_config('storage.allow_delete_query','true',false);
delete from storage.objects where name like 'protected-persons/$person/%' or name like 'operations/9b500000-%';
select set_config('storage.allow_delete_query','false',false);
delete from public.document_repair_events where operation_id in ('$($operations -join "','")');
delete from public.document_repair_observations where operation_id in ('$($operations -join "','")');
delete from public.document_repair_items where operation_id in ('$($operations -join "','")');
delete from public.document_repair_authorizations where operation_id in ('$($operations -join "','")');
delete from public.document_operation_backups where operation_id in ('$($operations -join "','")');
delete from public.document_object_locks where operation_id in ('$($operations -join "','")');
delete from public.document_operation_events where operation_id in ('$($operations -join "','")');
delete from public.document_operation_targets where operation_id in ('$($operations -join "','")');
delete from public.document_operations where id in ('$($operations -join "','")');
delete from public.protected_person_access where protected_person_id='$person'; delete from public.protected_persons where id='$person';
delete from public.platform_administrators where user_id in ('$admin','$owner'); delete from public.account_subscriptions where owner_id='$owner'; delete from auth.users where id in ('$admin','$owner');
"@
try {
  try { Invoke-Psql $cleanup|Out-Null } catch {
    # Une exécution interrompue peut avoir laissé des preuves append-only.
    # On repart alors d'une reconstruction locale vérifiée plutôt que de
    # désactiver leurs triggers d'immuabilité.
    & $SupabaseCli db reset --local --no-seed | Out-Null
    if($LASTEXITCODE -ne 0){throw "Impossible de préparer une base Supabase locale isolée."}
  }
  Invoke-Psql @"
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,confirmation_token,recovery_token,email_change_token_new,email_change,email_change_token_current,reauthentication_token,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('00000000-0000-0000-0000-000000000000','$admin','authenticated','authenticated','repair-physical-admin@example.test',extensions.crypt('$password',extensions.gen_salt('bf')),now(),'','','','','','','{`"provider`":`"email`",`"providers`" : [`"email`"]}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','$owner','authenticated','authenticated','repair-physical-owner@example.test',extensions.crypt('$password',extensions.gen_salt('bf')),now(),'','','','','','','{`"provider`":`"email`",`"providers`" : [`"email`"]}','{}',now(),now());
insert into auth.identities(id,user_id,provider_id,identity_data,provider,last_sign_in_at,created_at,updated_at) values
(gen_random_uuid(),'$admin','repair-physical-admin@example.test',jsonb_build_object('sub','$admin','email','repair-physical-admin@example.test'),'email',now(),now(),now()),
(gen_random_uuid(),'$owner','repair-physical-owner@example.test',jsonb_build_object('sub','$owner','email','repair-physical-owner@example.test'),'email',now(),now(),now());
update public.application_user_authorizations set status='active',status_changed_at=now(),account_mode='autonomous' where user_id in('$admin','$owner');
insert into public.platform_administrators(user_id) values('$admin'); insert into public.account_subscriptions(owner_id,status,started_at) values('$owner','development',now());
insert into public.protected_persons(id,owner_id,first_name,last_name) values('$person','$owner','Réparation','Locale');
"@|Out-Null
  $env:PAT_TEST_SUPABASE_URL=$config.API_URL; $env:PAT_TEST_SUPABASE_ANON_KEY=$config.ANON_KEY; $env:PAT_TEST_SUPABASE_SERVICE_ROLE_KEY=$config.SERVICE_ROLE_KEY; $env:PAT_TEST_PASSWORD=$password
  $seedRaw=node --experimental-strip-types "supabase/tests/administrative_document_repair_integration.mjs" seed
  if($LASTEXITCODE -ne 0){throw "Échec de préparation Storage locale."}
  $seed=$seedRaw|ConvertFrom-Json
  foreach($case in @('restore','divergent')){foreach($field in @('id','version','sha256')){if(-not $seed.$case.backup.$field -or $seed.$case.backup.$field -notmatch '^[A-Za-z0-9-]{1,128}$'){throw "Métadonnée Storage invalide."}}}
  $operationValues=for($i=0;$i -lt 3;$i++){"('$($operations[$i])','$person','$owner','$owner','user','transaction_proof_replace','transaction','$($transactions[$i])',gen_random_uuid(),'attention_required','[]','REPAIR_INTEGRATION_REQUIRED',0)"}
  $targetValues=for($i=0;$i -lt 3;$i++){ $name=@('restore','missing','divergent')[$i]; $original=$seed.$name.original; "('$($targets[$i])','$($operations[$i])',1,'transaction-proofs','protected-persons/$person/transactions/$($transactions[$i])/proof','primary','update','update',true,'$($original.id)','$($original.version)','pending',0)" }
  $backupValues=for($i=0;$i -lt 3;$i++){ $name=@('restore','missing','divergent')[$i]; $stored=$seed.$name.backup; if($name -eq 'missing'){ $objectId='9b500000-0000-4000-8900-000000000002'; $version='missing-v1'; $size=16; $hash=('b'*64) } else { $objectId=$stored.id; $version=$stored.version; $size=$stored.byteSize; $hash=$stored.sha256 }; "('$($backups[$i])','$($operations[$i])','$($targets[$i])','$person','$owner','transaction-proofs','protected-persons/$person/transactions/$($transactions[$i])/proof','$($seed.$name.original.id)','$($seed.$name.original.version)','operations/$($operations[$i])/targets/$($targets[$i])/backup',$size,'application/pdf','$hash','verified','$objectId','$version',now())" }
  Invoke-Psql @"
insert into public.document_operations(id,protected_person_id,initiated_by,initiator_subject_id,initiator_kind,workflow,business_entity_type,business_entity_id,client_request_id,state,target_signature,safe_error_code,row_revision) values $($operationValues -join ',');
insert into public.document_operation_targets(id,operation_id,ordinal,bucket_id,object_path,target_role,forward_action,compensation_action,expected_exists,expected_object_id,expected_object_version,application_state,target_revision) values $($targetValues -join ',');
insert into public.document_object_locks(bucket_id,object_path,target_id,operation_id) select bucket_id,object_path,id,operation_id from public.document_operation_targets where operation_id in('$($operations -join "','")');
insert into public.document_operation_backups(id,operation_id,target_id,protected_person_id,initiator_subject_id,original_bucket_id,original_object_path,original_object_id,original_object_version,recovery_object_path,byte_size,mime_type,sha256,state,recovery_object_id,recovery_object_version,upload_verified_at) values $($backupValues -join ',');
"@|Out-Null
  node --experimental-strip-types "supabase/tests/administrative_document_repair_integration.mjs" execute
  if($LASTEXITCODE -ne 0){throw "Échec du harnais de réparation documentaire."}
  $verification=Invoke-Psql "select (select state from public.document_operations where id='$($operations[0])')||'|'||(select count(*) from public.document_object_locks where operation_id in('$($operations[1])','$($operations[2])'));"
  if($verification -ne 'administratively_resolved|2'){throw "État SQL final inattendu: $verification"}
} finally {
  Remove-Item Env:PAT_TEST_SUPABASE_URL,Env:PAT_TEST_SUPABASE_ANON_KEY,Env:PAT_TEST_SUPABASE_SERVICE_ROLE_KEY,Env:PAT_TEST_PASSWORD -ErrorAction SilentlyContinue
  # Les décisions, observations et événements de réparation sont volontairement
  # immuables. Une reconstruction locale est donc le seul nettoyage fidèle qui
  # ne désactive aucun trigger et ne crée aucune porte de purge applicative.
  & $SupabaseCli db reset --local --no-seed | Out-Null
  if($LASTEXITCODE -ne 0){Write-Warning "La reconstruction de nettoyage Supabase local a échoué."}
}
