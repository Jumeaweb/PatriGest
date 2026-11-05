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
  throw "Reprise refusee : la configuration ne designe pas Supabase local."
}
if ([string]::IsNullOrWhiteSpace($configuration["NEXT_PUBLIC_SUPABASE_ANON_KEY"]) -or
    [string]::IsNullOrWhiteSpace($configuration["SUPABASE_SERVICE_ROLE_KEY"])) {
  throw "Reprise refusee : les cles Supabase locales sont absentes."
}

$container = "supabase_db_PatriGest"
$ports = (& docker.exe port $container 5432/tcp 2>$null) -join " "
if ($LASTEXITCODE -ne 0 -or $ports -notmatch '54322') {
  throw "Reprise refusee : le conteneur PostgreSQL local attendu n'est pas disponible sur 54322."
}
$fixtureCount = (& docker.exe exec $container psql -U postgres -d postgres -X -At -c "select count(*) from public.transactions where financial_account_id='97000000-0000-4000-8300-000000000301'") -join ""
if ($LASTEXITCODE -ne 0 -or $fixtureCount.Trim() -ne "5") {
  throw "Reprise refusee : les cinq transactions fictives ne sont pas presentes."
}

$env:PAT_LOCAL_SUPABASE_URL = "http://127.0.0.1:54321"
$env:PAT_LOCAL_ANON_KEY = $configuration["NEXT_PUBLIC_SUPABASE_ANON_KEY"]
$env:PAT_LOCAL_SERVICE_ROLE_KEY = $configuration["SUPABASE_SERVICE_ROLE_KEY"]
try {
  & node (Join-Path $PSScriptRoot "upload-proof-fixtures.mjs")
  if ($LASTEXITCODE -ne 0) { throw "Le chargement des justificatifs fictifs a echoue." }
} finally {
  Remove-Item Env:PAT_LOCAL_SERVICE_ROLE_KEY -ErrorAction SilentlyContinue
  Remove-Item Env:PAT_LOCAL_ANON_KEY -ErrorAction SilentlyContinue
  Remove-Item Env:PAT_LOCAL_SUPABASE_URL -ErrorAction SilentlyContinue
}

Write-Host "Reprise documentaire terminee sans recreer les fixtures SQL."
