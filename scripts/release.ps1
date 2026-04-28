#Requires -Version 7.0
[CmdletBinding(DefaultParameterSetName = 'Patch')]
param(
    [Parameter(ParameterSetName = 'Patch')]
    [switch]$Patch,

    [Parameter(ParameterSetName = 'Minor')]
    [switch]$Minor,

    [Parameter(ParameterSetName = 'Major')]
    [switch]$Major,

    [switch]$NoPush,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$repoRoot     = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$versionFile  = Join-Path $repoRoot 'VERSION'
$imageName    = 'mgpeter/glance-dashboard'
$localTag     = 'glance-dashboard:local'
$buildContext = Join-Path $repoRoot 'glance'

$bump = if ($Major) { 'major' } elseif ($Minor) { 'minor' } else { 'patch' }

if (-not (Test-Path $versionFile)) {
    throw "VERSION file not found at $versionFile"
}

$current = (Get-Content -Raw -Path $versionFile).Trim()
if ($current -notmatch '^\d+\.\d+\.\d+$') {
    throw "VERSION file does not contain a valid semver: '$current'"
}

$parts = $current.Split('.') | ForEach-Object { [int]$_ }
$majorN, $minorN, $patchN = $parts

switch ($bump) {
    'patch' { $patchN += 1 }
    'minor' { $minorN += 1; $patchN = 0 }
    'major' { $majorN += 1; $minorN = 0; $patchN = 0 }
}

$new = "$majorN.$minorN.$patchN"

Write-Host "glance-dashboard: $current -> $new ($bump)"

if ($DryRun) {
    Write-Host '(dry-run) no changes made'
    return
}

Set-Content -Path $versionFile -Value $new

Write-Host "Building $localTag from $buildContext ..."
& docker build -t $localTag $buildContext
if ($LASTEXITCODE -ne 0) { throw 'docker build failed' }

$latestRef = "${imageName}:latest"
$versionRef = "${imageName}:${new}"

Write-Host "Tagging $latestRef and $versionRef ..."
& docker tag $localTag $latestRef
if ($LASTEXITCODE -ne 0) { throw "docker tag $latestRef failed" }
& docker tag $localTag $versionRef
if ($LASTEXITCODE -ne 0) { throw "docker tag $versionRef failed" }

if ($NoPush) {
    Write-Host "Built (push skipped): $versionRef"
    return
}

Write-Host "Pushing $imageName (all tags) ..."
& docker push --all-tags $imageName
if ($LASTEXITCODE -ne 0) { throw 'docker push failed' }

Write-Host "Released $versionRef"
