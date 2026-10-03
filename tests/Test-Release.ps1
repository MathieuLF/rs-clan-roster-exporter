[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('roster-package-' + [guid]::NewGuid())
try {
    & (Join-Path $root 'scripts/Build-Release.ps1') -OutputDirectory $scratch
    $manifestPath = @(Get-ChildItem $scratch -Filter '*.release-manifest.json')[0].FullName
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    foreach ($asset in $manifest.assets) {
        $path = Join-Path $scratch $asset.name
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -ne $asset.sha256) { throw "Manifest checksum mismatch: $($asset.name)" }
        if ((Get-Content "$path.sha256" -Raw).Split(' ')[0] -ne $hash) { throw "Checksum file mismatch: $path" }
    }
    $manifestHash = (Get-FileHash $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ((Get-Content "$manifestPath.sha256" -Raw).Split(' ')[0] -ne $manifestHash) { throw 'Manifest checksum mismatch.' }
    $zip = @(Get-ChildItem $scratch -Filter '*.zip')[0].FullName
    $unpacked = Join-Path $scratch 'unpacked'
    Expand-Archive -LiteralPath $zip -DestinationPath $unpacked
    $names = @(Get-ChildItem $unpacked -File | ForEach-Object Name | Sort-Object)
    $expected = @('CHANGELOG.md','Get-RunescapeClanMembers.ps1','LICENSE','README.md','VERSION')
    if (Compare-Object $expected $names) { throw 'Portable archive must contain exactly the five public distribution files.' }
    & (Get-Command pwsh).Source -NoProfile -NonInteractive -File (Join-Path $unpacked 'Get-RunescapeClanMembers.ps1') -SelfTest
    if ($LASTEXITCODE -ne 0) { throw 'Packaged exporter failed its self-test.' }
    Write-Host 'Release archive, manifest, checksums and packaged self-tests passed.'
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
