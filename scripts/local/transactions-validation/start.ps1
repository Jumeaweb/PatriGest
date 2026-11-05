param(
  [ValidateSet("dev", "build")]
  [string]$Mode = "dev"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$environmentFile = Join-Path $projectRoot ".env.development.local.disabled"

if (-not (Test-Path -LiteralPath $environmentFile)) {
  throw "La configuration locale ignoree .env.development.local.disabled est absente."
}

$configuration = @{}
foreach ($line in Get-Content -LiteralPath $environmentFile) {
  if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
    $configuration[$matches[1]] = $matches[2].Trim().Trim('"').Trim("'")
  }
}

$expectedUrl = "http://127.0.0.1:54321"
if ($configuration["NEXT_PUBLIC_SUPABASE_URL"].TrimEnd('/') -ne $expectedUrl) {
  throw "Demarrage refuse : NEXT_PUBLIC_SUPABASE_URL doit designer $expectedUrl."
}
foreach ($required in @("NEXT_PUBLIC_SUPABASE_ANON_KEY", "SUPABASE_SERVICE_ROLE_KEY")) {
  if ([string]::IsNullOrWhiteSpace($configuration[$required])) {
    throw "Demarrage refuse : la variable locale $required est absente."
  }
}

$apiAvailable = Test-NetConnection -ComputerName 127.0.0.1 -Port 54321 -InformationLevel Quiet
$databaseAvailable = Test-NetConnection -ComputerName 127.0.0.1 -Port 54322 -InformationLevel Quiet
if (-not $apiAvailable -or -not $databaseAvailable) {
  throw "Demarrage refuse : Supabase local n'est pas disponible sur 54321/54322."
}

$env:NEXT_PUBLIC_SUPABASE_URL = $expectedUrl
$env:NEXT_PUBLIC_SUPABASE_ANON_KEY = $configuration["NEXT_PUBLIC_SUPABASE_ANON_KEY"]
$env:SUPABASE_SERVICE_ROLE_KEY = $configuration["SUPABASE_SERVICE_ROLE_KEY"]
$env:APP_URL = "http://localhost:3000"
$env:RESEND_API_KEY = ""
$env:RESEND_MONITORING_API_KEY = ""
$env:VERCEL_ACCESS_TOKEN = ""
$env:VERCEL_PROJECT_ID = ""
$env:VERCEL_ORG_ID = ""
$env:GANDI_ACCESS_TOKEN = ""
$env:PATRIGEST_ENABLE_TRANSACTION_PROOF_DURABLE_OPERATIONS = "false"
$env:PATRIGEST_ENABLE_BANK_STATEMENT_DURABLE_OPERATIONS = "false"
$env:PATRIGEST_ENABLE_MANAGEMENT_REPORT_DURABLE_OPERATIONS = "false"
$env:PATRIGEST_ENABLE_DOSSIER_ARCHIVE_LIFECYCLE = "false"
$env:PATRIGEST_ENABLE_ACCOUNT_DELETION_DURABLE_NEUTRALIZATION = "false"
$env:PATRIGEST_ENABLE_ADMIN_ACCOUNT_DELETION_DURABLE_NEUTRALIZATION = "false"
$env:PATRIGEST_ENABLE_ADMIN_DOCUMENT_REPAIR = "false"
$env:PATRIGEST_LOCAL_VALIDATION = "PAT-TRANSACTIONS-01D2"

Push-Location $projectRoot
try {
  Write-Host "Environnement local valide : Supabase 127.0.0.1:54321, application localhost:3000."
  if ($Mode -eq "build") {
    $env:NODE_OPTIONS = (($env:NODE_OPTIONS + " --use-system-ca").Trim())
    & npx.cmd next build --webpack
  } else {
    & npm.cmd run dev -- --hostname 127.0.0.1 --port 3000
  }
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
  Pop-Location
}
