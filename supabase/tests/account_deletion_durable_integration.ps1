param(
  [string]$ContainerName = "supabase_db_PatriGest",
  [string]$SupabaseCli = ""
)
$ErrorActionPreference = "Stop"
$docker = (Get-Command docker -ErrorAction Stop).Source
$utf8 = [System.Text.UTF8Encoding]::new($false)

if (-not $SupabaseCli) {
  $installed = Get-Command supabase -ErrorAction SilentlyContinue
  if ($installed) {
    $SupabaseCli = $installed.Source
  } else {
    $cached = Get-ChildItem -LiteralPath "$env:LOCALAPPDATA\npm-cache\_npx" -Recurse -Filter "supabase.exe" -ErrorAction SilentlyContinue |
      Select-Object -First 1 -ExpandProperty FullName
    if (-not $cached) { throw "CLI Supabase introuvable. Fournissez -SupabaseCli après une installation locale." }
    $SupabaseCli = $cached
  }
}

function Invoke-Psql([string]$Sql) {
  $start = [System.Diagnostics.ProcessStartInfo]::new()
  $start.FileName = $docker
  $start.UseShellExecute = $false
  $start.CreateNoWindow = $true
  $start.RedirectStandardInput = $true
  $start.RedirectStandardOutput = $true
  $start.RedirectStandardError = $true
  $start.StandardInputEncoding = $utf8
  $start.StandardOutputEncoding = $utf8
  $start.StandardErrorEncoding = $utf8
  $start.Arguments = "exec -i `"$ContainerName`" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -At -f -"
  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $start
  [void]$process.Start()
  $process.StandardInput.Write($Sql)
  $process.StandardInput.Close()
  $output = $process.StandardOutput.ReadToEnd()
  $errorOutput = $process.StandardError.ReadToEnd()
  $process.WaitForExit()
  if ($process.ExitCode -ne 0) { throw $errorOutput }
  $output.Trim()
}

$localStatus = & $SupabaseCli status -o env 2>$null
$configuration = @{}
foreach ($line in $localStatus) {
  if ($line -match '^([A-Z0-9_]+)="?(.*?)"?$') {
    $configuration[$Matches[1]] = $Matches[2].TrimEnd('"')
  }
}
foreach ($required in @("API_URL", "ANON_KEY", "SERVICE_ROLE_KEY", "DB_URL")) {
  if (-not $configuration.ContainsKey($required)) { throw "Configuration Supabase locale incomplète." }
}
$apiUri = [Uri]$configuration.API_URL
$dbUri = [Uri]$configuration.DB_URL
if ($apiUri.Scheme -ne "http" -or $apiUri.Host -notin @("127.0.0.1", "localhost") -or $apiUri.Port -ne 54321) {
  throw "Refus d’exécuter le harnais hors de l’API Supabase locale attendue."
}
if ($dbUri.Host -notin @("127.0.0.1", "localhost") -or $dbUri.Port -ne 54322) {
  throw "Refus d’exécuter le harnais sur une base PostgreSQL non locale."
}

$users = @(
  @{ Key = "owner"; Id = "9b000000-0000-4000-8000-000000000001"; Email = "deletion-owner@example.test" },
  @{ Key = "manager"; Id = "9b000000-0000-4000-8000-000000000002"; Email = "deletion-manager@example.test" },
  @{ Key = "reader"; Id = "9b000000-0000-4000-8000-000000000003"; Email = "deletion-reader@example.test" },
  @{ Key = "platform"; Id = "9b000000-0000-4000-8000-000000000004"; Email = "deletion-platform@example.test" },
  @{ Key = "interrupt"; Id = "9b000000-0000-4000-8000-000000000005"; Email = "deletion-interrupt@example.test" },
  @{ Key = "freeze"; Id = "9b000000-0000-4000-8000-000000000006"; Email = "deletion-freeze@example.test" },
  @{ Key = "state"; Id = "9b000000-0000-4000-8000-000000000007"; Email = "deletion-state@example.test" },
  @{ Key = "refused"; Id = "9b000000-0000-4000-8000-000000000008"; Email = "deletion-refused@example.test" },
  @{ Key = "ambiguous"; Id = "9b000000-0000-4000-8000-000000000009"; Email = "deletion-ambiguous@example.test" },
  @{ Key = "absent"; Id = "9b000000-0000-4000-8000-000000000010"; Email = "deletion-absent@example.test" },
  @{ Key = "signout"; Id = "9b000000-0000-4000-8000-000000000011"; Email = "deletion-signout@example.test" },
  @{ Key = "divergence"; Id = "9b000000-0000-4000-8000-000000000012"; Email = "deletion-divergence@example.test" },
  @{ Key = "sha"; Id = "9b000000-0000-4000-8000-000000000013"; Email = "deletion-sha@example.test" },
  @{ Key = "backup"; Id = "9b000000-0000-4000-8000-000000000014"; Email = "deletion-backup@example.test" },
  @{ Key = "lost"; Id = "9b000000-0000-4000-8000-000000000015"; Email = "deletion-lost@example.test" },
  @{ Key = "concurrent"; Id = "9b000000-0000-4000-8000-000000000016"; Email = "deletion-concurrent@example.test" }
)
$owner = $users[0].Id
$manager = $users[1].Id
$platform = $users[3].Id
$stateUser = $users[6].Id
$person = "9b000000-0000-4000-8100-000000000001"
$account = "9b000000-0000-4000-8200-000000000001"
$transactions = 1..24 | ForEach-Object { "9b000000-0000-4000-8300-{0:D12}" -f $_ }
$statements = 1..2 | ForEach-Object { "9b000000-0000-4000-8400-{0:D12}" -f $_ }
$reports = 1..2 | ForEach-Object { "9b000000-0000-4000-8500-{0:D12}" -f $_ }
$expiredAttempt = "9b000000-0000-4000-9100-000000000001"
$expiredAuthorization = "9b000000-0000-4000-9200-000000000001"
$expiredOperation = "9b000000-0000-4000-9300-000000000001"
$expiredTarget = "9b000000-0000-4000-9400-000000000001"
$password = "Local-only-3H2B2!2026"
$userIds = ($users | ForEach-Object { "'$($_.Id)'" }) -join ","

$cleanup = @"
select set_config('storage.allow_delete_query','true',false);
delete from storage.objects where bucket_id in (
  'transaction-proofs','bank-statements','management-reports','document-operation-backups'
) and (
  name like 'protected-persons/$person/%'
  or name in (
    select recovery_object_path from public.document_operation_backups
    where protected_person_id='$person'
  )
);
select set_config('storage.allow_delete_query','false',false);
delete from public.account_storage_neutralizations
where operation_id in (select id from public.document_operations where protected_person_id='$person');
delete from public.document_operation_backups where protected_person_id='$person';
delete from public.document_object_locks where operation_id in (select id from public.document_operations where protected_person_id='$person');
delete from public.document_operation_events where operation_id in (select id from public.document_operations where protected_person_id='$person');
delete from public.document_operation_targets where operation_id in (select id from public.document_operations where protected_person_id='$person');
delete from public.document_operations where protected_person_id='$person';
delete from public.account_deletion_document_authorizations where account_user_id in ($userIds);
delete from public.management_report_approvals where management_report_id in (select id from public.management_reports where protected_person_id='$person');
delete from public.management_report_difficulties where management_report_id in (select id from public.management_reports where protected_person_id='$person');
delete from public.management_report_transmissions where management_report_id in (select id from public.management_reports where protected_person_id='$person');
delete from public.management_report_documents where management_report_id in (select id from public.management_reports where protected_person_id='$person');
delete from public.management_report_account_selections where management_report_id in (select id from public.management_reports where protected_person_id='$person');
delete from public.management_reports where protected_person_id='$person';
delete from public.transaction_documents where transaction_id in (select id from public.transactions where financial_account_id='$account');
delete from public.bank_reconciliation_outstanding_transactions where bank_reconciliation_id in (
  select id from public.bank_reconciliations where bank_statement_id in (select id from public.bank_statements where financial_account_id='$account')
);
delete from public.bank_reconciliations where bank_statement_id in (select id from public.bank_statements where financial_account_id='$account');
delete from public.bank_statements where financial_account_id='$account';
delete from public.transactions where financial_account_id='$account';
delete from public.financial_accounts where id='$account';
delete from public.protected_person_access where protected_person_id='$person';
delete from public.protected_person_archive_changes where protected_person_id='$person';
delete from public.proof_reference_assignments where protected_person_id='$person';
delete from public.proof_reference_counters where protected_person_id='$person';
delete from public.protected_persons where id='$person';
delete from public.platform_administrators where user_id in ($userIds);
delete from public.account_subscriptions where owner_id in ($userIds);
delete from auth.users where id in ($userIds);
"@

try {
  Invoke-Psql $cleanup | Out-Null
  $userValues = ($users | ForEach-Object {
    "('00000000-0000-0000-0000-000000000000','$($_.Id)','authenticated','authenticated','$($_.Email)',extensions.crypt('$password',extensions.gen_salt('bf')),now(),'','','','','','','{`"provider`":`"email`",`"providers`" : [`"email`"]}','{}',now(),now())"
  }) -join ",`n"
  $identityValues = ($users | ForEach-Object {
    "(gen_random_uuid(),'$($_.Id)','$($_.Email)',jsonb_build_object('sub','$($_.Id)','email','$($_.Email)'),'email',now(),now(),now())"
  }) -join ",`n"
  $accessValues = ($users | Where-Object { $_.Key -notin @("owner", "platform") } | ForEach-Object -Begin { $index = 0 } -Process {
    $index += 1
    $role = if ($_.Key -eq "reader") { "read_only" } else { "manager" }
    "('9b000000-0000-4000-8900-{0:D12}','$person','$($_.Id)','$role','$owner')" -f $index
  }) -join ",`n"
  $transactionValues = ($transactions | ForEach-Object -Begin { $index = 0 } -Process {
    $index += 1
    "('$_','$account','2026-04-{0:D2}','expense','Suppression durable $index',$index)" -f $index
  }) -join ",`n"

  Invoke-Psql @"
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  confirmation_token,recovery_token,email_change_token_new,email_change,
  email_change_token_current,reauthentication_token,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values $userValues;
insert into auth.identities(id,user_id,provider_id,identity_data,provider,last_sign_in_at,created_at,updated_at)
values $identityValues;
update public.application_user_authorizations set status='active',status_changed_at=now()
where user_id in ($userIds);
update public.application_user_authorizations set account_mode='autonomous' where user_id='$owner';
insert into public.account_subscriptions(owner_id,status,started_at) values('$owner','development',now());
insert into public.platform_administrators(user_id) values('$platform');
insert into public.protected_persons(id,owner_id,first_name,last_name)
values('$person','$owner','Intégration','Suppression durable');
insert into public.protected_person_access(id,protected_person_id,user_id,role,invited_by)
values $accessValues;
insert into public.financial_accounts(id,protected_person_id,account_type,institution_name,account_name,initial_balance,initial_balance_date)
values('$account','$person','checking','Banque locale','Compte suppression durable',0,'2026-01-01');
insert into public.transactions(id,financial_account_id,transaction_date,transaction_type,label,amount)
values $transactionValues;
insert into public.bank_statements(
  id,financial_account_id,statement_start_date,statement_end_date,statement_balance,
  storage_path,original_file_name,mime_type,file_size,note,created_by
) values
('$($statements[0])','$account','2026-01-01','2026-01-31',100,
 'protected-persons/$person/accounts/$account/statements/$($statements[0])/statement',
 'janvier.pdf','application/pdf',64,'Intégration suppression','$manager'),
('$($statements[1])','$account','2026-02-01','2026-02-28',110,
 'protected-persons/$person/accounts/$account/statements/$($statements[1])/statement',
 'fevrier.pdf','application/pdf',64,'Intégration reprise','$($users[4].Id)');
insert into public.management_reports(
  id,protected_person_id,report_year,period_start,period_end,status,created_by
) values
('$($reports[0])','$person',2198,'2198-01-01','2198-12-31','ready','$manager'),
('$($reports[1])','$person',2199,'2199-01-01','2199-12-31','ready','$($users[4].Id)');

insert into public.account_deletion_document_authorizations(
  id,account_user_id,attempt_id,issued_at,expires_at,state
) values(
  '$expiredAuthorization','$stateUser','$expiredAttempt',
  clock_timestamp()-interval '2 minutes',clock_timestamp()-interval '1 minute','active'
);
insert into public.document_operations(
  id,protected_person_id,initiated_by,initiator_subject_id,initiator_kind,
  workflow,business_entity_type,business_entity_id,client_request_id,target_signature
) values(
  '$expiredOperation','$person','$stateUser','$stateUser','account_deletion',
  'account_storage_neutralization','transaction','$($transactions[23])',
  '9b000000-0000-4000-9500-000000000001','[]'::jsonb
);
insert into public.document_operation_targets(
  id,operation_id,ordinal,bucket_id,object_path,target_role,forward_action,
  compensation_action,expected_exists,expected_object_id,expected_object_version,
  expected_snapshot_captured_at
) values(
  '$expiredTarget','$expiredOperation',1,'transaction-proofs',
  'protected-persons/$person/transactions/$($transactions[23])/proof',
  'primary','delete','insert',true,
  '9b000000-0000-4000-9600-000000000001','expired-fixture-v1',now()
);
insert into public.account_storage_neutralizations(
  operation_id,target_id,authorization_id,account_user_id,
  expected_sha256,expected_byte_size,mime_type
) values(
  '$expiredOperation','$expiredTarget','$expiredAuthorization','$stateUser',
  repeat('a',64),1,'application/pdf'
);
"@ | Out-Null

  $env:PAT_TEST_SUPABASE_URL = $configuration.API_URL
  $env:PAT_TEST_SUPABASE_ANON_KEY = $configuration.ANON_KEY
  $env:PAT_TEST_SUPABASE_SERVICE_ROLE_KEY = $configuration.SERVICE_ROLE_KEY
  $env:PAT_TEST_PASSWORD = $password
  $env:PATRIGEST_ENABLE_ACCOUNT_DELETION_DURABLE_NEUTRALIZATION = "true"
  node --experimental-strip-types "supabase/tests/account_deletion_durable_integration.mjs"
  if ($LASTEXITCODE -ne 0) { throw "Le harnais d’intégration de suppression durable a échoué." }
}
finally {
  Remove-Item Env:PAT_TEST_SUPABASE_URL,Env:PAT_TEST_SUPABASE_ANON_KEY,Env:PAT_TEST_SUPABASE_SERVICE_ROLE_KEY,Env:PAT_TEST_PASSWORD,Env:PATRIGEST_ENABLE_ACCOUNT_DELETION_DURABLE_NEUTRALIZATION -ErrorAction SilentlyContinue
  try { Invoke-Psql $cleanup | Out-Null } catch { Write-Warning "Nettoyage local incomplet : $($_.Exception.Message)" }
}
