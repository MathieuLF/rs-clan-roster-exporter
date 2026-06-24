[CmdletBinding()]
param(
    [string]$Version = "",
    [switch]$Clean
)

$ErrorActionPreference = "Stop"
$Root = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath ".."))
$ProductName = "RuneScape-Clan-Roster-Exporter"
$ScriptName = "Get-RunescapeClanMembers.ps1"

function Get-ReleaseVersion {
    param([string]$RequestedVersion)

    if (-not [string]::IsNullOrWhiteSpace($RequestedVersion)) {
        return $RequestedVersion.Trim()
    }

    $versionPath = Join-Path -Path $Root -ChildPath "VERSION"
    if (-not (Test-Path -LiteralPath $versionPath -PathType Leaf)) {
        throw "Fichier VERSION introuvable."
    }

    return (Get-Content -LiteralPath $versionPath -Raw).Trim()
}

function Assert-SemVer {
    param([string]$Value)

    if ($Value -notmatch "^\d+\.\d+\.\d+$") {
        throw "Version invalide '$Value'. Format attendu : X.Y.Z."
    }
}

function Get-GitValue {
    param([string[]]$Arguments)

    $value = (& git @Arguments 2>$null)
    if ($LASTEXITCODE -ne 0) {
        return ""
    }

    return ([string]$value).Trim()
}

function Get-ChangelogSection {
    param([string]$ReleaseVersion)

    $changelogPath = Join-Path -Path $Root -ChildPath "CHANGELOG.md"
    if (-not (Test-Path -LiteralPath $changelogPath -PathType Leaf)) {
        throw "CHANGELOG.md introuvable."
    }

    $text = Get-Content -LiteralPath $changelogPath -Raw
    $pattern = "(?ms)^## \[$([regex]::Escape($ReleaseVersion))\].*?\r?\n(?<body>.*?)(?=^## |\z)"
    $match = [regex]::Match($text, $pattern)
    if (-not $match.Success) {
        throw "Aucune section CHANGELOG.md trouvee pour $ReleaseVersion."
    }

    return $match.Groups["body"].Value.Trim()
}

function Write-Utf8File {
    param(
        [string]$Path,
        [string]$Content
    )

    $encoding = New-Object System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Write-AsciiFile {
    param(
        [string]$Path,
        [string]$Content
    )

    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.Encoding]::ASCII)
}

function New-Sha256File {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Fichier introuvable pour empreinte SHA256 : $Path"
    }

    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    $fileName = Split-Path -Path $Path -Leaf
    $shaPath = "$Path.sha256"
    Write-AsciiFile -Path $shaPath -Content "$hash  $fileName`n"

    return [PSCustomObject]@{
        Path   = $Path
        Sha256 = $hash
        ShaFile = $shaPath
    }
}

$ReleaseVersion = Get-ReleaseVersion -RequestedVersion $Version
Assert-SemVer -Value $ReleaseVersion

$versionFile = Join-Path -Path $Root -ChildPath "VERSION"
$versionFileValue = (Get-Content -LiteralPath $versionFile -Raw).Trim()
if ($versionFileValue -ne $ReleaseVersion) {
    throw "VERSION contient '$versionFileValue', mais la release demandee est '$ReleaseVersion'."
}

$scriptPath = Join-Path -Path $Root -ChildPath $ScriptName
$scriptText = Get-Content -LiteralPath $scriptPath -Raw
if ($scriptText -notmatch "\`$script:ApplicationVersion = `"$([regex]::Escape($ReleaseVersion))`"") {
    throw "$ScriptName ne contient pas la version applicative $ReleaseVersion."
}

$distDir = Join-Path -Path $Root -ChildPath "dist"
if ($Clean -and (Test-Path -LiteralPath $distDir -PathType Container)) {
    Remove-Item -LiteralPath $distDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $distDir | Out-Null

$packageDir = Join-Path -Path $distDir -ChildPath "$ProductName-v$ReleaseVersion"
if (Test-Path -LiteralPath $packageDir) {
    Remove-Item -LiteralPath $packageDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $packageDir | Out-Null

$filesToPackage = @(
    $ScriptName,
    "README.md",
    "LICENSE",
    "VERSION",
    "CHANGELOG.md"
)

foreach ($file in $filesToPackage) {
    Copy-Item -LiteralPath (Join-Path -Path $Root -ChildPath $file) -Destination (Join-Path -Path $packageDir -ChildPath $file) -Force
}

$versionedScript = Join-Path -Path $distDir -ChildPath "Get-RunescapeClanMembers-v$ReleaseVersion.ps1"
Copy-Item -LiteralPath $scriptPath -Destination $versionedScript -Force

$zipPath = Join-Path -Path $distDir -ChildPath "$ProductName-v$ReleaseVersion-portable.zip"
if (Test-Path -LiteralPath $zipPath -PathType Leaf) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path -Path $packageDir -ChildPath "*") -DestinationPath $zipPath -Force

$scriptHash = New-Sha256File -Path $versionedScript
$zipHash = New-Sha256File -Path $zipPath
$commit = Get-GitValue -Arguments @("rev-parse", "HEAD")
$generatedAt = (Get-Date).ToUniversalTime().ToString("o")

$manifest = [PSCustomObject]@{
    name        = "RuneScape Clan Roster Exporter"
    version     = $ReleaseVersion
    tag         = "v$ReleaseVersion"
    generatedAt = $generatedAt
    commit      = $commit
    assets      = @(
        [PSCustomObject]@{
            name   = (Split-Path -Path $versionedScript -Leaf)
            type   = "powershell-script"
            sha256 = $scriptHash.Sha256
        },
        [PSCustomObject]@{
            name   = (Split-Path -Path $zipPath -Leaf)
            type   = "portable-zip"
            sha256 = $zipHash.Sha256
        }
    )
}

$manifestPath = Join-Path -Path $distDir -ChildPath "$ProductName-v$ReleaseVersion.release-manifest.json"
$manifestJson = $manifest | ConvertTo-Json -Depth 6
Write-Utf8File -Path $manifestPath -Content ($manifestJson + "`n")
$manifestHash = New-Sha256File -Path $manifestPath

$changelogNotes = Get-ChangelogSection -ReleaseVersion $ReleaseVersion
$releaseNotes = @"
$changelogNotes

## Assets officiels

- Script PowerShell : ``$(Split-Path -Path $versionedScript -Leaf)``
- ZIP portable : ``$(Split-Path -Path $zipPath -Leaf)``
- Manifeste : ``$(Split-Path -Path $manifestPath -Leaf)``

## Empreintes SHA256

- ``$(Split-Path -Path $versionedScript -Leaf)`` : ``$($scriptHash.Sha256)``
- ``$(Split-Path -Path $zipPath -Leaf)`` : ``$($zipHash.Sha256)``
- ``$(Split-Path -Path $manifestPath -Leaf)`` : ``$($manifestHash.Sha256)``

## Vérification publique

- Données RuneScape ou OSRS transmises pendant cette mise en ligne : ``non``.
- Les exports générés restent exclus du dépôt et des assets de release.
"@

$notesPath = Join-Path -Path $distDir -ChildPath "$ProductName-v$ReleaseVersion.release-notes.md"
Write-Utf8File -Path $notesPath -Content ($releaseNotes.Trim() + "`n")

Write-Host "Release preparee : v$ReleaseVersion"
Write-Host "Script : $versionedScript"
Write-Host "ZIP : $zipPath"
Write-Host "Manifest : $manifestPath"
Write-Host "Notes : $notesPath"
