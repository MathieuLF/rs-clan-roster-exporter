[CmdletBinding()]
param(
    [string]$Version = "",
    [switch]$Draft
)

$ErrorActionPreference = "Stop"
$Root = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath ".."))
$ProductName = "RuneScape-Clan-Roster-Exporter"

function Assert-LastExitCode {
    param([string]$Message)

    if ($LASTEXITCODE -ne 0) {
        throw "$Message (exit $LASTEXITCODE)"
    }
}

function Invoke-QuietNative {
    param([scriptblock]$Command)

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    try {
        & $Command *> $null
        return $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
}

function Get-ReleaseVersion {
    param([string]$RequestedVersion)

    if (-not [string]::IsNullOrWhiteSpace($RequestedVersion)) {
        return $RequestedVersion.Trim()
    }

    return (Get-Content -LiteralPath (Join-Path -Path $Root -ChildPath "VERSION") -Raw).Trim()
}

function Assert-CleanMain {
    $branch = (& git branch --show-current).Trim()
    Assert-LastExitCode "Lecture de la branche courante impossible"
    if ($branch -ne "main") {
        throw "Une release officielle doit etre creee depuis main, pas depuis '$branch'."
    }

    $status = & git status --porcelain
    Assert-LastExitCode "Lecture du statut Git impossible"
    if ($status) {
        throw "Le depot doit etre propre avant la publication."
    }
}

function Assert-NoExistingRelease {
    param([string]$Tag)

    $releaseExitCode = Invoke-QuietNative -Command { gh release view $Tag }
    if ($releaseExitCode -eq 0) {
        throw "La release GitHub $Tag existe deja."
    }

    $localTagExitCode = Invoke-QuietNative -Command { git rev-parse -q --verify "refs/tags/$Tag" }
    if ($localTagExitCode -eq 0) {
        throw "Le tag local $Tag existe deja."
    }

    $remoteTag = & git ls-remote --tags origin "refs/tags/$Tag"
    Assert-LastExitCode "Verification du tag distant impossible"
    if (-not [string]::IsNullOrWhiteSpace($remoteTag)) {
        throw "Le tag distant $Tag existe deja."
    }
}

Set-Location -LiteralPath $Root
$ReleaseVersion = Get-ReleaseVersion -RequestedVersion $Version
if ($ReleaseVersion -notmatch "^\d+\.\d+\.\d+$") {
    throw "Version invalide '$ReleaseVersion'. Format attendu : X.Y.Z."
}

$tag = "v$ReleaseVersion"
Assert-CleanMain
Assert-NoExistingRelease -Tag $tag

& (Join-Path -Path $PSScriptRoot -ChildPath "Build-Release.ps1") -Version $ReleaseVersion -Clean
Assert-LastExitCode "Preparation des assets impossible"

git tag -a $tag -m "RuneScape Clan Roster Exporter v$ReleaseVersion"
Assert-LastExitCode "Creation du tag impossible"

git push origin main
Assert-LastExitCode "Push de main impossible"

git push origin $tag
Assert-LastExitCode "Push du tag impossible"

$distDir = Join-Path -Path $Root -ChildPath "dist"
$assets = @(
    (Join-Path -Path $distDir -ChildPath "Get-RunescapeClanMembers-v$ReleaseVersion.ps1"),
    (Join-Path -Path $distDir -ChildPath "Get-RunescapeClanMembers-v$ReleaseVersion.ps1.sha256"),
    (Join-Path -Path $distDir -ChildPath "$ProductName-v$ReleaseVersion-portable.zip"),
    (Join-Path -Path $distDir -ChildPath "$ProductName-v$ReleaseVersion-portable.zip.sha256"),
    (Join-Path -Path $distDir -ChildPath "$ProductName-v$ReleaseVersion.release-manifest.json"),
    (Join-Path -Path $distDir -ChildPath "$ProductName-v$ReleaseVersion.release-manifest.json.sha256")
)

$releaseArgs = @(
    "release", "create", $tag,
    "--title", "RuneScape Clan Roster Exporter v$ReleaseVersion",
    "--notes-file", (Join-Path -Path $distDir -ChildPath "$ProductName-v$ReleaseVersion.release-notes.md")
)

if ($Draft) {
    $releaseArgs += "--draft"
}

$releaseArgs += $assets
gh @releaseArgs
Assert-LastExitCode "Creation de la release GitHub impossible"

Write-Host "Release GitHub creee : $tag"
