param([string]$ContainerName = "supabase_db_PatriGest")
$ErrorActionPreference = "Stop"
$docker = (Get-Command docker -ErrorAction Stop).Source
$utf8 = [System.Text.UTF8Encoding]::new($false)

function Start-Psql([string]$Sql) {
  $si = [System.Diagnostics.ProcessStartInfo]::new()
  $si.FileName = $docker
  $si.UseShellExecute = $false
  $si.CreateNoWindow = $true
  $si.RedirectStandardInput = $true
  $si.RedirectStandardOutput = $true
  $si.RedirectStandardError = $true
  $si.StandardInputEncoding = $utf8
  $si.StandardOutputEncoding = $utf8
  $si.StandardErrorEncoding = $utf8
  $si.Arguments = "exec -i `"$ContainerName`" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -At -f -"
  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $si
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
  if ($result.ExitCode -ne 0) { throw $result.Error }
  $result.Output.Trim()
}

$owner = "99800000-0000-4000-8000-000000000001"
$person = "99800000-0000-4000-8100-000000000001"
$account = "99800000-0000-4000-8200-000000000001"
$transaction = "99800000-0000-4000-8300-000000000001"
$request = "99800000-0000-4000-8400-000000000001"
$claims = '{"sub":"99800000-0000-4000-8000-000000000001","role":"authenticated"}'
$asUser = "set local role authenticated; select set_config('request.jwt.claim.sub','$owner',true); select set_config('request.jwt.claims','$claims',true);"

$cleanup = @"
delete from public.document_object_locks where operation_id in (select id from public.document_operations where protected_person_id='$person');
delete from public.document_operation_events where operation_id in (select id from public.document_operations where protected_person_id='$person');
delete from public.document_operation_targets where operation_id in (select id from public.document_operations where protected_person_id='$person');
delete from public.document_operations where protected_person_id='$person';
delete from public.proof_reference_assignments where protected_person_id='$person';
delete from public.transactions where id='$transaction';
delete from public.financial_accounts where id='$account';
delete from public.protected_person_archive_changes where protected_person_id='$person';
delete from public.proof_reference_counters where protected_person_id='$person';
delete from public.protected_persons where id='$person';
delete from auth.users where id='$owner';
"@

try {
  Invoke-Psql $cleanup | Out-Null
  Invoke-Psql @"
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('00000000-0000-0000-0000-000000000000','$owner','authenticated','authenticated','storage-target-concurrency@example.test','test',now(),'{}','{}',now(),now());
update public.application_user_authorizations set status='active',status_changed_at=now(),account_mode='autonomous' where user_id='$owner';
insert into public.account_subscriptions(owner_id,status,started_at) values('$owner','development',now());
insert into public.protected_persons(id,owner_id,first_name,last_name) values('$person','$owner','Concurrence','Cible Storage');
insert into public.financial_accounts(id,protected_person_id,account_type,institution_name,account_name,initial_balance,initial_balance_date)
values('$account','$person','checking','Banque test','Compte test',0,'2026-01-01');
insert into public.transactions(id,financial_account_id,transaction_date,transaction_type,label,amount)
values('$transaction','$account','2026-01-02','expense','Test cible',10);
begin;
$asUser
select public.begin_transaction_proof_document_operation('$person','$transaction','create','$request');
commit;
select public.transition_document_operation(
  (select id from public.document_operations where client_request_id='$request'),
  'reserved','executing');
"@ | Out-Null

  $target = Invoke-Psql "select target.id from public.document_operation_targets target join public.document_operations operation on operation.id=target.operation_id where operation.client_request_id='$request';"
  $first = Start-Psql "begin; select public.transition_document_operation_target('$target',0,'applied','99800000-0000-4000-8800-000000000001','version-a'); select pg_sleep(2); commit;"
  Start-Sleep -Milliseconds 400
  $second = Start-Psql "begin; select public.transition_document_operation_target('$target',0,'applied','99800000-0000-4000-8800-000000000002','version-b'); commit;"
  $firstResult = Wait-Psql $first
  $secondResult = Wait-Psql $second

  if ($firstResult.ExitCode -ne 0 -or $secondResult.ExitCode -eq 0 -or $secondResult.Error -notmatch 'P4S05|révision de la cible documentaire a changé') {
    throw "Transitions concurrentes non sérialisées: $($firstResult.Error) $($secondResult.Error)"
  }
  $state = Invoke-Psql "select application_state||':'||target_revision||':'||applied_object_version from public.document_operation_targets where id='$target';"
  if ($state -ne 'applied:1:version-a') {
    throw "Résultat concurrent inattendu: $state"
  }

  Write-Output "PASS: une seule transition de cible gagne et la révision obsolète est refusée."
}
finally {
  try { Invoke-Psql $cleanup | Out-Null } catch { Write-Warning $_ }
}
