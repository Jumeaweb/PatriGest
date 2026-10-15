param(
  [string]$ContainerName = "supabase_db_PatriGest"
)

$ErrorActionPreference = "Stop"
$docker = (Get-Command docker -ErrorAction Stop).Source

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

function Start-LocalPsql {
  param([Parameter(Mandatory)][string]$Sql)

  $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $docker
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardInput = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.Arguments = "exec -i `"$ContainerName`" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -At -f -"

  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  [void]$process.Start()
  $process.StandardInput.Write($Sql)
  $process.StandardInput.Close()
  return $process
}

function Wait-LocalPsqlPair {
  param(
    [Parameter(Mandatory)][System.Diagnostics.Process]$First,
    [Parameter(Mandatory)][System.Diagnostics.Process]$Second,
    [Parameter(Mandatory)][string]$Scenario
  )

  $First.WaitForExit()
  $Second.WaitForExit()
  $results = @(
    [pscustomobject]@{
      ExitCode = $First.ExitCode
      Output = $First.StandardOutput.ReadToEnd()
      Error = $First.StandardError.ReadToEnd()
    },
    [pscustomobject]@{
      ExitCode = $Second.ExitCode
      Output = $Second.StandardOutput.ReadToEnd()
      Error = $Second.StandardError.ReadToEnd()
    }
  )

  $successes = @($results | Where-Object ExitCode -eq 0)
  $failures = @($results | Where-Object ExitCode -ne 0)
  if ($successes.Count -ne 1 -or $failures.Count -ne 1) {
    throw "$Scenario : une opération devait réussir et une seule devait échouer. Résultats : $($results | ConvertTo-Json -Compress)"
  }
  if ($failures[0].Error -notmatch "limite de gestionnaires") {
    throw "$Scenario : l’échec n’est pas un refus de quota : $($failures[0].Error)"
  }
}

$ownerId = "93000000-0000-4000-8000-000000000001"
$invitationDossierId = "93000000-0000-4000-8000-000000000101"
$mixedDossierId = "93000000-0000-4000-8000-000000000102"
$readerAccessId = "93000000-0000-4000-8000-000000000205"
$claims = '{"sub":"93000000-0000-4000-8000-000000000001","role":"authenticated","email":"share-concurrency-owner@example.test"}'

$cleanup = @"
delete from public.protected_persons
where id in ('$invitationDossierId'::uuid, '$mixedDossierId'::uuid);
delete from auth.users
where id::text like '93000000-0000-4000-8000-%';
"@

try {
  Invoke-LocalPsql -Sql $cleanup | Out-Null

  $setup = @"
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
select
  '00000000-0000-0000-0000-000000000000'::uuid,
  ('93000000-0000-4000-8000-' || lpad(user_number::text, 12, '0'))::uuid,
  'authenticated', 'authenticated',
  case when user_number = 1 then 'share-concurrency-owner@example.test'
       else 'share-concurrency-user-' || user_number || '@example.test' end,
  'test-hash', now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb, now(), now()
from generate_series(1, 6) user_number;

update public.application_user_authorizations
set status = 'active', status_changed_at = now()
where user_id::text like '93000000-0000-4000-8000-%';

insert into public.protected_persons(id, owner_id, first_name, last_name)
values
  ('$invitationDossierId', '$ownerId', 'Concurrence', 'Invitations'),
  ('$mixedDossierId', '$ownerId', 'Concurrence', 'Mixte');

insert into public.protected_person_invitations(
  protected_person_id, email, role, token_hash, expires_at, invited_by
)
select
  '$invitationDossierId'::uuid,
  'share-concurrency-pending-' || slot || '@example.test',
  'manager',
  lpad(to_hex(900 + slot), 64, '0'),
  now() + interval '1 day',
  '$ownerId'::uuid
from generate_series(1, 4) slot;

insert into public.protected_person_access(
  id, protected_person_id, user_id, role, invited_by
)
select
  ('93000000-0000-4000-8000-' || lpad((200 + slot)::text, 12, '0'))::uuid,
  '$mixedDossierId'::uuid,
  ('93000000-0000-4000-8000-' || lpad((1 + slot)::text, 12, '0'))::uuid,
  'manager',
  '$ownerId'::uuid
from generate_series(1, 4) slot;

insert into public.protected_person_access(
  id, protected_person_id, user_id, role, invited_by
) values (
  '$readerAccessId', '$mixedDossierId',
  '93000000-0000-4000-8000-000000000006', 'read_only', '$ownerId'
);
"@
  Invoke-LocalPsql -Sql $setup | Out-Null

  $firstInvitation = @"
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','$ownerId',true);
select set_config('request.jwt.claims','$claims',true);
select public.issue_protected_person_invitation(
  '$invitationDossierId','share-concurrency-a@example.test','manager',
  lpad(to_hex(950),64,'0'),now()+interval '1 day'
);
commit;
"@
  $secondInvitation = @"
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','$ownerId',true);
select set_config('request.jwt.claims','$claims',true);
select public.issue_protected_person_invitation(
  '$invitationDossierId','share-concurrency-b@example.test','manager',
  lpad(to_hex(951),64,'0'),now()+interval '1 day'
);
commit;
"@
  $pair = @(
    (Start-LocalPsql -Sql $firstInvitation),
    (Start-LocalPsql -Sql $secondInvitation)
  )
  Wait-LocalPsqlPair -First $pair[0] -Second $pair[1] -Scenario "Deux invitations concurrentes"

  $invitationCount = Invoke-LocalPsql -Sql @"
select used_count
from public.get_protected_person_share_occupancy('$invitationDossierId')
where share_role = 'manager';
"@
  if ($invitationCount -ne "5") {
    throw "Deux invitations concurrentes : occupation finale inattendue ($invitationCount au lieu de 5)."
  }

  $roleChange = @"
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','$ownerId',true);
select set_config('request.jwt.claims','$claims',true);
select public.change_protected_person_access_role(
  '$mixedDossierId','$readerAccessId','manager'
);
commit;
"@
  $mixedInvitation = @"
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','$ownerId',true);
select set_config('request.jwt.claims','$claims',true);
select public.issue_protected_person_invitation(
  '$mixedDossierId','share-concurrency-mixed@example.test','manager',
  lpad(to_hex(952),64,'0'),now()+interval '1 day'
);
commit;
"@
  $mixedPair = @(
    (Start-LocalPsql -Sql $roleChange),
    (Start-LocalPsql -Sql $mixedInvitation)
  )
  Wait-LocalPsqlPair -First $mixedPair[0] -Second $mixedPair[1] -Scenario "Invitation et changement de rôle concurrents"

  $mixedResult = Invoke-LocalPsql -Sql @"
select
  occupancy.used_count || ':' ||
  ((select role from public.protected_person_access where id = '$readerAccessId') = 'manager')::integer || ':' ||
  (exists (
    select 1 from public.protected_person_invitations
    where protected_person_id = '$mixedDossierId'
      and email = 'share-concurrency-mixed@example.test'
      and accepted_at is null and revoked_at is null and declined_at is null
      and expires_at > now()
  ))::integer
from public.get_protected_person_share_occupancy('$mixedDossierId') occupancy
where occupancy.share_role = 'manager';
"@
  if ($mixedResult -notin @("5:1:0", "5:0:1")) {
    throw "Invitation et changement de rôle concurrents : état final incohérent ($mixedResult)."
  }

  Write-Output "PASS: 2 scénarios, 4 connexions PostgreSQL réelles, quotas finaux 5/5 respectés."
}
finally {
  try { Invoke-LocalPsql -Sql $cleanup | Out-Null } catch { Write-Warning $_ }
}
