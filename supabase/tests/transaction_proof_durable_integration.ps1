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
  throw "Refus d’exécuter le harnais sur une base non locale."
}

$owner = "99e00000-0000-4000-8000-000000000001"
$manager = "99e00000-0000-4000-8000-000000000002"
$reader = "99e00000-0000-4000-8000-000000000003"
$outsider = "99e00000-0000-4000-8000-000000000004"
$person = "99e00000-0000-4000-8100-000000000001"
$account = "99e00000-0000-4000-8200-000000000001"
$transactions = 1..7 | ForEach-Object { "99e00000-0000-4000-8300-{0:D12}" -f $_ }
$password = "Local-only-3E!2026"

$cleanup = @"
select set_config('storage.allow_delete_query','true',false);
delete from storage.objects where bucket_id in ('transaction-proofs','document-operation-backups')
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
delete from public.transaction_documents where transaction_id in (select id from public.transactions where financial_account_id='$account');
delete from public.protected_person_access where protected_person_id='$person';
delete from public.proof_reference_assignments where protected_person_id='$person';
delete from public.transactions where financial_account_id='$account';
delete from public.financial_accounts where id='$account';
delete from public.protected_person_archive_changes where protected_person_id='$person';
delete from public.proof_reference_counters where protected_person_id='$person';
delete from public.protected_persons where id='$person';
delete from public.account_subscriptions where owner_id='$owner';
delete from auth.users where id in ('$owner','$manager','$reader','$outsider');
"@

try {
  Invoke-Psql $cleanup | Out-Null
  $transactionValues = ($transactions | ForEach-Object -Begin { $index = 0 } -Process {
    $index += 1
    "('$_','$account','2026-02-{0:D2}','expense','Justificatif intégration $index',$index)" -f $index
  }) -join ",`n"
  Invoke-Psql @"
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  confirmation_token,recovery_token,email_change_token_new,email_change,
  email_change_token_current,reauthentication_token,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values
('00000000-0000-0000-0000-000000000000','$owner','authenticated','authenticated','proof-3e-owner@example.test',extensions.crypt('$password',extensions.gen_salt('bf')),now(),'','','','','','','{"provider":"email","providers":["email"]}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','$manager','authenticated','authenticated','proof-3e-manager@example.test',extensions.crypt('$password',extensions.gen_salt('bf')),now(),'','','','','','','{"provider":"email","providers":["email"]}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','$reader','authenticated','authenticated','proof-3e-reader@example.test',extensions.crypt('$password',extensions.gen_salt('bf')),now(),'','','','','','','{"provider":"email","providers":["email"]}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','$outsider','authenticated','authenticated','proof-3e-outsider@example.test',extensions.crypt('$password',extensions.gen_salt('bf')),now(),'','','','','','','{"provider":"email","providers":["email"]}','{}',now(),now());
insert into auth.identities(id,user_id,provider_id,identity_data,provider,last_sign_in_at,created_at,updated_at)
values
(gen_random_uuid(),'$owner','proof-3e-owner@example.test',jsonb_build_object('sub','$owner','email','proof-3e-owner@example.test'),'email',now(),now(),now()),
(gen_random_uuid(),'$manager','proof-3e-manager@example.test',jsonb_build_object('sub','$manager','email','proof-3e-manager@example.test'),'email',now(),now(),now()),
(gen_random_uuid(),'$reader','proof-3e-reader@example.test',jsonb_build_object('sub','$reader','email','proof-3e-reader@example.test'),'email',now(),now(),now()),
(gen_random_uuid(),'$outsider','proof-3e-outsider@example.test',jsonb_build_object('sub','$outsider','email','proof-3e-outsider@example.test'),'email',now(),now(),now());
update public.application_user_authorizations set status='active',status_changed_at=now()
where user_id in ('$owner','$manager','$reader','$outsider');
update public.application_user_authorizations set account_mode='autonomous' where user_id='$owner';
insert into public.account_subscriptions(owner_id,status,started_at) values('$owner','development',now());
insert into public.protected_persons(id,owner_id,first_name,last_name) values('$person','$owner','Intégration','Justificatifs');
insert into public.protected_person_access(id,protected_person_id,user_id,role,invited_by) values
('99e00000-0000-4000-8900-000000000001','$person','$manager','manager','$owner'),
('99e00000-0000-4000-8900-000000000002','$person','$reader','read_only','$owner');
insert into public.financial_accounts(id,protected_person_id,account_type,institution_name,account_name,initial_balance,initial_balance_date)
values('$account','$person','checking','Banque locale','Compte intégration',0,'2026-01-01');
insert into public.transactions(id,financial_account_id,transaction_date,transaction_type,label,amount)
values $transactionValues;
"@ | Out-Null

  $env:PAT_TEST_SUPABASE_URL = $configuration.API_URL
  $env:PAT_TEST_SUPABASE_ANON_KEY = $configuration.ANON_KEY
  $env:PAT_TEST_SUPABASE_SERVICE_ROLE_KEY = $configuration.SERVICE_ROLE_KEY
  $env:PAT_TEST_PASSWORD = $password
  node --experimental-strip-types "supabase/tests/transaction_proof_durable_integration.mjs"
  if ($LASTEXITCODE -ne 0) { throw "Le harnais d’intégration a échoué." }
}
finally {
  Remove-Item Env:PAT_TEST_SUPABASE_URL,Env:PAT_TEST_SUPABASE_ANON_KEY,Env:PAT_TEST_SUPABASE_SERVICE_ROLE_KEY,Env:PAT_TEST_PASSWORD -ErrorAction SilentlyContinue
  try { Invoke-Psql $cleanup | Out-Null } catch { Write-Warning "Nettoyage local incomplet : $($_.Exception.Message)" }
}
