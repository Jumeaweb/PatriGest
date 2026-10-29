param([string]$ContainerName = "supabase_db_PatriGest")

$ErrorActionPreference = "Stop"
$docker = (Get-Command docker -ErrorAction Stop).Source
$utf8 = [System.Text.UTF8Encoding]::new($false)

function Start-Psql([string]$Sql) {
  $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $docker
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardInput = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.StandardInputEncoding = $utf8
  $startInfo.StandardOutputEncoding = $utf8
  $startInfo.StandardErrorEncoding = $utf8
  $startInfo.Arguments = "exec -i `"$ContainerName`" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -At -f -"
  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  [void]$process.Start()
  $process.StandardInput.Write($Sql)
  $process.StandardInput.Close()
  return $process
}

function Wait-Psql($Process) {
  $Process.WaitForExit()
  [pscustomobject]@{
    ExitCode = $Process.ExitCode
    Output = $Process.StandardOutput.ReadToEnd()
    Error = $Process.StandardError.ReadToEnd()
  }
}

function Invoke-Psql([string]$Sql) {
  $result = Wait-Psql (Start-Psql $Sql)
  if ($result.ExitCode -ne 0) {
    throw $result.Error
  }
  return $result.Output.Trim()
}

$owner = "99500000-0000-4000-8000-000000000001"
$person = "99500000-0000-4000-8100-000000000001"
$account = "99500000-0000-4000-8200-000000000001"
$transaction = "99500000-0000-4000-8300-000000000001"
$operationRequest = "99500000-0000-4000-8400-000000000001"
$firstPermitRequest = "99500000-0000-4000-8500-000000000001"
$secondPermitRequest = "99500000-0000-4000-8500-000000000002"
$claims = '{"sub":"99500000-0000-4000-8000-000000000001","role":"authenticated"}'
# Les RPC expérimentales sont fermées aux rôles Data API en production. Ce
# harnais teste uniquement la sérialisation interne comme propriétaire SQL,
# avec les claims attendus par les contrôles métier. Les privilèges Data API
# sont vérifiés séparément par experimental_document_operations_disabled_test.
$asUser = "select set_config('request.jwt.claim.sub','$owner',true); select set_config('request.jwt.claims','$claims',true);"
$asService = "select set_config('request.jwt.claims','{`"role`":`"service_role`"}',true);"

Invoke-Psql @"
insert into auth.users(
  instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at
)
values(
  '00000000-0000-0000-0000-000000000000','$owner','authenticated',
  'authenticated','permit-concurrency@example.test','test',now(),'{}','{}',now(),now()
);
update public.application_user_authorizations
set status='active',status_changed_at=now(),account_mode='autonomous'
where user_id='$owner';
insert into public.account_subscriptions(owner_id,status,started_at)
values('$owner','development',now());
insert into public.protected_persons(id,owner_id,first_name,last_name)
values('$person','$owner','Concurrence','Permis');
insert into public.financial_accounts(
  id,protected_person_id,account_type,institution_name,account_name,
  initial_balance,initial_balance_date
)
values('$account','$person','checking','Banque test','Compte test',0,'2026-01-01');
insert into public.transactions(
  id,financial_account_id,transaction_date,transaction_type,label,amount
)
values('$transaction','$account','2026-01-02','expense','Permis concurrent',10);
begin;
$asUser
select public.begin_transaction_proof_document_operation(
  '$person','$transaction','create','$operationRequest'
);
commit;
"@ | Out-Null

$operation = Invoke-Psql "select id from public.document_operations where client_request_id='$operationRequest';"
$target = Invoke-Psql "select id from public.document_operation_targets where operation_id='$operation';"
Invoke-Psql "begin; $asUser select public.start_document_operation('$operation',1); commit;" | Out-Null

$issueOne = Start-Psql "begin; $asService select public.issue_document_storage_mutation_permit('$operation','$target','$firstPermitRequest',2,0,null); select pg_sleep(2); commit;"
Start-Sleep -Milliseconds 400
$issueTwo = Start-Psql "begin; $asService select public.issue_document_storage_mutation_permit('$operation','$target','$secondPermitRequest',2,0,null); commit;"
$issueOneResult = Wait-Psql $issueOne
$issueTwoResult = Wait-Psql $issueTwo

if ($issueOneResult.ExitCode -ne 0) {
  throw "La première émission concurrente a échoué : $($issueOneResult.Error)"
}
if ($issueTwoResult.ExitCode -eq 0 -or $issueTwoResult.Error -notmatch 'P4G05|permis (actif )?existe déjà') {
  throw "La seconde émission concurrente n'a pas été refusée : $($issueTwoResult.Error)"
}

$activePermitCount = Invoke-Psql "select count(*) from public.document_storage_mutation_permits where operation_id='$operation' and target_id='$target' and state='issued';"
if ($activePermitCount -ne "1") {
  throw "Nombre de permis actifs inattendu après émission concurrente : $activePermitCount"
}

$permit = Invoke-Psql "select id from public.document_storage_mutation_permits where operation_id='$operation' and target_id='$target' and state='issued';"
$path = Invoke-Psql "select object_path from public.document_operation_targets where id='$target';"
$consumeSql = "select public.consume_document_storage_mutation_permit('$permit',0,'transaction-proofs','$path','INSERT',null,null);"
$consumeOne = Start-Psql "begin; $consumeSql select pg_sleep(2); commit;"
Start-Sleep -Milliseconds 400
$consumeTwo = Start-Psql "begin; $consumeSql commit;"
$consumeOneResult = Wait-Psql $consumeOne
$consumeTwoResult = Wait-Psql $consumeTwo

if ($consumeOneResult.ExitCode -ne 0) {
  throw "La première consommation concurrente a échoué : $($consumeOneResult.Error)"
}
if ($consumeTwoResult.ExitCode -eq 0 -or $consumeTwoResult.Error -notmatch 'P4G06|déjà consommé|a changé') {
  throw "La seconde consommation concurrente n'a pas été refusée : $($consumeTwoResult.Error)"
}

$terminalState = Invoke-Psql "select state||':'||row_revision from public.document_storage_mutation_permits where id='$permit';"
if ($terminalState -ne "consumed:1") {
  throw "État terminal inattendu après consommation concurrente : $terminalState"
}

Write-Output "PASS: émission concurrente sérialisée, un seul permis actif et une seule consommation autorisée."
Write-Output "INFO: les fixtures append-only seront supprimées par le db reset local exécuté après ce test."
