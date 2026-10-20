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
  [pscustomobject]@{ ExitCode=$Process.ExitCode; Output=$Process.StandardOutput.ReadToEnd(); Error=$Process.StandardError.ReadToEnd() }
}
function Invoke-Psql([string]$Sql) {
  $result=Wait-Psql (Start-Psql $Sql)
  if($result.ExitCode -ne 0){ throw $result.Error }
  $result.Output.Trim()
}

$owner="99900000-0000-4000-8000-000000000001"
$person="99900000-0000-4000-8100-000000000001"
$account="99900000-0000-4000-8200-000000000001"
$transaction="99900000-0000-4000-8300-000000000001"
$request="99900000-0000-4000-8400-000000000001"
$object="99900000-0000-4000-8800-000000000001"
$path="protected-persons/$person/transactions/$transaction/proof"
$claims='{"sub":"99900000-0000-4000-8000-000000000001","role":"authenticated"}'
$asUser="set local role authenticated; select set_config('request.jwt.claim.sub','$owner',true); select set_config('request.jwt.claims','$claims',true);"

$cleanup=@"
delete from public.document_object_locks where operation_id in (select id from public.document_operations where protected_person_id='$person');
delete from public.document_operation_events where operation_id in (select id from public.document_operations where protected_person_id='$person');
delete from public.document_operation_targets where operation_id in (select id from public.document_operations where protected_person_id='$person');
delete from public.document_operations where protected_person_id='$person';
select set_config('storage.allow_delete_query','true',false);
delete from storage.objects where id='$object';
select set_config('storage.allow_delete_query','false',false);
delete from public.proof_reference_assignments where protected_person_id='$person';
delete from public.transactions where id='$transaction';
delete from public.financial_accounts where id='$account';
delete from public.proof_reference_counters where protected_person_id='$person';
delete from public.protected_persons where id='$person';
delete from auth.users where id='$owner';
"@

try {
  Invoke-Psql $cleanup | Out-Null
  Invoke-Psql @"
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('00000000-0000-0000-0000-000000000000','$owner','authenticated','authenticated','progress-concurrency@example.test','test',now(),'{}','{}',now(),now());
update public.application_user_authorizations set status='active',status_changed_at=now(),account_mode='autonomous' where user_id='$owner';
insert into public.account_subscriptions(owner_id,status,started_at) values('$owner','development',now());
insert into public.protected_persons(id,owner_id,first_name,last_name) values('$person','$owner','Concurrence','Progression');
insert into public.financial_accounts(id,protected_person_id,account_type,institution_name,account_name,initial_balance,initial_balance_date)
values('$account','$person','checking','Banque','Compte',0,'2026-01-01');
insert into public.transactions(id,financial_account_id,transaction_date,transaction_type,label,amount)
values('$transaction','$account','2026-01-02','expense','Course progression',10);
begin; $asUser
select public.begin_transaction_proof_document_operation('$person','$transaction','create','$request');
commit;
"@ | Out-Null

  $operation=Invoke-Psql "select id from public.document_operations where client_request_id='$request';"
  $startFirst=Start-Psql "begin; $asUser select public.start_document_operation('$operation',1); select pg_sleep(2); commit;"
  Start-Sleep -Milliseconds 400
  $startSecond=Start-Psql "begin; $asUser select public.start_document_operation('$operation',1); commit;"
  $startFirstResult=Wait-Psql $startFirst
  $startSecondResult=Wait-Psql $startSecond
  if($startFirstResult.ExitCode -ne 0 -or $startSecondResult.ExitCode -eq 0 -or $startSecondResult.Error -notmatch 'P4O06|révision de l.opération documentaire a changé'){
    throw "Double démarrage non sérialisé: $($startFirstResult.Error) $($startSecondResult.Error)"
  }

  Invoke-Psql "insert into storage.objects(id,bucket_id,name,owner,owner_id,metadata,version) values('$object','transaction-proofs','$path','$owner','$owner','{`"size`":10,`"mimetype`":`"application/pdf`"}','v1');" | Out-Null
  $target=Invoke-Psql "select id from public.document_operation_targets where operation_id='$operation';"
  $applyFirst=Start-Psql "begin; $asUser select public.record_document_operation_target_applied('$operation','$target',2,0); select pg_sleep(2); commit;"
  Start-Sleep -Milliseconds 400
  $applySecond=Start-Psql "begin; $asUser select public.record_document_operation_target_applied('$operation','$target',2,0); commit;"
  $applyFirstResult=Wait-Psql $applyFirst
  $applySecondResult=Wait-Psql $applySecond
  if($applyFirstResult.ExitCode -ne 0 -or $applySecondResult.ExitCode -eq 0 -or $applySecondResult.Error -notmatch 'P4O06|révision de l.opération documentaire a changé'){
    throw "Double preuve d'application non sérialisée: $($applyFirstResult.Error) $($applySecondResult.Error)"
  }
  $state=Invoke-Psql "select operation.state||':'||operation.row_revision||':'||target.application_state||':'||target.target_revision from public.document_operations operation join public.document_operation_targets target on target.operation_id=operation.id where operation.id='$operation';"
  if($state -ne 'executing:3:applied:1'){ throw "État concurrent inattendu: $state" }
  Write-Output "PASS: démarrage et preuve d'application sont sérialisés par leurs révisions optimistes."
}
finally {
  try { Invoke-Psql $cleanup | Out-Null } catch { Write-Warning $_ }
}
