param([string]$ContainerName = "supabase_db_PatriGest")
$ErrorActionPreference = "Stop"
$docker = (Get-Command docker -ErrorAction Stop).Source
$utf8 = [System.Text.UTF8Encoding]::new($false)

function Start-Psql([string]$Sql) {
  $si=[System.Diagnostics.ProcessStartInfo]::new(); $si.FileName=$docker
  $si.UseShellExecute=$false; $si.CreateNoWindow=$true
  $si.RedirectStandardInput=$true; $si.RedirectStandardOutput=$true; $si.RedirectStandardError=$true
  $si.StandardInputEncoding=$utf8; $si.StandardOutputEncoding=$utf8; $si.StandardErrorEncoding=$utf8
  $si.Arguments="exec -i `"$ContainerName`" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -At -f -"
  $p=[System.Diagnostics.Process]::new(); $p.StartInfo=$si; [void]$p.Start()
  $p.StandardInput.Write($Sql); $p.StandardInput.Close(); return $p
}
function Wait-Psql($Process) {
  $Process.WaitForExit()
  [pscustomobject]@{ExitCode=$Process.ExitCode;Output=$Process.StandardOutput.ReadToEnd();Error=$Process.StandardError.ReadToEnd()}
}
function Invoke-Psql([string]$Sql) {
  $r=Wait-Psql (Start-Psql $Sql); if($r.ExitCode -ne 0){throw $r.Error}; $r.Output.Trim()
}

$owner="99700000-0000-4000-8000-000000000001"
$person="99700000-0000-4000-8100-000000000001"
$account="99700000-0000-4000-8200-000000000001"
$transaction="99700000-0000-4000-8300-000000000001"
$claims='{"sub":"99700000-0000-4000-8000-000000000001","role":"authenticated"}'
$asUser="set local role authenticated; select set_config('request.jwt.claim.sub','$owner',true); select set_config('request.jwt.claims','$claims',true);"

$cleanup=@"
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
update public.protected_person_archive_runtime_config set lifecycle_enabled=false,updated_at=clock_timestamp() where singleton;
"@

try {
  Invoke-Psql $cleanup | Out-Null
  Invoke-Psql @"
update public.protected_person_archive_runtime_config set lifecycle_enabled=true,updated_at=clock_timestamp() where singleton;
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('00000000-0000-0000-0000-000000000000','$owner','authenticated','authenticated','reservation-concurrency@example.test','test',now(),'{}','{}',now(),now());
update public.application_user_authorizations set status='active',status_changed_at=now(),account_mode='autonomous' where user_id='$owner';
insert into public.account_subscriptions(owner_id,status,started_at) values('$owner','development',now());
insert into public.protected_persons(id,owner_id,first_name,last_name) values('$person','$owner','Concurrence','Documentaire');
insert into public.financial_accounts(id,protected_person_id,account_type,institution_name,account_name,initial_balance,initial_balance_date)
values('$account','$person','checking','Banque test','Compte test',0,'2026-01-01');
insert into public.transactions(id,financial_account_id,transaction_date,transaction_type,label,amount)
values('$transaction','$account','2026-01-02','expense','Test',10);
"@ | Out-Null

  $reservationFirst=Start-Psql "begin; $asUser select public.begin_transaction_proof_document_operation('$person','$transaction','create','99700000-0000-4000-8400-000000000001'); select pg_sleep(2); commit;"
  Start-Sleep -Milliseconds 400
  $archiveSecond=Start-Psql "begin; $asUser select public.archive_protected_person('$person',1,'Course réservation'); commit;"
  $r1=Wait-Psql $reservationFirst; $r2=Wait-Psql $archiveSecond
  if($r1.ExitCode -ne 0 -or $r2.ExitCode -eq 0 -or $r2.Error -notmatch 'P4A06|opération documentaire en cours bloque'){throw "Réservation puis archivage non sérialisés: $($r1.Error) $($r2.Error)"}

  Invoke-Psql "select public.transition_document_operation((select id from public.document_operations where client_request_id='99700000-0000-4000-8400-000000000001'),'reserved','cancelled');" | Out-Null
  $archiveFirst=Start-Psql "begin; $asUser select public.archive_protected_person('$person',1,'Course archivage'); select pg_sleep(2); commit;"
  Start-Sleep -Milliseconds 400
  $reservationSecond=Start-Psql "begin; $asUser select public.begin_transaction_proof_document_operation('$person','$transaction','create','99700000-0000-4000-8400-000000000002'); commit;"
  $r3=Wait-Psql $archiveFirst; $r4=Wait-Psql $reservationSecond
  if($r3.ExitCode -ne 0 -or $r4.ExitCode -eq 0 -or $r4.Error -notmatch 'P4O03|dossier doit être actif'){throw "Archivage puis réservation non sérialisés: $($r3.Error) $($r4.Error)"}

  Invoke-Psql "begin; $asUser select public.restore_protected_person('$person',2,'Test conflit'); commit;" | Out-Null
  $samePathFirst=Start-Psql "begin; $asUser select public.begin_transaction_proof_document_operation('$person','$transaction','create','99700000-0000-4000-8400-000000000003'); select pg_sleep(2); commit;"
  Start-Sleep -Milliseconds 400
  $samePathSecond=Start-Psql "begin; $asUser select public.begin_transaction_proof_document_operation('$person','$transaction','create','99700000-0000-4000-8400-000000000004'); commit;"
  $r5=Wait-Psql $samePathFirst; $r6=Wait-Psql $samePathSecond
  if($r5.ExitCode -ne 0 -or $r6.ExitCode -eq 0 -or $r6.Error -notmatch 'P4O05|déjà réservé par une autre opération'){throw "Conflit de chemin non sérialisé: $($r5.Error) $($r6.Error)"}
  Write-Output "PASS: réservation/archivage, archivage/réservation et conflit de chemin sérialisés."
}
finally { try { Invoke-Psql $cleanup | Out-Null } catch { Write-Warning $_ } }
