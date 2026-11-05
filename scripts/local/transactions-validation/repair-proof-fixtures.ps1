$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$environmentFile = Join-Path $projectRoot ".env.development.local.disabled"

if (-not (Test-Path -LiteralPath $environmentFile)) { throw "Configuration locale absente." }
$configuration = @{}
foreach ($line in Get-Content -LiteralPath $environmentFile) {
  if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
    $configuration[$matches[1]] = $matches[2].Trim().Trim('"').Trim("'")
  }
}
if ($configuration["NEXT_PUBLIC_SUPABASE_URL"].TrimEnd('/') -ne "http://127.0.0.1:54321") {
  throw "Reparation refusee : seule l'API Supabase locale 127.0.0.1:54321 est autorisee."
}
if ([string]::IsNullOrWhiteSpace($configuration["NEXT_PUBLIC_SUPABASE_ANON_KEY"]) -or
    [string]::IsNullOrWhiteSpace($configuration["SUPABASE_SERVICE_ROLE_KEY"])) {
  throw "Reparation refusee : les cles Supabase locales sont absentes."
}

$container = "supabase_db_PatriGest"
$ports = (& docker.exe port $container 5432/tcp 2>$null) -join " "
if ($LASTEXITCODE -ne 0 -or $ports -notmatch '54322') {
  throw "Reparation refusee : le PostgreSQL local attendu n'est pas disponible sur 54322."
}

$fixtureGuardSql = @"
select (
  exists(select 1 from public.transaction_documents document
    join public.transactions transaction on transaction.id=document.transaction_id
    join public.financial_accounts account on account.id=transaction.financial_account_id
    where transaction.id='f9b1a546-ab8e-4130-a084-9e7dabfeebf9'
      and account.id='97000000-0000-4000-8300-000000000301'
      and account.protected_person_id='97000000-0000-4000-8100-000000000101'
      and document.storage_path='protected-persons/97000000-0000-4000-8100-000000000101/transactions/f9b1a546-ab8e-4130-a084-9e7dabfeebf9/proof'
      and document.file_name='justificatif-courant.pdf')
  and exists(select 1 from public.transaction_document_history history
    join public.transactions transaction on transaction.id=history.transaction_id
    join public.financial_accounts account on account.id=transaction.financial_account_id
    where transaction.id='bd090eaa-fd77-4714-ac48-612ee8f6320d'
      and account.id='97000000-0000-4000-8300-000000000301'
      and account.protected_person_id='97000000-0000-4000-8100-000000000101'
      and history.storage_path='protected-persons/97000000-0000-4000-8100-000000000101/transactions/bd090eaa-fd77-4714-ac48-612ee8f6320d/proof'
      and history.file_name='justificatif-historique.pdf'
      and history.proof_reference='2026-0004')
);
"@
$fixtureGuard = (& docker.exe exec $container psql -U postgres -d postgres -X -At -c $fixtureGuardSql) -join ""
if ($LASTEXITCODE -ne 0 -or $fixtureGuard.Trim() -ne "t") {
  throw "Reparation refusee : les associations documentaires ne correspondent pas aux fixtures attendues."
}

$businessHashSql = @"
select md5(jsonb_build_object(
  'transactions',(select jsonb_agg(to_jsonb(transaction) order by transaction.id) from public.transactions transaction where transaction.id in ('f9b1a546-ab8e-4130-a084-9e7dabfeebf9','bd090eaa-fd77-4714-ac48-612ee8f6320d')),
  'documents',(select jsonb_agg(to_jsonb(document) order by document.id) from public.transaction_documents document where document.transaction_id in ('f9b1a546-ab8e-4130-a084-9e7dabfeebf9','bd090eaa-fd77-4714-ac48-612ee8f6320d')),
  'history',(select jsonb_agg(to_jsonb(history) order by history.id) from public.transaction_document_history history where history.transaction_id in ('f9b1a546-ab8e-4130-a084-9e7dabfeebf9','bd090eaa-fd77-4714-ac48-612ee8f6320d'))
)::text);
"@
$businessHashBefore = ((& docker.exe exec $container psql -U postgres -d postgres -X -At -c $businessHashSql) -join "").Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($businessHashBefore)) {
  throw "Impossible d'etablir l'empreinte metier avant reparation."
}

$authEnvironment = & docker.exe inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "supabase_auth_PatriGest"
$jwtSecretLine = $authEnvironment | Where-Object { $_ -like 'GOTRUE_JWT_SECRET=*' } | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($jwtSecretLine)) {
  throw "Reparation refusee : secret JWT local introuvable."
}
$jwtSecret = $jwtSecretLine.Substring('GOTRUE_JWT_SECRET='.Length)
$outsiderSql = @"
select user_account.id::text || E'\t' || user_account.email
from auth.users user_account
where user_account.id not in (
  '97000000-0000-4000-8000-000000000001',
  '97000000-0000-4000-8000-000000000002',
  '97000000-0000-4000-8000-000000000003'
)
and not exists(select 1 from public.protected_persons person where person.owner_id=user_account.id)
and not exists(select 1 from public.protected_person_access access where access.user_id=user_account.id)
order by user_account.id
limit 1;
"@
$outsiderRecord = ((& docker.exe exec $container psql -U postgres -d postgres -X -At -c $outsiderSql) -join "").Trim()
$outsiderParts = $outsiderRecord -split "`t", 2
if ($LASTEXITCODE -ne 0 -or $outsiderParts.Count -ne 2) {
  throw "Reparation refusee : aucun utilisateur exterieur local existant n'est disponible."
}

$env:PAT_LOCAL_SUPABASE_URL = "http://127.0.0.1:54321"
$env:PAT_LOCAL_APP_URL = "http://127.0.0.1:3000"
$env:PAT_LOCAL_ANON_KEY = $configuration["NEXT_PUBLIC_SUPABASE_ANON_KEY"]
$env:PAT_LOCAL_SERVICE_ROLE_KEY = $configuration["SUPABASE_SERVICE_ROLE_KEY"]
$env:PAT_LOCAL_JWT_SECRET = $jwtSecret
$env:PAT_LOCAL_OUTSIDER_ID = $outsiderParts[0]
$env:PAT_LOCAL_OUTSIDER_EMAIL = $outsiderParts[1]
try {
  & node (Join-Path $PSScriptRoot "repair-proof-fixtures.mjs")
  if ($LASTEXITCODE -ne 0) { throw "La reparation binaire locale a echoue." }
} finally {
  Remove-Item Env:PAT_LOCAL_SERVICE_ROLE_KEY -ErrorAction SilentlyContinue
  Remove-Item Env:PAT_LOCAL_APP_URL -ErrorAction SilentlyContinue
  Remove-Item Env:PAT_LOCAL_JWT_SECRET -ErrorAction SilentlyContinue
  Remove-Item Env:PAT_LOCAL_OUTSIDER_ID -ErrorAction SilentlyContinue
  Remove-Item Env:PAT_LOCAL_OUTSIDER_EMAIL -ErrorAction SilentlyContinue
  Remove-Item Env:PAT_LOCAL_ANON_KEY -ErrorAction SilentlyContinue
  Remove-Item Env:PAT_LOCAL_SUPABASE_URL -ErrorAction SilentlyContinue
}

$businessHashAfter = ((& docker.exe exec $container psql -U postgres -d postgres -X -At -c $businessHashSql) -join "").Trim()
if ($LASTEXITCODE -ne 0 -or $businessHashAfter -ne $businessHashBefore) {
  throw "Controle final en echec : l'etat metier ou documentaire a change."
}
Write-Host "Etat metier, references et historiques inchanges."
