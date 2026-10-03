[CmdletBinding()]
param(
    [switch]$NetworkSmoke,
    [ValidateSet('Dev', 'Full')]
    [string]$Profile = 'Full'
)

$ErrorActionPreference = "Stop"
$Root = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath ".."))
$MainScript = Join-Path -Path $Root -ChildPath "Get-RunescapeClanMembers.ps1"
function Initialize-ValidationConsole {
    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
        [Console]::OutputEncoding = $utf8NoBom
        [Console]::InputEncoding = $utf8NoBom
        $global:OutputEncoding = $utf8NoBom
    }
    catch {
        Write-Verbose "Could not adjust validation encoding: $($_.Exception.Message)"
    }

    if ($env:OS -eq "Windows_NT" -and -not [Console]::IsOutputRedirected) {
        try {
            cmd.exe /c "chcp 65001 >nul" | Out-Null
        }
        catch {
            Write-Verbose "Could not change the console code page: $($_.Exception.Message)"
        }
    }
}

function Get-CommandSource {
    param([string]$Name)

    $command = Get-Command -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($null -eq $command) {
        return ""
    }

    return $command.Source
}

function Invoke-NativeCheck {
    param(
        [string]$Label,
        [string]$CommandPath,
        [string[]]$Arguments
    )

    Write-Host "==> $Label"
    & $CommandPath @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed (exit $LASTEXITCODE)."
    }
}

function Invoke-NetworkSmokeCheck {
    param([string]$CommandPath)

    $tempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "rs-clan-roster-exporter-network-smoke-$PID-$(Get-Date -Format 'yyyyMMddHHmmssfff')"

    try {
        [System.IO.Directory]::CreateDirectory($tempRoot) | Out-Null
        Invoke-NativeCheck -Label "PowerShell 7 - Network smoke OSRS" -CommandPath $CommandPath -Arguments @(
            "-NoProfile",
            "-File",
            $MainScript,
            "-NonInteractive",
            "-Game",
            "OSRS",
            "-OsrsGroupId",
            "257",
            "-OutputFormat",
            "Csv",
            "-OutputDir",
            $tempRoot,
            "-PreviewCount",
            "1",
            "-TimeoutSec",
            "45",
            "-MaxRetries",
            "2",
            "-RequestDelaySec",
            "0"
        )

        $exports = @(Get-ChildItem -LiteralPath $tempRoot -Filter "*.csv" -File)

        if ($exports.Count -lt 1) {
            throw "The network smoke test did not generate any CSV file in $tempRoot."
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-ScriptAnalyzerCheck {
    $tools = Get-Content (Join-Path $PSScriptRoot 'toolchain.json') -Raw | ConvertFrom-Json
    Import-Module PSScriptAnalyzer -RequiredVersion $tools.scriptAnalyzer -Force -ErrorAction Stop
    $analyzer = Get-Command -Name Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue

    if ($null -eq $analyzer) {
        throw "PSScriptAnalyzer is required. Run scripts/Setup-Tools.ps1."
    }

    Write-Host "==> PSScriptAnalyzer errors"
    $issues = foreach ($path in (@($MainScript) + @(Get-ChildItem $PSScriptRoot -Filter '*.ps1' -File | ForEach-Object FullName) + @(Get-ChildItem (Join-Path $Root 'tests') -Filter '*.ps1' -File | ForEach-Object FullName))) {
        $tokens = $null
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count -gt 0) { throw "PowerShell parse errors in $path : $parseErrors" }
        Invoke-ScriptAnalyzer -Path $path -Settings (Join-Path $PSScriptRoot 'PSScriptAnalyzerSettings.psd1')
    }

    $issues = @($issues)

    if ($issues.Count -gt 0) {
        $issues | Format-Table -AutoSize | Out-String | Write-Host
        throw "PSScriptAnalyzer found $($issues.Count) error(s)."
    }
}

Initialize-ValidationConsole
Set-Location -LiteralPath $Root

if (-not (Test-Path -LiteralPath $MainScript -PathType Leaf)) {
    throw "Main script not found: $MainScript"
}

$pwsh = Get-CommandSource -Name "pwsh"

if ([string]::IsNullOrWhiteSpace($pwsh)) {
    throw "PowerShell 7 is required. Run scripts/setup-cloud.sh on Ubuntu."
} else {
    Invoke-NativeCheck -Label "PowerShell 7 - Version" -CommandPath $pwsh -Arguments @("-NoProfile", "-File", $MainScript, "-Version")
    Invoke-NativeCheck -Label "PowerShell 7 - SelfTest" -CommandPath $pwsh -Arguments @("-NoProfile", "-File", $MainScript, "-SelfTest")
}

if ($env:OS -eq "Windows_NT") {
    $windowsPowerShell = Get-CommandSource -Name "powershell.exe"

    if ([string]::IsNullOrWhiteSpace($windowsPowerShell)) {
        Write-Warning "powershell.exe not found; Windows PowerShell 5.1 validation skipped."
    } else {
        Invoke-NativeCheck -Label "Windows PowerShell - Version (real file)" -CommandPath $windowsPowerShell -Arguments @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $MainScript, '-Version')
        Invoke-NativeCheck -Label "Windows PowerShell - SelfTest (real file)" -CommandPath $windowsPowerShell -Arguments @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $MainScript, '-SelfTest')
    }
}

Invoke-ScriptAnalyzerCheck
Invoke-NativeCheck -Label 'Offline exporter integration' -CommandPath $pwsh -Arguments @('-NoProfile', '-NonInteractive', '-File', (Join-Path $Root 'tests/Test-Exporter.ps1'))
$node = Get-CommandSource -Name 'node'
if ([string]::IsNullOrWhiteSpace($node)) { throw 'Node.js is required for site checks; run the setup.' }
Invoke-NativeCheck -Label 'Site JavaScript syntax' -CommandPath $node -Arguments @('--check', (Join-Path $Root 'docs/assets/site.js'))
Invoke-NativeCheck -Label 'Site contracts and release states' -CommandPath $node -Arguments @('--test', (Join-Path $Root 'tests/site.test.cjs'))
if ($Profile -eq 'Full') {
    Invoke-NativeCheck -Label 'Release packaging' -CommandPath $pwsh -Arguments @('-NoProfile', '-NonInteractive', '-File', (Join-Path $Root 'tests/Test-Release.ps1'))
} else {
    Write-Host 'Dev excludes release packaging, live APIs and browser rendering. Use Full and targeted integrations before publication.'
}

if ($NetworkSmoke) {
    if ([string]::IsNullOrWhiteSpace($pwsh)) {
        throw "-NetworkSmoke requires pwsh to keep the smoke test consistent with Linux/macOS."
    }

    Invoke-NetworkSmokeCheck -CommandPath $pwsh
}

Write-Host "Local validation complete."
