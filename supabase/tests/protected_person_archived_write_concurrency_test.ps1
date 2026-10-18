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
  $startInfo.StandardInputEncoding = [System.Text.UTF8Encoding]::new($false)
  $startInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
  $startInfo.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)
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

function Get-LocalPsqlResult {
  param([Parameter(Mandatory)][System.Diagnostics.Process]$Process)

  $Process.WaitForExit()
  return [pscustomobject]@{
    ExitCode = $Process.ExitCode
    Output = $Process.StandardOutput.ReadToEnd()
    Error = $Process.StandardError.ReadToEnd()
  }
}

$ownerId = "99000000-0000-4000-8000-000000000001"
$dossierId = "99000000-0000-4000-8100-000000000001"
$accountId = "99000000-0000-4000-8200-000000000001"
$claims = '{"sub":"99000000-0000-4000-8000-000000000001","role":"authenticated"}'

$cleanup = @"
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','$ownerId',true);
select set_config('request.jwt.claims','$claims',true);
do `$cleanup`$
declare
  dossier_status text;
  dossier_revision bigint;
begin
  select status, archive_revision
  into dossier_status, dossier_revision
  from public.protected_persons
  where id = '$dossierId';

  if dossier_status = 'archived' then
    perform public.restore_protected_person(
      '$dossierId', dossier_revision, 'Nettoyage du test concurrent'
    );
  end if;
end;
`$cleanup`$;
commit;

delete from public.financial_accounts where id = '$accountId';
delete from public.protected_person_archive_changes
where protected_person_id = '$dossierId';
delete from public.protected_persons where id = '$dossierId';
delete from auth.users where id = '$ownerId';
"@

try {
  Invoke-LocalPsql -Sql $cleanup | Out-Null

  Invoke-LocalPsql -Sql @"
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000000', '$ownerId',
  'authenticated', 'authenticated', 'archive-concurrency@example.test',
  'test-hash', now(), '{"provider":"email","providers":["email"]}', '{}',
  now(), now()
);

update public.application_user_authorizations
set status = 'active', status_changed_at = now(), account_mode = 'autonomous'
where user_id = '$ownerId';

insert into public.account_subscriptions(
  owner_id, plan_key, dossier_capacity_key, status, started_at
) values ('$ownerId', null, null, 'development', now());

insert into public.protected_persons(id, owner_id, first_name, last_name)
values ('$dossierId', '$ownerId', 'Concurrence', 'Archivage');

insert into public.financial_accounts(
  id, protected_person_id, account_type, institution_name, account_name,
  initial_balance, initial_balance_date
) values (
  '$accountId', '$dossierId', 'checking', 'Banque test',
  'Compte concurrent', 10, '2026-01-01'
);
"@ | Out-Null

  $writeFirst = Start-LocalPsql -Sql @"
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','$ownerId',true);
select set_config('request.jwt.claims','$claims',true);
update public.financial_accounts
set notes = 'Écriture validée avant archivage'
where id = '$accountId';
select pg_sleep(2);
commit;
"@
  Start-Sleep -Milliseconds 400
  $archiveSecond = Start-LocalPsql -Sql @"
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','$ownerId',true);
select set_config('request.jwt.claims','$claims',true);
select public.archive_protected_person(
  '$dossierId', 1, 'Archivage après écriture concurrente'
);
commit;
"@

  $writeFirstResult = Get-LocalPsqlResult -Process $writeFirst
  $archiveSecondResult = Get-LocalPsqlResult -Process $archiveSecond
  if ($writeFirstResult.ExitCode -ne 0 -or $archiveSecondResult.ExitCode -ne 0) {
    throw "Écriture puis archivage : les deux opérations devaient réussir après sérialisation. Écriture=$($writeFirstResult | ConvertTo-Json -Compress) Archivage=$($archiveSecondResult | ConvertTo-Json -Compress)"
  }

  $firstState = Invoke-LocalPsql -Sql @"
select person.status || ':' || person.archive_revision || ':' || account.notes
from public.protected_persons person
join public.financial_accounts account on account.protected_person_id = person.id
where person.id = '$dossierId';
"@
  if ($firstState -ne "archived:2:Écriture validée avant archivage") {
    throw "Écriture puis archivage : état final inattendu ($firstState)."
  }

  Invoke-LocalPsql -Sql @"
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','$ownerId',true);
select set_config('request.jwt.claims','$claims',true);
select public.restore_protected_person('$dossierId', 2, 'Second scénario');
commit;
"@ | Out-Null

  $archiveFirst = Start-LocalPsql -Sql @"
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','$ownerId',true);
select set_config('request.jwt.claims','$claims',true);
select public.archive_protected_person(
  '$dossierId', 3, 'Archivage avant écriture concurrente'
);
select pg_sleep(2);
commit;
"@
  Start-Sleep -Milliseconds 400
  $writeSecond = Start-LocalPsql -Sql @"
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','$ownerId',true);
select set_config('request.jwt.claims','$claims',true);
update public.financial_accounts
set notes = 'Écriture interdite après archivage'
where id = '$accountId';
commit;
"@

  $archiveFirstResult = Get-LocalPsqlResult -Process $archiveFirst
  $writeSecondResult = Get-LocalPsqlResult -Process $writeSecond
  if ($archiveFirstResult.ExitCode -ne 0) {
    throw "Archivage puis écriture : l’archivage devait réussir. Résultat=$($archiveFirstResult | ConvertTo-Json -Compress)"
  }
  if ($writeSecondResult.ExitCode -eq 0 -or
      $writeSecondResult.Error -notmatch 'P4R01|Ce dossier est archivé') {
    throw "Archivage puis écriture : l’écriture devait échouer avec la garde d’archive."
  }

  $secondState = Invoke-LocalPsql -Sql @"
select person.status || ':' || person.archive_revision || ':' || account.notes
from public.protected_persons person
join public.financial_accounts account on account.protected_person_id = person.id
where person.id = '$dossierId';
"@
  if ($secondState -ne "archived:4:Écriture validée avant archivage") {
    throw "Archivage puis écriture : état final inattendu ($secondState)."
  }

  Write-Output "PASS: 2 scénarios, 4 connexions PostgreSQL réelles, sérialisation archive/écriture respectée."
}
finally {
  try { Invoke-LocalPsql -Sql $cleanup | Out-Null } catch { Write-Warning $_ }
}
