param([string]$Password)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$environmentFile = Join-Path $projectRoot ".env.development.local.disabled"
$sqlFile = Join-Path $PSScriptRoot "transactions-validation-fixtures.sql"

if (-not (Test-Path -LiteralPath $environmentFile)) { throw "Configuration locale absente." }
$configuration = @{}
foreach ($line in Get-Content -LiteralPath $environmentFile) {
  if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
    $configuration[$matches[1]] = $matches[2].Trim().Trim('"').Trim("'")
  }
}
if ($configuration["NEXT_PUBLIC_SUPABASE_URL"].TrimEnd('/') -ne "http://127.0.0.1:54321") {
  throw "Fixtures refusees : la configuration ne designe pas Supabase local."
}
$container = "supabase_db_PatriGest"
$ports = (& docker.exe port $container 5432/tcp 2>$null) -join " "
if ($LASTEXITCODE -ne 0 -or $ports -notmatch '54322') {
  throw "Fixtures refusees : le conteneur PostgreSQL local attendu n'est pas disponible sur 54322."
}
$alreadySeeded = (& docker.exe exec $container psql -U postgres -d postgres -X -At -c "select exists(select 1 from public.protected_persons where id='97000000-0000-4000-8100-000000000101')") -join ""
if ($LASTEXITCODE -ne 0) { throw "Impossible de vérifier les fixtures locales." }

if ($alreadySeeded.Trim() -ne "t") {
  if ([string]::IsNullOrWhiteSpace($Password)) {
    $securePassword = Read-Host "Mot de passe commun des trois comptes fictifs" -AsSecureString
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    try { $Password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
  }
  if ($Password.Length -lt 12 -or $Password -notmatch '[A-Z]' -or $Password -notmatch '[a-z]' -or $Password -notmatch '[0-9]' -or $Password -match "['\r\n]") {
    throw "Le mot de passe local doit contenir au moins 12 caracteres, majuscule, minuscule et chiffre, sans apostrophe."
  }
  $sql = (Get-Content -LiteralPath $sqlFile -Raw -Encoding UTF8).Replace("__LOCAL_PASSWORD__", $Password)
  $sql | & docker.exe exec -i $container psql -U postgres -d postgres -X -v ON_ERROR_STOP=1
  if ($LASTEXITCODE -ne 0) { throw "La création des fixtures locales a échoué." }
} else {
  Write-Host "Les fixtures SQL existent deja ; aucune donnee n'a ete remplacee."
}

& (Join-Path $PSScriptRoot "resume-proofs.ps1")
if ($LASTEXITCODE -ne 0) { throw "La reprise documentaire a echoue." }
$Password = $null
Write-Host "Fixtures pretes : owner, manager et read-only sous le domaine example.test."
