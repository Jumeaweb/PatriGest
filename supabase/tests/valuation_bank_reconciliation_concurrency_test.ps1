param(
  [string]$ContainerName = "supabase_db_PatriGest-Valuation-Reconciliation-Test"
)

$ErrorActionPreference = "Stop"
$docker = (Get-Command docker -ErrorAction Stop).Source

function Start-Psql([string]$Sql) {
  $start = [System.Diagnostics.ProcessStartInfo]::new()
  $start.FileName = $docker
  $start.Arguments = "exec -i `"$ContainerName`" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -At -f -"
  $start.UseShellExecute = $false
  $start.CreateNoWindow = $true
  $start.RedirectStandardInput = $true
  $start.RedirectStandardOutput = $true
  $start.RedirectStandardError = $true
  $utf8 = [System.Text.UTF8Encoding]::new($false)
  $start.StandardInputEncoding = $utf8
  $start.StandardOutputEncoding = $utf8
  $start.StandardErrorEncoding = $utf8
  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $start
  [void]$process.Start()
  $process.StandardInput.Write($Sql)
  $process.StandardInput.Close()
  return $process
}

function Wait-Psql([System.Diagnostics.Process]$Process) {
  $Process.WaitForExit()
  [pscustomobject]@{
    ExitCode = $Process.ExitCode
    Output = $Process.StandardOutput.ReadToEnd()
    Error = $Process.StandardError.ReadToEnd()
  }
}

function Invoke-Psql([string]$Sql) {
  $result = Wait-Psql (Start-Psql $Sql)
  if ($result.ExitCode -ne 0) { throw $result.Error }
  $result.Output.Trim()
}

$owner = "99800000-0000-4000-8000-000000000001"
$person = "99800000-0000-4000-8100-000000000001"
$account = "99800000-0000-4000-8200-000000000001"
$valuation = "99800000-0000-4000-8300-000000000001"
$statement = "99800000-0000-4000-8400-000000000001"
$reconciliation = "99800000-0000-4000-8500-000000000001"

$cleanup = @"
set session_replication_role=replica;
delete from public.bank_reconciliations where id='$reconciliation';
delete from public.bank_statements where id='$statement';
delete from public.account_valuations where id='$valuation';
delete from public.financial_accounts where id='$account';
delete from public.protected_persons where id='$person';
delete from auth.users where id='$owner';
set session_replication_role=origin;
"@

try {
  Invoke-Psql $cleanup | Out-Null
  Invoke-Psql @"
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('00000000-0000-0000-0000-000000000000','$owner','authenticated','authenticated','valuation-concurrency@example.test','hash',now(),'{"provider":"email","providers":["email"]}','{}',now(),now());
update public.application_user_authorizations set status='active',status_changed_at=now() where user_id='$owner';
insert into public.protected_persons(id,owner_id,first_name,last_name) values('$person','$owner','Concurrence','Valorisation');
insert into public.financial_accounts(id,protected_person_id,account_type,institution_name,account_name,initial_balance,initial_balance_date,status)
values('$account','$person','life_insurance','Test','Compte valorisé',100,'2020-01-01','active');
insert into public.account_valuations(id,financial_account_id,valuation_date,value) values('$valuation','$account','2020-12-31',125);
insert into public.bank_statements(id,financial_account_id,statement_end_date,statement_balance,storage_path,created_by)
values('$statement','$account','2020-12-31',125,'valuation-concurrency','$owner');
insert into public.bank_reconciliations(id,bank_statement_id,created_by) values('$reconciliation','$statement','$owner');
"@ | Out-Null

  $validate = @"
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','$owner',true);
select set_config('request.jwt.claims','{"sub":"$owner","role":"authenticated"}',true);
select * from public.account_valuations where id='$valuation' for share;
select pg_sleep(1);
select (public.validate_bank_reconciliation('$reconciliation')).status;
commit;
"@
  $modify = @"
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','$owner',true);
select set_config('request.jwt.claims','{"sub":"$owner","role":"authenticated"}',true);
update public.account_valuations set value=126 where id='$valuation';
commit;
"@
  $validationProcess = Start-Psql $validate
  Start-Sleep -Milliseconds 150
  $modificationProcess = Start-Psql $modify
  $validationResult = Wait-Psql $validationProcess
  $modificationResult = Wait-Psql $modificationProcess
  if ($validationResult.ExitCode -ne 0) { throw "La validation concurrente a échoué : $($validationResult.Error)" }
  if ($modificationResult.ExitCode -eq 0 -or $modificationResult.Error -notmatch "rapprochement validé") {
    throw "La modification concurrente n'a pas été refusée correctement : $($modificationResult | ConvertTo-Json -Compress)"
  }

  $state = Invoke-Psql "select status || ':' || control_basis || ':' || reference_value from public.bank_reconciliations where id='$reconciliation';"
  if ($state -ne "validated:valuation:125.00") { throw "État final inattendu : $state" }
  Write-Output "PASS: la validation verrouille la valorisation; la modification concurrente attend puis est refusée sans altérer l'instantané."
}
finally {
  try { Invoke-Psql $cleanup | Out-Null } catch { Write-Warning $_ }
}
