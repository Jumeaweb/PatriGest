param([string]$ContainerName = "supabase_db_PatriGest", [string]$SupabaseCli = "")
$ErrorActionPreference = "Stop"
$docker = (Get-Command docker -ErrorAction Stop).Source
$utf8 = [System.Text.UTF8Encoding]::new($false)
if (-not $SupabaseCli) {
  $installed = Get-Command supabase -ErrorAction SilentlyContinue
  if ($installed) { $SupabaseCli = $installed.Source } else {
    $SupabaseCli = Get-ChildItem -LiteralPath "$env:LOCALAPPDATA\npm-cache\_npx" -Recurse -Filter "supabase.exe" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
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
$users=@("admin","owner","target","empty","blocked"); $ids=1..5|ForEach-Object{"ac000000-0000-4000-8000-{0:D12}" -f $_}; $password="Local-only-admin-3H2C3!"
$person="ac000000-0000-4000-8100-000000000001"; $account="ac000000-0000-4000-8200-000000000001"; $transaction="ac000000-0000-4000-8300-000000000001"; $statement="ac000000-0000-4000-8400-000000000001"; $report="ac000000-0000-4000-8500-000000000001"
$userIds=($ids|ForEach-Object{"'$_'"}) -join ','
$cleanup=@"
select set_config('storage.allow_delete_query','true',false);
delete from storage.objects where name like 'protected-persons/$person/%' or name like 'administrative-account-deletion/%';
select set_config('storage.allow_delete_query','false',false);
delete from public.administrative_account_deletion_events where target_user_id in ($userIds);
delete from public.account_storage_neutralizations where account_user_id in ($userIds);
delete from public.document_operation_backups where protected_person_id='$person';
delete from public.document_object_locks where operation_id in(select id from public.document_operations where protected_person_id='$person');
delete from public.document_operation_events where operation_id in(select id from public.document_operations where protected_person_id='$person');
delete from public.document_operation_targets where operation_id in(select id from public.document_operations where protected_person_id='$person');
delete from public.document_operations where protected_person_id='$person';
delete from public.administrative_account_deletion_authorizations where target_user_id in ($userIds);
delete from public.management_report_documents where management_report_id='$report'; delete from public.management_reports where id='$report';
delete from public.bank_statements where id='$statement'; delete from public.transaction_documents where transaction_id='$transaction'; delete from public.transactions where id='$transaction';
delete from public.proof_reference_assignments where protected_person_id='$person'; delete from public.proof_reference_counters where protected_person_id='$person';
delete from public.financial_accounts where id='$account'; delete from public.protected_person_access where protected_person_id='$person'; delete from public.protected_persons where id='$person';
delete from public.platform_administrators where user_id in ($userIds); delete from public.account_subscriptions where owner_id in ($userIds); delete from auth.users where id in ($userIds);
"@
try {
  Invoke-Psql $cleanup|Out-Null
  $userValues=for($i=0;$i -lt $users.Count;$i++){"('00000000-0000-0000-0000-000000000000','$($ids[$i])','authenticated','authenticated','admin-deletion-$($users[$i])@example.test',extensions.crypt('$password',extensions.gen_salt('bf')),now(),'','','','','','','{`"provider`":`"email`",`"providers`" : [`"email`"]}','{}',now(),now())"}
  $identityValues=for($i=0;$i -lt $users.Count;$i++){"(gen_random_uuid(),'$($ids[$i])','admin-deletion-$($users[$i])@example.test',jsonb_build_object('sub','$($ids[$i])','email','admin-deletion-$($users[$i])@example.test'),'email',now(),now(),now())"}
  Invoke-Psql @"
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,confirmation_token,recovery_token,email_change_token_new,email_change,email_change_token_current,reauthentication_token,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values $($userValues -join ',');
insert into auth.identities(id,user_id,provider_id,identity_data,provider,last_sign_in_at,created_at,updated_at) values $($identityValues -join ',');
update public.application_user_authorizations set status='active',status_changed_at=now() where user_id in ($userIds);
update public.application_user_authorizations set account_mode='autonomous' where user_id='$($ids[1])';
insert into public.platform_administrators(user_id) values('$($ids[0])'); insert into public.account_subscriptions(owner_id,status,started_at) values('$($ids[1])','development',now());
insert into public.protected_persons(id,owner_id,first_name,last_name) values('$person','$($ids[1])','Test','Suppression admin');
insert into public.protected_person_access(id,protected_person_id,user_id,role,invited_by) values(gen_random_uuid(),'$person','$($ids[2])','manager','$($ids[1])'),(gen_random_uuid(),'$person','$($ids[4])','read_only','$($ids[1])');
insert into public.financial_accounts(id,protected_person_id,account_type,institution_name,account_name,initial_balance,initial_balance_date) values('$account','$person','checking','Banque locale','Compte local',0,'2026-01-01');
insert into public.transactions(id,financial_account_id,transaction_date,transaction_type,label,amount) values('$transaction','$account','2026-01-02','expense','Test',1);
insert into public.transaction_documents(transaction_id,storage_path,file_name,mime_type,file_size,created_by) values('$transaction','protected-persons/$person/transactions/$transaction/proof','preuve.pdf','application/pdf',1,'$($ids[1])');
insert into public.bank_statements(id,financial_account_id,statement_start_date,statement_end_date,statement_balance,storage_path,original_file_name,mime_type,file_size,created_by) values('$statement','$account','2026-01-01','2026-01-31',0,'protected-persons/$person/accounts/$account/statements/$statement/statement','test.pdf','application/pdf',1,'$($ids[1])');
insert into public.management_reports(id,protected_person_id,report_year,period_start,period_end,status,created_by) values('$report','$person',2197,'2197-01-01','2197-12-31','ready','$($ids[1])');
"@|Out-Null
  $env:PAT_TEST_SUPABASE_URL=$config.API_URL; $env:PAT_TEST_SUPABASE_ANON_KEY=$config.ANON_KEY; $env:PAT_TEST_SUPABASE_SERVICE_ROLE_KEY=$config.SERVICE_ROLE_KEY; $env:PAT_TEST_PASSWORD=$password; $env:PATRIGEST_ENABLE_ADMIN_ACCOUNT_DELETION_DURABLE_NEUTRALIZATION="true"
  node --experimental-strip-types "supabase/tests/administrative_account_deletion_durable_integration.mjs"; if($LASTEXITCODE -ne 0){throw "Échec du harnais administratif durable."}
} finally {
  Remove-Item Env:PAT_TEST_SUPABASE_URL,Env:PAT_TEST_SUPABASE_ANON_KEY,Env:PAT_TEST_SUPABASE_SERVICE_ROLE_KEY,Env:PAT_TEST_PASSWORD,Env:PATRIGEST_ENABLE_ADMIN_ACCOUNT_DELETION_DURABLE_NEUTRALIZATION -ErrorAction SilentlyContinue
  try{Invoke-Psql $cleanup|Out-Null}catch{Write-Warning "Nettoyage local incomplet : $($_.Exception.Message)"}
}
