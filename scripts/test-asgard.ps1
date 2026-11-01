#Requires -Version 7.0
<#
.SYNOPSIS
Build the image and run it locally with the Asgard config (glance-asgard.yml) and
glance/asgard.env, then check that the login is enforced.

.PARAMETER NoKeep
Stop the container after the checks (default: leave it running for a browser login).

.PARAMETER NoLogin
Skip the check that logs in with your password.
#>
[CmdletBinding()]
param(
    [switch]$NoKeep,
    [switch]$NoLogin
)

$ErrorActionPreference = 'Stop'

$repoRoot  = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$glanceDir = Join-Path $repoRoot 'glance'
$envFile   = Join-Path $glanceDir 'asgard.env'
$localTag  = 'glance-dashboard:local'
$container = 'glance-asgard-test'
$port      = 8081
$base      = "http://127.0.0.1:$port"
$vars      = 'STEAM_API_KEY', 'STEAM_USER', 'WEATHER_LOCATION', 'GLANCE_SECRET_KEY', 'GLANCE_PASSWORD_HASH'

if (-not (Test-Path $envFile)) { throw "$envFile not found. Run: scripts/auth-secrets.ps1 -Write" }

# The file is single-quoted for Compose. `docker run --env-file` would keep the
# quotes as part of the values, so load it here and pass the variables through.
$values = @{}
foreach ($line in Get-Content $envFile) {
    if ($line -match "^([A-Z_]+)='(.*)'$") { $values[$Matches[1]] = $Matches[2] }
}
foreach ($var in $vars) {
    if (-not $values[$var]) { throw "$var is empty in $envFile" }
}

Write-Host "Building $localTag from $glanceDir ..."
& docker build -q -t $localTag $glanceDir | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'docker build failed' }

& docker rm -f $container 2>$null | Out-Null
foreach ($var in $vars) { Set-Item "Env:$var" $values[$var] }
try {
    $envArgs = $vars | ForEach-Object { '-e', $_ }
    & docker run -d --name $container -p "127.0.0.1:${port}:8080" @envArgs `
        --entrypoint /app/glance $localTag --config /app/config/glance-asgard.yml | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'docker run failed' }
}
finally {
    foreach ($var in $vars) { Remove-Item "Env:$var" -ErrorAction SilentlyContinue }
}

function Get-Status([string]$Path, [hashtable]$Extra = @{}) {
    $r = Invoke-WebRequest -Uri "$base$Path" -MaximumRedirection 0 -SkipHttpErrorCheck -ErrorAction SilentlyContinue @Extra
    return $r
}

$up = $false
foreach ($i in 1..30) {
    try { if ((Get-Status '/api/healthz').StatusCode -eq 200) { $up = $true; break } } catch { }
    if ((& docker inspect -f '{{.State.Running}}' $container) -ne 'true') { break }
    Start-Sleep -Seconds 1
}
if (-not $up) {
    Write-Host 'FAIL: container did not start' -ForegroundColor Red
    & docker logs $container
    & docker rm -f $container | Out-Null
    exit 1
}

$fails = 0
function Test-Check([string]$Name, $Actual, $Expected) {
    if ("$Actual" -eq "$Expected") {
        Write-Host "PASS  $Name"
    }
    else {
        Write-Host "FAIL  $Name (expected $Expected, got $Actual)" -ForegroundColor Red
        $script:fails++
    }
}

Test-Check 'GET /api/healthz is public' (Get-Status '/api/healthz').StatusCode 200

$r = Get-Status '/'
$location = "$($r.Headers['Location'])"
Test-Check 'GET / redirects to the login page' "$($r.StatusCode) $($location.Split('/')[-1])" '303 login'

Test-Check 'Page content needs a session' (Get-Status '/api/pages/home/content/').StatusCode 401

if (-not $NoLogin) {
    $password = Read-Host "Password for 'piotr' (checks the hash survived the env file)" -AsSecureString |
        ConvertFrom-SecureString -AsPlainText
    $body = @{ username = 'piotr'; password = $password } | ConvertTo-Json -Compress
    $password = $null
    $login = Invoke-WebRequest -Uri "$base/api/authenticate" -Method Post -ContentType 'application/json' `
        -Body $body -SessionVariable session -SkipHttpErrorCheck
    $body = $null
    Test-Check 'Login with the right password' $login.StatusCode 200
    Test-Check 'Page content with the session cookie' `
        (Get-Status '/api/pages/home/content/' @{ WebSession = $session }).StatusCode 200
}

Write-Host ''
if ($NoKeep) {
    & docker rm -f $container | Out-Null
}
else {
    Write-Host "Running at $base. Stop it with: docker rm -f $container"
}

if ($fails -gt 0) {
    Write-Host "$fails check(s) failed" -ForegroundColor Red
    exit 1
}
Write-Host 'All checks passed'
