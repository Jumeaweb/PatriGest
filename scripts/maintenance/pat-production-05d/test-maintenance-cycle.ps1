[CmdletBinding()]
param(
  [string] $SupabaseWorkdir = 'C:\Users\jerom\Documents\PatriGest-Restore-20261029',
  [string] $ExpectedProjectId = 'PatriGest-Restore-20261029',
  [string] $ExpectedApiUrl = 'http://127.0.0.1:55321',
  [int] $ExpectedDbPort = 55322,
  [string] $DbContainer = 'supabase_db_PatriGest-Restore-20261029',
  [string] $StorageContainer = 'supabase_storage_PatriGest-Restore-20261029',
  [string] $SupabaseCli = 'C:\Users\jerom\AppData\Local\npm-cache\_npx\aa8e5c70f9d8d161\node_modules\@supabase\cli-windows-x64\bin\supabase.exe'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-Condition {
  param([bool] $Condition, [string] $Message)

  if (-not $Condition) {
    throw $Message
  }
}

function Get-SupabaseEnvironment {
  $lines = & $SupabaseCli status --workdir $SupabaseWorkdir -o env 2>$null
  if ($LASTEXITCODE -ne 0) {
    throw 'Supabase CLI could not inspect the isolated stack.'
  }

  $result = @{}
  foreach ($line in $lines) {
    if ($line -match '^([A-Z_]+)="?(.*?)"?$') {
      $result[$matches[1]] = $matches[2].TrimEnd('"')
    }
  }
  return $result
}

function Invoke-DbSql {
  param([Parameter(Mandatory)] [string] $Sql)

  $result = & docker.exe exec $DbContainer psql -X -U postgres -d postgres `
    -v ON_ERROR_STOP=1 -Atc $Sql
  if ($LASTEXITCODE -ne 0) {
    throw 'A PostgreSQL verification command failed.'
  }
  return ,@($result)
}

function Invoke-DbFile {
  param([Parameter(Mandatory)] [string] $LocalPath)

  $containerPath = '/tmp/' + [IO.Path]::GetFileName($LocalPath)
  & docker.exe cp $LocalPath "${DbContainer}:$containerPath" | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Could not copy $LocalPath into the isolated database container."
  }
  $result = & docker.exe exec $DbContainer psql -X -U postgres -d postgres `
    -v ON_ERROR_STOP=1 -f $containerPath
  if ($LASTEXITCODE -ne 0) {
    throw "PostgreSQL script failed: $LocalPath"
  }
  return ,@($result)
}

function ConvertTo-Base64Url {
  param([byte[]] $Bytes)

  return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function New-LocalJwt {
  param(
    [Parameter(Mandatory)] [string] $Secret,
    [Parameter(Mandatory)] [string] $Subject,
    [Parameter(Mandatory)] [string] $Role
  )

  $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $header = ConvertTo-Base64Url ([Text.Encoding]::UTF8.GetBytes(
    (@{ alg = 'HS256'; typ = 'JWT' } | ConvertTo-Json -Compress)
  ))
  $payload = ConvertTo-Base64Url ([Text.Encoding]::UTF8.GetBytes(
    (@{
      aud = 'authenticated'
      exp = $now + 3600
      iat = $now
      iss = 'supabase-demo'
      role = $Role
      sub = $Subject
    } | ConvertTo-Json -Compress)
  ))
  $unsigned = "$header.$payload"
  $hmac = [Security.Cryptography.HMACSHA256]::new([Text.Encoding]::UTF8.GetBytes($Secret))
  try {
    $signature = ConvertTo-Base64Url ($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($unsigned)))
  } finally {
    $hmac.Dispose()
  }
  return "$unsigned.$signature"
}

function Invoke-Api {
  param(
    [Parameter(Mandatory)] [string] $Method,
    [Parameter(Mandatory)] [string] $Url,
    [Parameter(Mandatory)] [string] $ApiKey,
    [Parameter(Mandatory)] [string] $Bearer,
    [byte[]] $Body,
    [string] $ContentType = 'application/json',
    [hashtable] $AdditionalHeaders = @{}
  )

  $client = [Net.Http.HttpClient]::new()
  try {
    $request = [Net.Http.HttpRequestMessage]::new(
      [Net.Http.HttpMethod]::new($Method),
      $Url
    )
    $request.Headers.TryAddWithoutValidation('apikey', $ApiKey) | Out-Null
    $request.Headers.TryAddWithoutValidation('Authorization', "Bearer $Bearer") | Out-Null
    foreach ($entry in $AdditionalHeaders.GetEnumerator()) {
      $request.Headers.TryAddWithoutValidation($entry.Key, [string] $entry.Value) | Out-Null
    }
    if ($null -ne $Body) {
      $request.Content = [Net.Http.ByteArrayContent]::new($Body)
      $request.Content.Headers.ContentType = [Net.Http.Headers.MediaTypeHeaderValue]::Parse($ContentType)
    }
    $response = $client.Send($request)
    $bytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
    return [pscustomobject]@{
      StatusCode = [int] $response.StatusCode
      IsSuccess = $response.IsSuccessStatusCode
      Bytes = $bytes
    }
  } finally {
    $client.Dispose()
  }
}

function ConvertTo-StorageUrlPath {
  param([Parameter(Mandatory)] [string] $Path)

  return (($Path -split '/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
}

function Get-Sha256 {
  param([Parameter(Mandatory)] [byte[]] $Bytes)

  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    return [Convert]::ToHexString($sha.ComputeHash($Bytes)).ToLowerInvariant()
  } finally {
    $sha.Dispose()
  }
}

function Get-PhysicalStorageFingerprint {
  $inventory = & docker.exe exec $StorageContainer sh -c `
    "find /mnt -type f -exec stat -c '%n|%s|%Y' '{}' ';' | sort"
  if ($LASTEXITCODE -ne 0) {
    throw 'Could not inventory the isolated physical Storage backend.'
  }
  return Get-Sha256 ([Text.Encoding]::UTF8.GetBytes(($inventory -join "`n")))
}

function Test-StorageTableOwnerGuard {
  $storageEnvironment = & docker.exe inspect $StorageContainer `
    --format '{{range .Config.Env}}{{println .}}{{end}}'
  if ($LASTEXITCODE -ne 0) {
    throw 'Could not inspect the isolated Storage connection.'
  }
  $databaseUrlLine = $storageEnvironment | Where-Object { $_ -like 'DATABASE_URL=*' } | Select-Object -First 1
  Assert-Condition ($null -ne $databaseUrlLine) 'Storage DATABASE_URL is unavailable.'

  $databaseUri = [Uri] ($databaseUrlLine.Substring('DATABASE_URL='.Length))
  $credentials = $databaseUri.UserInfo -split ':', 2
  Assert-Condition ($credentials.Count -eq 2) 'Storage database credentials are invalid.'
  $databaseUser = [Uri]::UnescapeDataString($credentials[0])
  $databasePassword = [Uri]::UnescapeDataString($credentials[1])
  Assert-Condition ($databaseUser -eq 'supabase_storage_admin') `
    'The Storage connection is not using the storage.objects owner.'

  $result = & docker.exe exec -e "PGPASSWORD=$databasePassword" $DbContainer `
    psql -X -h 127.0.0.1 -U $databaseUser -d postgres -v ON_ERROR_STOP=1 `
    -c "insert into storage.objects (bucket_id, name) values ('transaction-proofs', 'maintenance-05d-table-owner-probe')" 2>&1
  Assert-Condition ($LASTEXITCODE -ne 0) `
    'The storage.objects table owner bypassed the maintenance trigger.'
  Assert-Condition (([string] ($result -join "`n")).Contains(
    'Storage mutations are temporarily disabled for maintenance'
  )) 'The table-owner refusal did not originate from the maintenance trigger.'
}

function Test-StorageRoundTrip {
  param(
    [Parameter(Mandatory)] [string] $ObjectPath,
    [Parameter(Mandatory)] [string] $ApiKey,
    [Parameter(Mandatory)] [string] $Bearer,
    [Parameter(Mandatory)] [byte[]] $Bytes
  )

  $encodedPath = ConvertTo-StorageUrlPath $ObjectPath
  $objectUrl = "$ExpectedApiUrl/storage/v1/object/$bucket/$encodedPath"
  $downloadUrl = "$ExpectedApiUrl/storage/v1/object/authenticated/$bucket/$encodedPath"
  $upload = Invoke-Api -Method POST -Url $objectUrl -ApiKey $ApiKey `
    -Bearer $Bearer -Body $Bytes -ContentType 'application/pdf'
  Assert-Condition $upload.IsSuccess 'The normal Storage upload probe failed.'

  $download = Invoke-Api -Method GET -Url $downloadUrl -ApiKey $ApiKey -Bearer $Bearer
  Assert-Condition $download.IsSuccess 'The normal Storage download probe failed.'
  Assert-Condition ((Get-Sha256 $download.Bytes) -eq (Get-Sha256 $Bytes)) `
    'The normal Storage probe bytes differ after download.'

  $deleteBody = [Text.Encoding]::UTF8.GetBytes(
    (@{ prefixes = @($ObjectPath) } | ConvertTo-Json -Compress)
  )
  $delete = Invoke-Api -Method DELETE -Url "$ExpectedApiUrl/storage/v1/object/$bucket" `
    -ApiKey $ApiKey -Bearer $Bearer -Body $deleteBody
  Assert-Condition $delete.IsSuccess 'The normal Storage cleanup probe failed.'

  $missing = Invoke-Api -Method GET -Url $downloadUrl -ApiKey $ApiKey -Bearer $Bearer
  Assert-Condition (-not $missing.IsSuccess) 'The deleted Storage probe remains accessible.'
}

function Test-MaintenanceStorageRejection {
  param([Parameter(Mandatory)] $Response)

  if ($Response.IsSuccess) {
    return $false
  }
  $bodyText = [Text.Encoding]::UTF8.GetString($Response.Bytes)
  return $bodyText.Contains('Storage mutations are temporarily disabled for maintenance')
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$activateScript = Join-Path $scriptRoot 'activate-maintenance.sql'
$deactivateScript = Join-Path $scriptRoot 'deactivate-maintenance.sql'
$integrityScript = Join-Path $scriptRoot 'capture-integrity.sql'
$activated = $false

$configPath = Join-Path $SupabaseWorkdir 'supabase\config.toml'
Assert-Condition (Test-Path -LiteralPath $configPath) 'Supabase config was not found.'
$config = Get-Content -Raw -LiteralPath $configPath
Assert-Condition ($config -match ('project_id\s*=\s*"' + [regex]::Escape($ExpectedProjectId) + '"')) `
  'The Supabase project_id does not match the isolated rehearsal project.'
Assert-Condition ($config -match ('(?ms)^\[api\].*?^port\s*=\s*' + $ExpectedApiUrl.Split(':')[-1] + '\s*$')) `
  'The isolated API port does not match.'
Assert-Condition ($config -match ('(?ms)^\[db\].*?^port\s*=\s*' + $ExpectedDbPort + '\s*$')) `
  'The isolated database port does not match.'

$containerLabel = (& docker.exe inspect $DbContainer `
  --format '{{index .Config.Labels "com.supabase.cli.project"}}').Trim()
Assert-Condition ($LASTEXITCODE -eq 0 -and $containerLabel -eq $ExpectedProjectId) `
  'The database container identity does not match the isolated project.'

$supabaseEnvironment = Get-SupabaseEnvironment
Assert-Condition ($supabaseEnvironment['API_URL'] -eq $ExpectedApiUrl) `
  'Supabase CLI returned an unexpected API URL.'
Assert-Condition ($supabaseEnvironment['DB_URL'] -match (':' + $ExpectedDbPort + '/')) `
  'Supabase CLI returned an unexpected database port.'

$maintenanceState = Invoke-DbSql @'
select case
  when to_regnamespace('patrigest_maintenance') is null then 'inactive'
  else 'active_or_inconsistent'
end;
'@
Assert-Condition ($maintenanceState[-1] -eq 'inactive') `
  'The rehearsal requires an initially inactive maintenance state.'

$documentIdentity = Invoke-DbSql @'
select storage_object.bucket_id || E'\t' || storage_object.name || E'\t'
  || protected_person.owner_id::text
from storage.objects storage_object
join public.protected_persons protected_person
  on protected_person.id = split_part(storage_object.name, '/', 2)::uuid
where storage_object.bucket_id = 'transaction-proofs'
order by storage_object.created_at
limit 1;
'@
Assert-Condition ($documentIdentity.Count -eq 1) 'No suitable local Storage test fixture was found.'
$documentParts = $documentIdentity[0] -split "`t", 3
Assert-Condition ($documentParts.Count -eq 3) 'The Storage fixture identity is invalid.'
$bucket = $documentParts[0]
$existingObjectName = $documentParts[1]
$existingOwnerId = $documentParts[2]
$objectDirectory = ($existingObjectName -split '/')[0..(($existingObjectName -split '/').Count - 2)] -join '/'

$insertFixture = Invoke-DbSql @'
select 'protected-persons/' || protected_person.id || '/transactions/'
  || transaction.id || '/proof' || E'\t' || protected_person.owner_id::text
from public.transactions transaction
join public.financial_accounts account
  on account.id = transaction.financial_account_id
join public.protected_persons protected_person
  on protected_person.id = account.protected_person_id
where transaction.transaction_type = 'expense'
  and not exists (
    select 1
    from storage.objects storage_object
    where storage_object.bucket_id = 'transaction-proofs'
      and storage_object.name = 'protected-persons/' || protected_person.id
        || '/transactions/' || transaction.id || '/proof'
  )
order by transaction.created_at
limit 1;
'@
Assert-Condition ($insertFixture.Count -eq 1) `
  'No authorized local Storage INSERT fixture was found.'
$insertFixtureParts = $insertFixture[0] -split "`t", 2
Assert-Condition ($insertFixtureParts.Count -eq 2) 'The Storage INSERT fixture is invalid.'
$authenticatedInsertPath = $insertFixtureParts[0]
$ownerId = $insertFixtureParts[1]

$authenticatedJwt = New-LocalJwt `
  -Secret $supabaseEnvironment['JWT_SECRET'] `
  -Subject $ownerId `
  -Role 'authenticated'
$existingOwnerJwt = New-LocalJwt `
  -Secret $supabaseEnvironment['JWT_SECRET'] `
  -Subject $existingOwnerId `
  -Role 'authenticated'
$serviceKey = $supabaseEnvironment['SERVICE_ROLE_KEY']
$anonKey = $supabaseEnvironment['ANON_KEY']
$encodedExistingPath = ConvertTo-StorageUrlPath $existingObjectName
$existingDownloadUrl = "$ExpectedApiUrl/storage/v1/object/authenticated/$bucket/$encodedExistingPath"
$restUrl = "$ExpectedApiUrl/rest/v1/profiles?select=id&limit=1"
$probeBytes = [Text.Encoding]::ASCII.GetBytes("%PDF-1.4`n% maintenance probe`n")

Test-StorageRoundTrip -ObjectPath $authenticatedInsertPath -ApiKey $anonKey `
  -Bearer $authenticatedJwt -Bytes $probeBytes

$baselineIntegrity = (Invoke-DbFile $integrityScript) -join "`n"
$baselinePhysicalStorage = Get-PhysicalStorageFingerprint
$baselineAcl = (Invoke-DbSql @'
select grantor.rolname || '>'
  || case when expanded.grantee = 0 then 'PUBLIC' else grantee.rolname end
  || ':' || expanded.privilege_type || ':' || expanded.is_grantable::text
from pg_namespace namespace
cross join lateral aclexplode(coalesce(namespace.nspacl, acldefault('n', namespace.nspowner))) expanded
join pg_roles grantor on grantor.oid = expanded.grantor
left join pg_roles grantee on grantee.oid = expanded.grantee
where namespace.nspname = 'public'
  and (expanded.grantee = 0 or grantee.rolname in ('anon', 'authenticated', 'service_role'))
order by 1;
'@) -join "`n"

foreach ($identity in @(
  @{ Name = 'anon'; Key = $anonKey; Bearer = $anonKey },
  @{ Name = 'authenticated'; Key = $anonKey; Bearer = $authenticatedJwt },
  @{ Name = 'service_role'; Key = $serviceKey; Bearer = $serviceKey }
)) {
  $response = Invoke-Api -Method GET -Url $restUrl -ApiKey $identity.Key -Bearer $identity.Bearer
  Assert-Condition $response.IsSuccess "Baseline Data API access failed for $($identity.Name)."
}

$baselineDownload = Invoke-Api -Method GET -Url $existingDownloadUrl `
  -ApiKey $serviceKey -Bearer $serviceKey
Assert-Condition $baselineDownload.IsSuccess 'Baseline Storage download failed.'
$baselineDocumentHash = Get-Sha256 $baselineDownload.Bytes

try {
  Invoke-DbFile $activateScript | Out-Null
  $activated = $true

  foreach ($identity in @(
    @{ Name = 'anon'; Key = $anonKey; Bearer = $anonKey },
    @{ Name = 'authenticated'; Key = $anonKey; Bearer = $authenticatedJwt },
    @{ Name = 'service_role'; Key = $serviceKey; Bearer = $serviceKey }
  )) {
    $response = Invoke-Api -Method GET -Url $restUrl -ApiKey $identity.Key -Bearer $identity.Bearer
    Assert-Condition (-not $response.IsSuccess) `
      "Data API remained accessible during maintenance for $($identity.Name)."
  }

  $activeDownload = Invoke-Api -Method GET -Url $existingDownloadUrl `
    -ApiKey $serviceKey -Bearer $serviceKey
  Assert-Condition $activeDownload.IsSuccess 'Authorized Storage reading was blocked.'
  Assert-Condition ((Get-Sha256 $activeDownload.Bytes) -eq $baselineDocumentHash) `
    'An existing Storage object changed during maintenance.'

  foreach ($identity in @(
    @{ Name = 'authenticated'; Key = $anonKey; Bearer = $authenticatedJwt; Path = $authenticatedInsertPath },
    @{ Name = 'service_role'; Key = $serviceKey; Bearer = $serviceKey; Path = "$objectDirectory/maintenance-05d-service-$([guid]::NewGuid()).pdf" }
  )) {
    $probeName = $identity.Path
    $probeUrl = "$ExpectedApiUrl/storage/v1/object/$bucket/$(ConvertTo-StorageUrlPath $probeName)"
    $upload = Invoke-Api -Method POST -Url $probeUrl -ApiKey $identity.Key `
      -Bearer $identity.Bearer -Body $probeBytes -ContentType 'application/pdf'
    Assert-Condition (-not $upload.IsSuccess) `
      "Storage upload unexpectedly succeeded during maintenance for $($identity.Name)."
  }

  $upsert = Invoke-Api -Method POST `
    -Url "$ExpectedApiUrl/storage/v1/object/$bucket/$encodedExistingPath" `
    -ApiKey $serviceKey -Bearer $serviceKey -Body $probeBytes `
    -ContentType 'application/pdf' -AdditionalHeaders @{ 'x-upsert' = 'true' }
  Assert-Condition (-not $upsert.IsSuccess) `
    'Service-role Storage replacement unexpectedly succeeded during maintenance.'

  $authenticatedUpsert = Invoke-Api -Method POST `
    -Url "$ExpectedApiUrl/storage/v1/object/$bucket/$encodedExistingPath" `
    -ApiKey $anonKey -Bearer $existingOwnerJwt -Body $probeBytes `
    -ContentType 'application/pdf' -AdditionalHeaders @{ 'x-upsert' = 'true' }
  Assert-Condition (-not $authenticatedUpsert.IsSuccess) `
    'Authenticated Storage replacement unexpectedly succeeded during maintenance.'

  $deleteBody = [Text.Encoding]::UTF8.GetBytes(
    (@{ prefixes = @($existingObjectName) } | ConvertTo-Json -Compress)
  )
  $delete = Invoke-Api -Method DELETE -Url "$ExpectedApiUrl/storage/v1/object/$bucket" `
    -ApiKey $serviceKey -Bearer $serviceKey -Body $deleteBody
  Assert-Condition (-not $delete.IsSuccess) `
    'Service-role Storage deletion unexpectedly succeeded during maintenance.'

  $authenticatedDelete = Invoke-Api -Method DELETE `
    -Url "$ExpectedApiUrl/storage/v1/object/$bucket" `
    -ApiKey $anonKey -Bearer $existingOwnerJwt -Body $deleteBody
  Assert-Condition (-not $authenticatedDelete.IsSuccess) `
    'Authenticated Storage deletion unexpectedly succeeded during maintenance.'

  $sqlGuardChecks = Invoke-DbSql @'
do $guard_test$
begin
  begin
    insert into storage.objects (bucket_id, name)
    values ('transaction-proofs', 'maintenance-05d-postgres-probe');
    raise exception 'postgres mutation unexpectedly succeeded';
  exception
    when sqlstate '55000' then null;
  end;

  begin
    set local role authenticated;
    insert into storage.objects (bucket_id, name)
    values ('transaction-proofs', 'maintenance-05d-authenticated-probe');
    raise exception 'authenticated mutation unexpectedly succeeded';
  exception
    when sqlstate '55000' then null;
  end;
  reset role;

  begin
    set local role service_role;
    insert into storage.objects (bucket_id, name)
    values ('transaction-proofs', 'maintenance-05d-service-role-probe');
    raise exception 'service_role Storage mutation unexpectedly succeeded';
  exception
    when sqlstate '55000' then null;
  end;
  reset role;

  begin
    set local role service_role;
    insert into public.profiles (id)
    values ('00000000-0000-0000-0000-000000000001');
    raise exception 'service_role business mutation unexpectedly succeeded';
  exception
    when insufficient_privilege then null;
  end;
  reset role;
end;
$guard_test$;
select 'guard-checks-passed';
'@
  Assert-Condition ($sqlGuardChecks[-1] -eq 'guard-checks-passed') `
    'SQL guard checks did not complete.'

  Test-StorageTableOwnerGuard

  $activeIntegrity = (Invoke-DbFile $integrityScript) -join "`n"
  Assert-Condition ($activeIntegrity -eq $baselineIntegrity) `
    'Business or Storage metadata changed while maintenance was active.'
  Assert-Condition ((Get-PhysicalStorageFingerprint) -eq $baselinePhysicalStorage) `
    'The physical Storage backend changed while maintenance was active.'

  Invoke-DbFile $deactivateScript | Out-Null
  $activated = $false

  $restoredAcl = (Invoke-DbSql @'
select grantor.rolname || '>'
  || case when expanded.grantee = 0 then 'PUBLIC' else grantee.rolname end
  || ':' || expanded.privilege_type || ':' || expanded.is_grantable::text
from pg_namespace namespace
cross join lateral aclexplode(coalesce(namespace.nspacl, acldefault('n', namespace.nspowner))) expanded
join pg_roles grantor on grantor.oid = expanded.grantor
left join pg_roles grantee on grantee.oid = expanded.grantee
where namespace.nspname = 'public'
  and (expanded.grantee = 0 or grantee.rolname in ('anon', 'authenticated', 'service_role'))
order by 1;
'@) -join "`n"
  Assert-Condition ($restoredAcl -eq $baselineAcl) 'Schema ACL restoration was not exact.'

  $restoredIntegrity = (Invoke-DbFile $integrityScript) -join "`n"
  Assert-Condition ($restoredIntegrity -eq $baselineIntegrity) `
    'Business or Storage metadata changed across the maintenance cycle.'

  foreach ($identity in @(
    @{ Name = 'anon'; Key = $anonKey; Bearer = $anonKey },
    @{ Name = 'authenticated'; Key = $anonKey; Bearer = $authenticatedJwt },
    @{ Name = 'service_role'; Key = $serviceKey; Bearer = $serviceKey }
  )) {
    $response = Invoke-Api -Method GET -Url $restUrl -ApiKey $identity.Key -Bearer $identity.Bearer
    Assert-Condition $response.IsSuccess `
      "Data API access was not restored for $($identity.Name)."
  }

  $restoredDownload = Invoke-Api -Method GET -Url $existingDownloadUrl `
    -ApiKey $serviceKey -Bearer $serviceKey
  Assert-Condition $restoredDownload.IsSuccess 'Storage download was not restored.'
  Assert-Condition ((Get-Sha256 $restoredDownload.Bytes) -eq $baselineDocumentHash) `
    'The existing Storage object was not restored byte-for-byte.'

  Test-StorageRoundTrip -ObjectPath $authenticatedInsertPath -ApiKey $anonKey `
    -Bearer $authenticatedJwt -Bytes $probeBytes
  Assert-Condition ((Get-PhysicalStorageFingerprint) -eq $baselinePhysicalStorage) `
    'The physical Storage backend did not return to its baseline after the probe cleanup.'

  Write-Output "PASS isolation project=$ExpectedProjectId api=$ExpectedApiUrl dbPort=$ExpectedDbPort"
  Write-Output 'PASS Data API blocked for anon, authenticated and service_role'
  Write-Output 'PASS Storage INSERT/UPDATE/DELETE blocked; authorized read preserved'
  Write-Output 'PASS PostgreSQL owner-path mutation blocked by the trigger'
  Write-Output 'PASS ACL and integrity fingerprints restored exactly'
} finally {
  if ($activated) {
    Invoke-DbFile $deactivateScript | Out-Null
  }
}
