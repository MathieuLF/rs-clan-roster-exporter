[CmdletBinding()]
param(
    [switch]$NetworkSmoke
)

$ErrorActionPreference = "Stop"
$Root = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath ".."))
$MainScript = Join-Path -Path $Root -ChildPath "Get-RunescapeClanMembers.ps1"
$ReleaseScripts = @(
    Join-Path -Path $Root -ChildPath "scripts\Build-Release.ps1"
    Join-Path -Path $Root -ChildPath "scripts\Publish-Release.ps1"
    $PSCommandPath
)

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

function Invoke-WindowsPowerShellUtf8ScriptCheck {
    param(
        [string]$Label,
        [string]$CommandPath,
        [string]$ScriptPath,
        [string[]]$ScriptArguments
    )

    Write-Host "==> $Label"

    $escapedScriptPath = $ScriptPath.Replace("'", "''")
    $argumentTokens = @($ScriptArguments | ForEach-Object {
        if ($_ -match "^-[A-Za-z][A-Za-z0-9]*$") {
            $_
        } else {
            "'$($_.Replace("'", "''"))'"
        }
    }) -join " "

    $command = @"
`$utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList `$false
[Console]::OutputEncoding = `$utf8NoBom
[Console]::InputEncoding = `$utf8NoBom
`$global:OutputEncoding = `$utf8NoBom
`$ProgressPreference = 'SilentlyContinue'
if (`$env:OS -eq 'Windows_NT' -and -not [Console]::IsOutputRedirected) {
    cmd.exe /c 'chcp 65001 >nul' | Out-Null
}
Set-Location -LiteralPath '$($Root.Replace("'", "''"))'
`$scriptText = [System.IO.File]::ReadAllText('$escapedScriptPath', [System.Text.Encoding]::UTF8)
`$scriptBlock = [scriptblock]::Create(`$scriptText)
& `$scriptBlock $argumentTokens
exit `$LASTEXITCODE
"@

    $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($command))
    $output = @(& $CommandPath -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encodedCommand 2>&1)
    $exitCode = $LASTEXITCODE

    foreach ($entry in $output) {
        $text = [string]$entry

        if ($text -like "#< CLIXML*" -or $text -like "<Objs Version=*") {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($text)) {
            Write-Host $text
        }
    }

    if ($exitCode -ne 0) {
        throw "$Label failed (exit $exitCode)."
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
    $analyzer = Get-Command -Name Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue

    if ($null -eq $analyzer) {
        Write-Warning "PSScriptAnalyzer not found; static analysis skipped."
        return
    }

    Write-Host "==> PSScriptAnalyzer errors"
    $issues = foreach ($path in (@($MainScript) + $ReleaseScripts)) {
        Invoke-ScriptAnalyzer -Path $path -Severity Error
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
    Write-Warning "pwsh not found; PowerShell 7 validation skipped."
} else {
    Invoke-NativeCheck -Label "PowerShell 7 - Version" -CommandPath $pwsh -Arguments @("-NoProfile", "-File", $MainScript, "-Version")
    Invoke-NativeCheck -Label "PowerShell 7 - SelfTest" -CommandPath $pwsh -Arguments @("-NoProfile", "-File", $MainScript, "-SelfTest")
}

if ($env:OS -eq "Windows_NT") {
    $windowsPowerShell = Get-CommandSource -Name "powershell.exe"

    if ([string]::IsNullOrWhiteSpace($windowsPowerShell)) {
        Write-Warning "powershell.exe not found; Windows PowerShell 5.1 validation skipped."
    } else {
        Invoke-WindowsPowerShellUtf8ScriptCheck -Label "Windows PowerShell - Version" -CommandPath $windowsPowerShell -ScriptPath $MainScript -ScriptArguments @("-Version")
        Invoke-WindowsPowerShellUtf8ScriptCheck -Label "Windows PowerShell - SelfTest" -CommandPath $windowsPowerShell -ScriptPath $MainScript -ScriptArguments @("-SelfTest")
    }
}

Invoke-ScriptAnalyzerCheck

if ($NetworkSmoke) {
    if ([string]::IsNullOrWhiteSpace($pwsh)) {
        throw "-NetworkSmoke requires pwsh to keep the smoke test consistent with Linux/macOS."
    }

    Invoke-NetworkSmokeCheck -CommandPath $pwsh
}

Write-Host "Local validation complete."
