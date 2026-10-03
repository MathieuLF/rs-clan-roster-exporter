[CmdletBinding()]
param()
$ErrorActionPreference = "Stop"
$tools = Get-Content (Join-Path $PSScriptRoot "toolchain.json") -Raw | ConvertFrom-Json
if (-not (Get-Module -ListAvailable PSScriptAnalyzer | Where-Object Version -EQ $tools.scriptAnalyzer)) {
    Install-Module PSScriptAnalyzer -RequiredVersion $tools.scriptAnalyzer -Scope CurrentUser -Repository PSGallery -Force -ErrorAction Stop
}
Import-Module PSScriptAnalyzer -RequiredVersion $tools.scriptAnalyzer -Force
Write-Host "PSScriptAnalyzer $($tools.scriptAnalyzer) ready."
