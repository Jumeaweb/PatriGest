param(
  [string]$ContainerName = "supabase_db_PatriGest"
)

$ErrorActionPreference = "Stop"
$docker = (Get-Command docker -ErrorAction Stop).Source
$utf8 = [System.Text.UTF8Encoding]::new($false)

function Start-LocalPsql {
  param([Parameter(Mandatory)][string]$Sql)

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

function Get-LocalPsqlResult {
  param([Parameter(Mandatory)][System.Diagnostics.Process]$Process)

  $Process.WaitForExit()
  return [pscustomobject]@{
    ExitCode = $Process.ExitCode
    Output = $Process.StandardOutput.ReadToEnd()
    Error = $Process.StandardError.ReadToEnd()
  }
}

function Invoke-LocalPsql {
  param([Parameter(Mandatory)][string]$Sql)

  $result = Get-LocalPsqlResult -Process (Start-LocalPsql -Sql $Sql)
  if ($result.ExitCode -ne 0) {
    throw "La commande PostgreSQL locale a échoué :`n$($result.Error)"
  }
  return $result.Output.Trim()
}

function Assert-Success {
  param(
    [Parameter(Mandatory)]$Result,
    [Parameter(Mandatory)][string]$Scenario
  )

  if ($Result.ExitCode -ne 0) {
    throw "$Scenario devait réussir : $($Result | ConvertTo-Json -Compress)"
  }
}

function Assert-ArchiveRefusal {
  param(
    [Parameter(Mandatory)]$Result,
    [Parameter(Mandatory)][string]$Scenario
  )

  if ($Result.ExitCode -eq 0 -or
      $Result.Error -notmatch 'P4R01|Ce dossier est archivé') {
    throw "$Scenario devait être refusé par la garde d’archive : $($Result | ConvertTo-Json -Compress)"
  }
}

$ownerId = "9b000000-0000-4000-8000-000000000001"
$managerId = "9b000000-0000-4000-8000-000000000002"
$readerId = "9b000000-0000-4000-8000-000000000003"
$inviteeId = "9b000000-0000-4000-8000-000000000004"
$dossierId = "9b000000-0000-4000-8100-000000000001"
$readerAccessId = "9b000000-0000-4000-8200-000000000001"
$acceptInvitationId = "9b000000-0000-4000-8300-000000000001"
$revokeInvitationId = "9b000000-0000-4000-8300-000000000002"
$acceptToken = "$(('a1').PadLeft(64, '0'))"
$revokeToken = "$(('a2').PadLeft(64, '0'))"
$ownerClaims = '{"sub":"9b000000-0000-4000-8000-000000000001","role":"authenticated","email":"archive-sharing-owner@example.test"}'
$inviteeClaims = '{"sub":"9b000000-0000-4000-8000-000000000004","role":"authenticated","email":"archive-sharing-invitee@example.test"}'

$cleanup = @"
update public.protected_person_archive_runtime_config
set lifecycle_enabled = true, updated_at = clock_timestamp()
where singleton;
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','$ownerId',true);
select set_config('request.jwt.claims','$ownerClaims',true);
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
      '$dossierId', dossier_revision, 'Nettoyage du test concurrent de partage'
    );
  end if;
end;
`$cleanup`$;
commit;

update public.protected_person_archive_runtime_config
set lifecycle_enabled = false, updated_at = clock_timestamp()
where singleton;

delete from public.protected_person_invitations
where protected_person_id = '$dossierId';
delete from public.protected_person_access
where protected_person_id = '$dossierId';
delete from public.protected_person_archive_changes
where protected_person_id = '$dossierId';
delete from public.protected_persons where id = '$dossierId';
delete from auth.users
where id in ('$ownerId', '$managerId', '$readerId', '$inviteeId');
"@

function Start-Archive {
  param(
    [Parameter(Mandatory)][int]$ExpectedRevision,
    [Parameter(Mandatory)][string]$Reason
  )

  return Start-LocalPsql -Sql @"
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','$ownerId',true);
select set_config('request.jwt.claims','$ownerClaims',true);
select public.archive_protected_person('$dossierId', $ExpectedRevision, '$Reason');
select pg_sleep(2);
commit;
"@
}

function Invoke-Restore {
  param([Parameter(Mandatory)][int]$ExpectedRevision)

  Invoke-LocalPsql -Sql @"
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','$ownerId',true);
select set_config('request.jwt.claims','$ownerClaims',true);
select public.restore_protected_person(
  '$dossierId', $ExpectedRevision, 'Préparation du scénario concurrent suivant'
);
commit;
"@ | Out-Null
}

try {
  Invoke-LocalPsql -Sql $cleanup | Out-Null

  Invoke-LocalPsql -Sql @"
update public.protected_person_archive_runtime_config
set lifecycle_enabled = true, updated_at = clock_timestamp()
where singleton;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000','$ownerId','authenticated','authenticated','archive-sharing-owner@example.test','test-hash',now(),'{"provider":"email","providers":["email"]}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','$managerId','authenticated','authenticated','archive-sharing-manager@example.test','test-hash',now(),'{"provider":"email","providers":["email"]}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','$readerId','authenticated','authenticated','archive-sharing-reader@example.test','test-hash',now(),'{"provider":"email","providers":["email"]}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','$inviteeId','authenticated','authenticated','archive-sharing-invitee@example.test','test-hash',now(),'{"provider":"email","providers":["email"]}','{}',now(),now());

update public.application_user_authorizations
set status = 'active', status_changed_at = now()
where user_id in ('$ownerId', '$managerId', '$readerId', '$inviteeId');

update public.application_user_authorizations
set account_mode = 'autonomous'
where user_id = '$ownerId';

insert into public.account_subscriptions(owner_id, status, started_at)
values ('$ownerId', 'development', now());

insert into public.protected_persons(id, owner_id, first_name, last_name)
values ('$dossierId', '$ownerId', 'Concurrence', 'Partage');

insert into public.protected_person_access(
  id, protected_person_id, user_id, role, invited_by
) values (
  '$readerAccessId', '$dossierId', '$readerId', 'read_only', '$ownerId'
);

insert into public.protected_person_invitations(
  id, protected_person_id, email, role, token_hash, expires_at, invited_by
) values
  ('$acceptInvitationId','$dossierId','archive-sharing-invitee@example.test','read_only','$acceptToken',now()+interval '1 day','$ownerId'),
  ('$revokeInvitationId','$dossierId','archive-sharing-revoke@example.test','read_only','$revokeToken',now()+interval '1 day','$ownerId');
"@ | Out-Null

  $archive = Start-Archive -ExpectedRevision 1 -Reason "Concurrence création"
  Start-Sleep -Milliseconds 400
  $issue = Start-LocalPsql -Sql @"
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','$ownerId',true);
select set_config('request.jwt.claims','$ownerClaims',true);
select public.issue_protected_person_invitation(
  '$dossierId','archive-sharing-new@example.test','read_only',
  lpad(to_hex(991),64,'0'),now()+interval '1 day'
);
commit;
"@
  $archiveResult = Get-LocalPsqlResult -Process $archive
  $issueResult = Get-LocalPsqlResult -Process $issue
  Assert-Success -Result $archiveResult -Scenario "Archivage concurrent à la création"
  Assert-ArchiveRefusal -Result $issueResult -Scenario "Création concurrente à l’archivage"

  Invoke-Restore -ExpectedRevision 2

  $archive = Start-Archive -ExpectedRevision 3 -Reason "Concurrence acceptation"
  Start-Sleep -Milliseconds 400
  $accept = Start-LocalPsql -Sql @"
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','$inviteeId',true);
select set_config('request.jwt.claims','$inviteeClaims',true);
select public.accept_protected_person_invitation('$acceptToken');
commit;
"@
  $archiveResult = Get-LocalPsqlResult -Process $archive
  $acceptResult = Get-LocalPsqlResult -Process $accept
  Assert-Success -Result $archiveResult -Scenario "Archivage concurrent à l’acceptation"
  Assert-ArchiveRefusal -Result $acceptResult -Scenario "Acceptation concurrente à l’archivage"

  $restore = Start-LocalPsql -Sql @"
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','$ownerId',true);
select set_config('request.jwt.claims','$ownerClaims',true);
select public.restore_protected_person('$dossierId', 4, 'Concurrence restauration');
select pg_sleep(2);
commit;
"@
  Start-Sleep -Milliseconds 400
  $accept = Start-LocalPsql -Sql @"
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','$inviteeId',true);
select set_config('request.jwt.claims','$inviteeClaims',true);
select public.accept_protected_person_invitation('$acceptToken');
commit;
"@
  $restoreResult = Get-LocalPsqlResult -Process $restore
  $acceptResult = Get-LocalPsqlResult -Process $accept
  Assert-Success -Result $restoreResult -Scenario "Restauration concurrente à l’acceptation"
  Assert-Success -Result $acceptResult -Scenario "Acceptation après restauration concurrente"

  $archive = Start-Archive -ExpectedRevision 5 -Reason "Concurrence promotion"
  Start-Sleep -Milliseconds 400
  $promotion = Start-LocalPsql -Sql @"
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','$ownerId',true);
select set_config('request.jwt.claims','$ownerClaims',true);
select public.change_protected_person_access_role(
  '$dossierId','$readerAccessId','manager'
);
commit;
"@
  $archiveResult = Get-LocalPsqlResult -Process $archive
  $promotionResult = Get-LocalPsqlResult -Process $promotion
  Assert-Success -Result $archiveResult -Scenario "Archivage concurrent à la promotion"
  Assert-ArchiveRefusal -Result $promotionResult -Scenario "Promotion concurrente à l’archivage"

  Invoke-Restore -ExpectedRevision 6

  $archive = Start-Archive -ExpectedRevision 7 -Reason "Concurrence révocation"
  Start-Sleep -Milliseconds 400
  $revoke = Start-LocalPsql -Sql @"
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','$ownerId',true);
select set_config('request.jwt.claims','$ownerClaims',true);
select public.revoke_protected_person_invitation('$revokeInvitationId');
commit;
"@
  $archiveResult = Get-LocalPsqlResult -Process $archive
  $revokeResult = Get-LocalPsqlResult -Process $revoke
  Assert-Success -Result $archiveResult -Scenario "Archivage concurrent à la révocation"
  Assert-Success -Result $revokeResult -Scenario "Révocation après archivage concurrent"

  $finalState = Invoke-LocalPsql -Sql @"
select
  person.status || ':' || person.archive_revision || ':' ||
  (exists (
    select 1 from public.protected_person_access access
    where access.protected_person_id = person.id
      and access.user_id = '$inviteeId'
      and access.role = 'read_only'
  ))::integer || ':' ||
  (exists (
    select 1 from public.protected_person_invitations invitation
    where invitation.id = '$revokeInvitationId'
      and invitation.revoked_at is not null
  ))::integer
from public.protected_persons person
where person.id = '$dossierId';
"@
  if ($finalState -ne "archived:8:1:1") {
    throw "État final concurrent inattendu : $finalState"
  }

  Write-Output "PASS: 5 scénarios, 10 connexions PostgreSQL réelles, cycle de vie et partage sérialisés."
}
finally {
  try { Invoke-LocalPsql -Sql $cleanup | Out-Null } catch { Write-Warning $_ }
}
