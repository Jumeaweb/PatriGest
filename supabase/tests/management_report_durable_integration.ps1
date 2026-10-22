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

$owner = "9a000000-0000-4000-8000-000000000001"
$manager = "9a000000-0000-4000-8000-000000000002"
$reader = "9a000000-0000-4000-8000-000000000003"
$outsider = "9a000000-0000-4000-8000-000000000004"
$person = "9a000000-0000-4000-8100-000000000001"
$reports = 1..12 | ForEach-Object { "9a000000-0000-4000-8600-{0:D12}" -f $_ }
$password = "Local-only-3G2C!2026"

$cleanup = @"
select set_config('storage.allow_delete_query','true',false);
delete from storage.objects where bucket_id in ('management-reports','document-operation-backups')
  and (
    name like 'protected-persons/$person/%'
    or name in (
      select recovery_object_path from public.document_operation_backups where protected_person_id='$person'
    )
  );
select set_config('storage.allow_delete_query','false',false);
delete from public.document_operation_backups where protected_person_id='$person';
delete from public.document_object_locks where operation_id in (select id from public.document_operations where protected_person_id='$person');
delete from public.document_operation_events where operation_id in (select id from public.document_operations where protected_person_id='$person');
delete from public.document_operation_targets where operation_id in (select id from public.document_operations where protected_person_id='$person');
delete from public.document_operations where protected_person_id='$person';
delete from public.management_report_approvals where management_report_id in (select id from public.management_reports where protected_person_id='$person');
delete from public.management_report_difficulties where management_report_id in (select id from public.management_reports where protected_person_id='$person');
delete from public.management_report_transmissions where management_report_id in (select id from public.management_reports where protected_person_id='$person');
delete from public.management_report_documents where management_report_id in (select id from public.management_reports where protected_person_id='$person');
delete from public.management_report_account_selections where management_report_id in (select id from public.management_reports where protected_person_id='$person');
delete from public.management_reports where protected_person_id='$person';
delete from public.protected_person_access where protected_person_id='$person';
delete from public.protected_person_archive_changes where protected_person_id='$person';
delete from public.proof_reference_assignments where protected_person_id='$person';
delete from public.proof_reference_counters where protected_person_id='$person';
delete from public.protected_persons where id='$person';
delete from public.account_subscriptions where owner_id='$owner';
delete from auth.users where id in ('$owner','$manager','$reader','$outsider');
"@

try {
  Invoke-Psql $cleanup | Out-Null
  $reportValues = ($reports | ForEach-Object -Begin { $year = 2100 } -Process {
    $value = "('$_','$person',$year,'$year-01-01','$year-12-31','ready','$owner')"
    $year += 1
    $value
  }) -join ",`n"
  Invoke-Psql @"
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  confirmation_token,recovery_token,email_change_token_new,email_change,
  email_change_token_current,reauthentication_token,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values
('00000000-0000-0000-0000-000000000000','$owner','authenticated','authenticated','report-3g2c-owner@example.test',extensions.crypt('$password',extensions.gen_salt('bf')),now(),'','','','','','','{"provider":"email","providers":["email"]}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','$manager','authenticated','authenticated','report-3g2c-manager@example.test',extensions.crypt('$password',extensions.gen_salt('bf')),now(),'','','','','','','{"provider":"email","providers":["email"]}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','$reader','authenticated','authenticated','report-3g2c-reader@example.test',extensions.crypt('$password',extensions.gen_salt('bf')),now(),'','','','','','','{"provider":"email","providers":["email"]}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','$outsider','authenticated','authenticated','report-3g2c-outsider@example.test',extensions.crypt('$password',extensions.gen_salt('bf')),now(),'','','','','','','{"provider":"email","providers":["email"]}','{}',now(),now());
insert into auth.identities(id,user_id,provider_id,identity_data,provider,last_sign_in_at,created_at,updated_at)
values
(gen_random_uuid(),'$owner','report-3g2c-owner@example.test',jsonb_build_object('sub','$owner','email','report-3g2c-owner@example.test'),'email',now(),now(),now()),
(gen_random_uuid(),'$manager','report-3g2c-manager@example.test',jsonb_build_object('sub','$manager','email','report-3g2c-manager@example.test'),'email',now(),now(),now()),
(gen_random_uuid(),'$reader','report-3g2c-reader@example.test',jsonb_build_object('sub','$reader','email','report-3g2c-reader@example.test'),'email',now(),now(),now()),
(gen_random_uuid(),'$outsider','report-3g2c-outsider@example.test',jsonb_build_object('sub','$outsider','email','report-3g2c-outsider@example.test'),'email',now(),now(),now());
update public.application_user_authorizations set status='active',status_changed_at=now()
where user_id in ('$owner','$manager','$reader','$outsider');
update public.application_user_authorizations set account_mode='autonomous' where user_id='$owner';
insert into public.account_subscriptions(owner_id,status,started_at) values('$owner','development',now());
insert into public.protected_persons(id,owner_id,first_name,last_name) values('$person','$owner','Intégration','Comptes de gestion');
insert into public.protected_person_access(id,protected_person_id,user_id,role,invited_by) values
('9a000000-0000-4000-8900-000000000001','$person','$manager','manager','$owner'),
('9a000000-0000-4000-8900-000000000002','$person','$reader','read_only','$owner');
insert into public.management_reports(id,protected_person_id,report_year,period_start,period_end,status,created_by)
values $reportValues;
"@ | Out-Null

  $env:PAT_TEST_SUPABASE_URL = $configuration.API_URL
  $env:PAT_TEST_SUPABASE_ANON_KEY = $configuration.ANON_KEY
  $env:PAT_TEST_SUPABASE_SERVICE_ROLE_KEY = $configuration.SERVICE_ROLE_KEY
  $env:PAT_TEST_PASSWORD = $password
  $env:PATRIGEST_ENABLE_MANAGEMENT_REPORT_DURABLE_OPERATIONS = "true"
  node --experimental-strip-types "supabase/tests/management_report_durable_integration.mjs"
  if ($LASTEXITCODE -ne 0) { throw "Le harnais d’intégration des comptes de gestion a échoué." }
}
finally {
  Remove-Item Env:PAT_TEST_SUPABASE_URL,Env:PAT_TEST_SUPABASE_ANON_KEY,Env:PAT_TEST_SUPABASE_SERVICE_ROLE_KEY,Env:PAT_TEST_PASSWORD,Env:PATRIGEST_ENABLE_MANAGEMENT_REPORT_DURABLE_OPERATIONS -ErrorAction SilentlyContinue
  try { Invoke-Psql $cleanup | Out-Null } catch { Write-Warning "Nettoyage local incomplet : $($_.Exception.Message)" }
}
