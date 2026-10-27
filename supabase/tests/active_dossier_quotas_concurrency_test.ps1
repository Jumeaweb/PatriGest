param(
  [string]$ContainerName = "supabase_db_PatriGest"
)

$ErrorActionPreference = "Stop"
$docker = (Get-Command docker -ErrorAction Stop).Source

function Start-LocalPsql {
  param([Parameter(Mandatory)][string]$Sql)

  $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $docker
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardInput = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $utf8 = [System.Text.UTF8Encoding]::new($false)
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

function Invoke-LocalPsql {
  param([Parameter(Mandatory)][string]$Sql)

  $process = Start-LocalPsql -Sql $Sql
  $process.WaitForExit()
  $output = $process.StandardOutput.ReadToEnd()
  $errorOutput = $process.StandardError.ReadToEnd()
  if ($process.ExitCode -ne 0) {
    throw "La commande PostgreSQL locale a échoué :`n$errorOutput"
  }
  return $output.Trim()
}

function Get-ProcessResult {
  param([Parameter(Mandatory)][System.Diagnostics.Process]$Process)

  $Process.WaitForExit()
  return [pscustomobject]@{
    ExitCode = $Process.ExitCode
    Output = $Process.StandardOutput.ReadToEnd()
    Error = $Process.StandardError.ReadToEnd()
  }
}

function Wait-OneQuotaFailure {
  param(
    [Parameter(Mandatory)][System.Diagnostics.Process]$First,
    [Parameter(Mandatory)][System.Diagnostics.Process]$Second,
    [Parameter(Mandatory)][string]$Scenario
  )

  $results = @(
    (Get-ProcessResult -Process $First),
    (Get-ProcessResult -Process $Second)
  )
  $successes = @($results | Where-Object ExitCode -eq 0)
  $failures = @($results | Where-Object ExitCode -ne 0)
  if ($successes.Count -ne 1 -or $failures.Count -ne 1) {
    throw "$Scenario : une opération devait réussir et une seule échouer. $($results | ConvertTo-Json -Compress)"
  }
  if ($failures[0].Error -notmatch "capacité de dossiers actifs est atteinte") {
    throw "$Scenario : l’échec n’est pas un refus de quota : $($failures[0].Error)"
  }
}

function Wait-AllSuccess {
  param(
    [Parameter(Mandatory)][System.Diagnostics.Process]$First,
    [Parameter(Mandatory)][System.Diagnostics.Process]$Second,
    [Parameter(Mandatory)][string]$Scenario
  )

  $results = @(
    (Get-ProcessResult -Process $First),
    (Get-ProcessResult -Process $Second)
  )
  $failures = @($results | Where-Object ExitCode -ne 0)
  if ($failures.Count -ne 0) {
    throw "$Scenario : les deux opérations devaient réussir. $($results | ConvertTo-Json -Compress)"
  }
}

function Authenticated-Sql {
  param(
    [Parameter(Mandatory)][string]$OwnerId,
    [Parameter(Mandatory)][string]$Statement
  )

  return @"
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','$OwnerId',true);
select set_config('request.jwt.claims','{"sub":"$OwnerId","role":"authenticated"}',true);
$Statement
commit;
"@
}

$owner1 = "97000000-0000-4000-8000-000000000001"
$owner2 = "97000000-0000-4000-8000-000000000002"
$owner3 = "97000000-0000-4000-8000-000000000003"
$owner4 = "97000000-0000-4000-8000-000000000004"
$owner5 = "97000000-0000-4000-8000-000000000005"

$cleanup = @"
update public.protected_person_archive_runtime_config
set lifecycle_enabled=false, updated_at=clock_timestamp()
where singleton;
delete from public.protected_person_archive_changes
where protected_person_id in (
  select id from public.protected_persons
  where owner_id::text like '97000000-0000-4000-8000-%'
);
delete from public.protected_persons where owner_id::text like '97000000-0000-4000-8000-%';
delete from public.account_subscriptions where owner_id::text like '97000000-0000-4000-8000-%';
delete from auth.users where id::text like '97000000-0000-4000-8000-%';
"@

try {
  Invoke-LocalPsql -Sql $cleanup | Out-Null

  $setup = @"
update public.protected_person_archive_runtime_config
set lifecycle_enabled=true, updated_at=clock_timestamp()
where singleton;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
select
  '00000000-0000-0000-0000-000000000000'::uuid,
  ('97000000-0000-4000-8000-' || lpad(user_number::text,12,'0'))::uuid,
  'authenticated','authenticated','dossier-concurrency-' || user_number || '@example.test',
  'test',now(),'{}','{}',now(),now()
from generate_series(1,5) user_number;

update public.application_user_authorizations
set status='active', status_changed_at=now(), account_mode='autonomous'
where user_id::text like '97000000-0000-4000-8000-%';

insert into public.account_subscriptions(owner_id,plan_key,dossier_capacity_key,status)
values
  ('$owner1',null,null,'development'),
  ('$owner2','essential','included','active'),
  ('$owner3','essential','included','active'),
  ('$owner4','comfort','five','active'),
  ('$owner5','essential','included','active');

insert into public.protected_persons(id,owner_id,first_name,last_name,status,archived_at)
values
  ('97000000-0000-4000-8101-000000000101','$owner1','Créations','Initial','active',null),
  ('97000000-0000-4000-8102-000000000101','$owner2','Mixte','Initial','active',null),
  ('97000000-0000-4000-8102-000000000102','$owner2','Mixte','Archive','archived',now()),
  ('97000000-0000-4000-8103-000000000101','$owner3','Restaurations','Initial','active',null),
  ('97000000-0000-4000-8103-000000000102','$owner3','Restaurations','Archive A','archived',now()),
  ('97000000-0000-4000-8103-000000000103','$owner3','Restaurations','Archive B','archived',now()),
  ('97000000-0000-4000-8104-000000000101','$owner4','Réduction','Un','active',null),
  ('97000000-0000-4000-8104-000000000102','$owner4','Réduction','Deux','active',null),
  ('97000000-0000-4000-8104-000000000103','$owner4','Réduction','Trois','active',null),
  ('97000000-0000-4000-8104-000000000104','$owner4','Réduction','Quatre','active',null),
  ('97000000-0000-4000-8105-000000000101','$owner5','Archive création','Un','active',null),
  ('97000000-0000-4000-8105-000000000102','$owner5','Archive création','Deux','active',null);
"@
  Invoke-LocalPsql -Sql $setup | Out-Null

  $createA = Authenticated-Sql -OwnerId $owner1 -Statement @"
insert into public.protected_persons(id,owner_id,first_name,last_name)
values('97000000-0000-4000-8201-000000000101','$owner1','Concurrent','Création A');
"@
  $createB = Authenticated-Sql -OwnerId $owner1 -Statement @"
insert into public.protected_persons(id,owner_id,first_name,last_name)
values('97000000-0000-4000-8201-000000000102','$owner1','Concurrent','Création B');
"@
  Wait-OneQuotaFailure -First (Start-LocalPsql -Sql $createA) -Second (Start-LocalPsql -Sql $createB) -Scenario "Deux créations"

  $mixedCreate = Authenticated-Sql -OwnerId $owner2 -Statement @"
insert into public.protected_persons(id,owner_id,first_name,last_name)
values('97000000-0000-4000-8202-000000000101','$owner2','Concurrent','Création');
"@
  $mixedRestore = Authenticated-Sql -OwnerId $owner2 -Statement @"
select public.restore_protected_person(
  '97000000-0000-4000-8102-000000000102', 1, 'Test de restauration concurrente'
);
"@
  Wait-OneQuotaFailure -First (Start-LocalPsql -Sql $mixedCreate) -Second (Start-LocalPsql -Sql $mixedRestore) -Scenario "Création et restauration"

  $restoreA = Authenticated-Sql -OwnerId $owner3 -Statement @"
select public.restore_protected_person(
  '97000000-0000-4000-8103-000000000102', 1, 'Test de restauration concurrente A'
);
"@
  $restoreB = Authenticated-Sql -OwnerId $owner3 -Statement @"
select public.restore_protected_person(
  '97000000-0000-4000-8103-000000000103', 1, 'Test de restauration concurrente B'
);
"@
  Wait-OneQuotaFailure -First (Start-LocalPsql -Sql $restoreA) -Second (Start-LocalPsql -Sql $restoreB) -Scenario "Deux restaurations"

  $reduceCapacity = @"
begin;
update public.account_subscriptions
set plan_key='essential',dossier_capacity_key='included'
where owner_id='$owner4' and ended_at is null;
select pg_sleep(1);
commit;
"@
  $createDuringReduction = Authenticated-Sql -OwnerId $owner4 -Statement @"
insert into public.protected_persons(id,owner_id,first_name,last_name)
values('97000000-0000-4000-8204-000000000101','$owner4','Concurrent','Réduction');
"@
  $reductionProcess = Start-LocalPsql -Sql $reduceCapacity
  Start-Sleep -Milliseconds 150
  $creationProcess = Start-LocalPsql -Sql $createDuringReduction
  Wait-OneQuotaFailure -First $reductionProcess -Second $creationProcess -Scenario "Réduction et création"

  $archive = Authenticated-Sql -OwnerId $owner5 -Statement @"
select public.archive_protected_person(
  '97000000-0000-4000-8105-000000000101', 1, 'Test d’archivage concurrent'
);
select pg_sleep(1);
"@
  $createAfterArchive = Authenticated-Sql -OwnerId $owner5 -Statement @"
insert into public.protected_persons(id,owner_id,first_name,last_name)
values('97000000-0000-4000-8205-000000000101','$owner5','Concurrent','Après archive');
"@
  $archiveProcess = Start-LocalPsql -Sql $archive
  Start-Sleep -Milliseconds 150
  $createProcess = Start-LocalPsql -Sql $createAfterArchive
  Wait-AllSuccess -First $archiveProcess -Second $createProcess -Scenario "Archivage et création"

  $finalState = Invoke-LocalPsql -Sql @"
select string_agg(owner_id || ':' || active_count, ',' order by owner_id)
from (
  select owner_id, count(*) filter (where status='active') as active_count
  from public.protected_persons
  where owner_id::text like '97000000-0000-4000-8000-%'
  group by owner_id
) counts;
"@
  $expected = "$owner1`:2,$owner2`:2,$owner3`:2,$owner4`:4,$owner5`:2"
  if ($finalState -ne $expected) {
    throw "État final inattendu : $finalState (attendu : $expected)."
  }

  Write-Output "PASS: 5 scénarios, 10 connexions PostgreSQL réelles, aucun dépassement concurrent créé."
}
finally {
  try { Invoke-LocalPsql -Sql $cleanup | Out-Null } catch { Write-Warning $_ }
}
