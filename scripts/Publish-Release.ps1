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
    Assert-LastExitCode "Could not read the current branch"
    if ($branch -ne "main") {
        throw "An official release must be created from main, not from '$branch'."
    }

    $status = & git status --porcelain
    Assert-LastExitCode "Could not read Git status"
    if ($status) {
        throw "The repository must be clean before publishing."
    }
}

function Assert-NoExistingRelease {
    param([string]$Tag)

    $releaseExitCode = Invoke-QuietNative -Command { gh release view $Tag }
    if ($releaseExitCode -eq 0) {
        throw "GitHub release $Tag already exists."
    }

    $localTagExitCode = Invoke-QuietNative -Command { git rev-parse -q --verify "refs/tags/$Tag" }
    if ($localTagExitCode -eq 0) {
        throw "Local tag $Tag already exists."
    }

    $remoteTag = & git ls-remote --tags origin "refs/tags/$Tag"
    Assert-LastExitCode "Could not verify the remote tag"
    if (-not [string]::IsNullOrWhiteSpace($remoteTag)) {
        throw "Remote tag $Tag already exists."
    }
}

Set-Location -LiteralPath $Root
$ReleaseVersion = Get-ReleaseVersion -RequestedVersion $Version
if ($ReleaseVersion -notmatch "^\d+\.\d+\.\d+$") {
    throw "Invalid version '$ReleaseVersion'. Expected format: X.Y.Z."
}

$tag = "v$ReleaseVersion"
Assert-CleanMain
Assert-NoExistingRelease -Tag $tag

& (Join-Path -Path $PSScriptRoot -ChildPath "Test-Local.ps1")

& (Join-Path -Path $PSScriptRoot -ChildPath "Build-Release.ps1") -Version $ReleaseVersion -Clean
Assert-LastExitCode "Could not prepare release assets"

git tag -a $tag -m "RuneScape Clan Roster Exporter v$ReleaseVersion"
Assert-LastExitCode "Could not create tag"

git push origin main
Assert-LastExitCode "Could not push main"

git push origin $tag
Assert-LastExitCode "Could not push tag"

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
Assert-LastExitCode "Could not create GitHub release"

Write-Host "GitHub release created: $tag"
