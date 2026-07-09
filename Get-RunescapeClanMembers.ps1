#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Exports members from a RuneScape 3 clan or OSRS group.

.DESCRIPTION
  The script can run interactively or with parameters.

  RS3 uses the public Jagex Clan Members Lite endpoint.
  OSRS uses the public Wise Old Man API because OSRS does not expose the same
  public Jagex clan CSV.

  Available output formats:
    - Markdown
    - CSV

.EXAMPLE
  .\Get-RunescapeClanMembers.ps1

.EXAMPLE
  .\Get-RunescapeClanMembers.ps1 -Game RS3 -ClanName "Wapitiklan Empire" -OutputFormat Csv

.EXAMPLE
  .\Get-RunescapeClanMembers.ps1 -Game OSRS -ClanName "KnightSlayer" -OutputFormat Markdown

.EXAMPLE
  .\Get-RunescapeClanMembers.ps1 -Game Both -ClanName "KnightSlayer" -OutputFormat Csv

.NOTES
  Compatible with Windows PowerShell 5.1+ and PowerShell 7+.
#>

[CmdletBinding()]
param(
    [string]$Game,
    [string]$ClanName,
    [string]$OutputFormat,
    [string]$OutputDir = ".\output",
    [ValidateRange(5, 300)]
    [int]$TimeoutSec = 90,
    [ValidateRange(1, 8)]
    [int]$MaxRetries = 4,
    [ValidateRange(0, 60)]
    [int]$RequestDelaySec = 2,
    [ValidateRange(1, 120)]
    [int]$RetryBaseDelaySec = 8,
    [ValidateRange(5, 600)]
    [int]$MaxRetryDelaySec = 120,
    [ValidateRange(25, 5000)]
    [int]$OutputChunkSize = 250,
    [ValidateRange(1, 500)]
    [int]$PreviewCount = 50,
    [ValidateRange(0, 2147483647)]
    [int]$OsrsGroupId,
    [string]$RepositoryUrl,
    [switch]$ShowAllInConsole,
    [switch]$OpenFolder,
    [switch]$AllowInsecureFallback,
    [switch]$KeepRecoveryFile,
    [switch]$Version,
    [switch]$SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$script:ApplicationVersion = "0.2.0"
$script:LastHttpRequestAt = $null
$script:ConfiguredRetryBaseDelaySec = $RetryBaseDelaySec
$script:ConfiguredMaxRetryDelaySec = $MaxRetryDelaySec
$script:ConfiguredRepositoryUrl = $RepositoryUrl
$script:ConfiguredPlainUi = ($env:RS_CLAN_PLAIN_UI -match "^(1|true|yes|on)$")

function Get-ScriptBaseDirectory {
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        return [System.IO.Path]::GetFullPath($PSScriptRoot)
    }

    if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
        return [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($PSCommandPath))
    }

    return [System.IO.Path]::GetFullPath((Get-Location).Path)
}

function Initialize-Console {
    try {
        $utf8Bom = New-Object System.Text.UTF8Encoding -ArgumentList $true
        [Console]::OutputEncoding = $utf8Bom
        [Console]::InputEncoding = $utf8Bom
        $global:OutputEncoding = $utf8Bom
        $PSDefaultParameterValues["Out-File:Encoding"] = "utf8"
    } catch {
        Write-Verbose "Could not adjust console encoding: $($_.Exception.Message)"
    }

    if ($env:OS -eq "Windows_NT" -and -not [Console]::IsOutputRedirected) {
        try {
            cmd.exe /c "chcp 65001 >nul" | Out-Null
        } catch {
            Write-Verbose "Could not change the console code page: $($_.Exception.Message)"
        }
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    } catch {
        Write-Verbose "Could not force TLS 1.2 in this host: $($_.Exception.Message)"
    }
}

function Write-Console {
    param(
        [AllowEmptyString()]
        [string]$Message = "",
        [System.ConsoleColor]$ForegroundColor
    )

    try {
        if ($PSBoundParameters.ContainsKey("ForegroundColor")) {
            $Host.UI.WriteLine($ForegroundColor, $Host.UI.RawUI.BackgroundColor, $Message)
        } else {
            $Host.UI.WriteLine($Message)
        }
    }
    catch {
        Write-Verbose "Could not write through the PowerShell host: $($_.Exception.Message)"
        Write-Information -MessageData $Message -InformationAction Continue
    }
}

function Test-DecoratedConsole {
    if ($script:ConfiguredPlainUi) {
        return $false
    }

    if ($PSVersionTable.PSVersion.Major -lt 6) {
        return $false
    }

    try {
        return (-not [Console]::IsOutputRedirected)
    }
    catch {
        return $false
    }
}

function Get-UiMarker {
    param(
        [string]$Kind,
        [string]$Fallback
    )

    if (-not (Test-DecoratedConsole)) {
        return $Fallback
    }

    switch ($Kind) {
        "Info" { return [char]::ConvertFromUtf32(0x2139) }
        "Ok" { return [char]::ConvertFromUtf32(0x2705) }
        "Warn" { return [char]::ConvertFromUtf32(0x26A0) }
        "Fail" { return [char]::ConvertFromUtf32(0x274C) }
        "Search" { return [char]::ConvertFromUtf32(0x1F50E) }
        "Summary" { return [char]::ConvertFromUtf32(0x1F4CB) }
        "Export" { return [char]::ConvertFromUtf32(0x1F4E6) }
        default { return $Fallback }
    }
}

function Write-Info {
    param([string]$Message)
    Write-Console "$(Get-UiMarker -Kind "Info" -Fallback "[INFO]") $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Console "$(Get-UiMarker -Kind "Ok" -Fallback "[OK]  ") $Message" -ForegroundColor Green
}

function Write-Warn2 {
    param([string]$Message)
    Write-Console "$(Get-UiMarker -Kind "Warn" -Fallback "[WARN]") $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Console "$(Get-UiMarker -Kind "Fail" -Fallback "[FAIL]") $Message" -ForegroundColor Red
}

function ConvertTo-FileUri {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path)
        return ([System.Uri]$fullPath).AbsoluteUri
    } catch {
        return $null
    }
}

function Write-LocalPath {
    param(
        [string]$Label,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    Write-Ok "${Label}: $fullPath"

    $fileUri = ConvertTo-FileUri -Path $fullPath

    if (-not [string]::IsNullOrWhiteSpace($fileUri)) {
        Write-Info "Local link: $fileUri"
    }
}

function Open-OutputDirectory {
    param(
        [string]$Path,
        [switch]$ProbeOnly
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        Write-Warn2 "No output folder to open."
        return $false
    }

    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path)
    }
    catch {
        Write-Warn2 "Invalid output path: $Path"
        return $false
    }

    if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
        Write-Warn2 "Output folder not found: $fullPath"
        return $false
    }

    if ($ProbeOnly) {
        return $true
    }

    try {
        Invoke-Item -LiteralPath $fullPath -ErrorAction Stop
        return $true
    }
    catch {
        Write-Warn2 "Could not open the output folder automatically: $fullPath"
        Write-Warn2 "Open it manually from the path shown above."
        return $false
    }
}

function Test-CanPrompt {
    try {
        return (-not [Console]::IsInputRedirected)
    } catch {
        return $true
    }
}

function ConvertTo-Game {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $clean = $Value.Trim()

    switch -Regex ($clean) {
        "^(1|rs3|runescape\s*3|runescape)$" { return "RS3" }
        "^(2|osrs|old\s*school|old\s*school\s*runescape)$" { return "OSRS" }
        "^(3|both|all|tout|tous|les\s*deux|rs3\s*\+\s*osrs|osrs\s*\+\s*rs3)$" { return "Both" }
    }

    throw "Invalid game: '$Value'. Accepted values: RS3, OSRS, or Both."
}

function ConvertTo-OutputFormat {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $clean = $Value.Trim()

    switch -Regex ($clean) {
        "^(1|md|markdown)$" { return "Markdown" }
        "^(2|csv)$" { return "Csv" }
    }

    throw "Invalid format: '$Value'. Accepted values: Markdown or CSV."
}

function ConvertTo-ClanName {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $clean = $Value.Trim()
    $clean = $clean.Replace([char]0x00A0, " ").Replace([char]0x202F, " ")
    $clean = $clean -replace "\s+", " "

    if ($clean.Length -lt 2) {
        throw "The clan name must contain at least 2 characters."
    }

    if ($clean.Length -gt 100) {
        throw "The clan name is too long. Limit: 100 characters."
    }

    if ($clean -match "[\x00-\x1F]") {
        throw "The clan name contains an invalid control character."
    }

    return $clean
}

function Read-Choice {
    param(
        [string]$Question,
        [string[]]$AllowedValues,
        [string[]]$Labels
    )

    if ($null -eq $AllowedValues -or $AllowedValues.Count -eq 0) {
        throw "No choices available for this question: $Question"
    }

    if ($null -ne $Labels -and $Labels.Count -ne $AllowedValues.Count) {
        throw "The label list must contain the same number of items as the choice list."
    }

    $range = if ($AllowedValues.Count -eq 1) { "1" } else { "1-$($AllowedValues.Count)" }

    while ($true) {
        Write-Console $Question -ForegroundColor White

        for ($i = 0; $i -lt $AllowedValues.Count; $i++) {
            $label = $AllowedValues[$i]

            if ($null -ne $Labels -and -not [string]::IsNullOrWhiteSpace($Labels[$i])) {
                $label = $Labels[$i]
            }

            Write-Console ("  {0}) {1}" -f ($i + 1), $label) -ForegroundColor White
        }

        $answer = Read-Host "Your choice ($range)"

        $choice = 0

        if ([int]::TryParse($answer, [ref]$choice) -and $choice -ge 1 -and $choice -le $AllowedValues.Count) {
            return $AllowedValues[$choice - 1]
        }

        Write-Warn2 "Expected answer: a number between 1 and $($AllowedValues.Count)."
    }
}

function Read-RequiredText {
    param([string]$Question)

    while ($true) {
        $answer = Read-Host $Question

        try {
            $clean = ConvertTo-ClanName -Value $answer

            if (-not [string]::IsNullOrWhiteSpace($clean)) {
                return $clean
            }
        }
        catch {
            Write-Warn2 $_.Exception.Message
        }
    }
}

function Resolve-InteractiveOption {
    param(
        [string]$Game,
        [string]$ClanName,
        [string]$OutputFormat,
        [int]$OsrsGroupId
    )

    $resolvedGame = ConvertTo-Game -Value $Game
    $resolvedFormat = ConvertTo-OutputFormat -Value $OutputFormat
    $resolvedClan = ConvertTo-ClanName -Value $ClanName

    if ([string]::IsNullOrWhiteSpace($resolvedGame)) {
        if (-not (Test-CanPrompt)) {
            throw "The -Game parameter is required in non-interactive mode. Values: RS3, OSRS, or Both."
        }

        Write-Console ""
        $resolvedGame = Read-Choice -Question "Target game" -AllowedValues @("RS3", "OSRS", "Both") -Labels @("RS3: RuneScape 3 clan through Jagex", "OSRS: OSRS group through Wise Old Man", "Both: search RS3 and OSRS")
    }

    if ([string]::IsNullOrWhiteSpace($resolvedClan) -and -not ($resolvedGame -eq "OSRS" -and $OsrsGroupId -gt 0)) {
        if (-not (Test-CanPrompt)) {
            throw "The -ClanName parameter is required in non-interactive mode."
        }

        if ($resolvedGame -eq "OSRS") {
            $resolvedClan = Read-RequiredText -Question "OSRS group/clan name to search"
        } elseif ($resolvedGame -eq "Both") {
            $resolvedClan = Read-RequiredText -Question "Clan/group name to search in RS3 and OSRS"
        } else {
            $resolvedClan = Read-RequiredText -Question "RS3 clan name to search"
        }
    }

    if ([string]::IsNullOrWhiteSpace($resolvedFormat)) {
        if (-not (Test-CanPrompt)) {
            throw "The -OutputFormat parameter is required in non-interactive mode. Values: Markdown or CSV."
        }

        $resolvedFormat = Read-Choice -Question "Output format" -AllowedValues @("Markdown", "Csv") -Labels @("Markdown (.md)", "CSV (.csv)")
    }

    [PSCustomObject]@{
        Game         = $resolvedGame
        ClanName     = $resolvedClan
        OutputFormat = $resolvedFormat
    }
}

function Get-SafeSlug {
    param([string]$Text)

    $slug = $Text.ToLowerInvariant()
    $slug = $slug -replace "[^a-z0-9]+", "-"
    $slug = $slug.Trim("-")

    if ([string]::IsNullOrWhiteSpace($slug)) {
        return "clan"
    }

    return $slug
}

function Get-FileTimestamp {
    return (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
}

function Get-ResponseSample {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    $clean = $Text.Trim()
    return $clean.Substring(0, [Math]::Min(250, $clean.Length))
}

function Get-HttpHeader {
    param([string]$Accept)

    $userAgent = "RunescapeClanMembersExporter/$script:ApplicationVersion PowerShell/$($PSVersionTable.PSVersion)"

    if (-not [string]::IsNullOrWhiteSpace($script:ConfiguredRepositoryUrl)) {
        $userAgent = "$userAgent ($script:ConfiguredRepositoryUrl)"
    }

    @{
        "User-Agent" = $userAgent
        "Accept"     = $Accept
    }
}

function Wait-RequestPace {
    param(
        [int]$MinimumDelaySec,
        [string]$Purpose
    )

    if ($MinimumDelaySec -le 0 -or $null -eq $script:LastHttpRequestAt) {
        return
    }

    $elapsed = (Get-Date) - $script:LastHttpRequestAt
    $remaining = [Math]::Ceiling($MinimumDelaySec - $elapsed.TotalSeconds)

    if ($remaining -le 0) {
        return
    }

    Write-Info "Gentle network pause of $remaining second(s) before the next call."

    for ($i = $remaining; $i -gt 0; $i--) {
        Write-Progress -Activity $Purpose -Status "Respectful network pause ($i s)" -SecondsRemaining $i -PercentComplete 5
        Start-Sleep -Seconds 1
    }
}

function Get-RetryAfterSecond {
    param([object]$ErrorRecord)

    try {
        $response = $ErrorRecord.Exception.Response

        if ($null -eq $response -or $null -eq $response.Headers) {
            return $null
        }

        $retryAfter = $response.Headers["Retry-After"]

        if ([string]::IsNullOrWhiteSpace($retryAfter)) {
            return $null
        }

        $seconds = 0

        if ([int]::TryParse($retryAfter, [ref]$seconds) -and $seconds -gt 0) {
            return $seconds
        }

        $retryDate = [DateTime]::MinValue

        if ([DateTime]::TryParse($retryAfter, [ref]$retryDate)) {
            $delta = $retryDate.ToUniversalTime() - (Get-Date).ToUniversalTime()

            if ($delta.TotalSeconds -gt 0) {
                return [Math]::Ceiling($delta.TotalSeconds)
            }
        }
    } catch {
        return $null
    }

    return $null
}

function Get-HttpStatusCode {
    param([object]$ErrorRecord)

    try {
        if ($null -ne $ErrorRecord.Exception.Response -and $null -ne $ErrorRecord.Exception.Response.StatusCode) {
            return [int]$ErrorRecord.Exception.Response.StatusCode
        }
    } catch {
        return $null
    }

    return $null
}

function Test-IsPermanentHttpStatusCode {
    param([int]$StatusCode)

    return ($StatusCode -in @(400, 401, 403, 404))
}

function Get-RetryDelaySecond {
    param(
        [int]$Attempt,
        [object]$ErrorRecord
    )

    $retryAfter = Get-RetryAfterSecond -ErrorRecord $ErrorRecord

    if ($null -ne $retryAfter) {
        return [Math]::Min($script:ConfiguredMaxRetryDelaySec, [Math]::Max($script:ConfiguredRetryBaseDelaySec, [int]$retryAfter))
    }

    $exponentialDelay = [int]($script:ConfiguredRetryBaseDelaySec * [Math]::Pow(2, [Math]::Max(0, $Attempt - 1)))
    $jitter = Get-Random -Minimum 0 -Maximum 4
    return [Math]::Min($script:ConfiguredMaxRetryDelaySec, ($exponentialDelay + $jitter))
}

function Wait-RetryDelay {
    param(
        [int]$Seconds,
        [string]$Purpose
    )

    if ($Seconds -le 0) {
        return
    }

    Write-Info "Pausing $Seconds second(s), then retrying."

    for ($remaining = $Seconds; $remaining -gt 0; $remaining--) {
        Write-Progress -Activity $Purpose -Status "Retry in $remaining s" -SecondsRemaining $remaining -PercentComplete 10

        if ($remaining -le 3 -or $remaining % 10 -eq 0) {
            Write-Info "Resuming in $remaining second(s)..."
        }

        Start-Sleep -Seconds 1
    }
}

function Invoke-HttpText {
    param(
        [string]$Url,
        [string]$Accept,
        [int]$TimeoutSec,
        [int]$MaxRetries,
        [string]$Purpose
    )

    $headers = Get-HttpHeader -Accept $Accept
    $lastMessage = $null

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            $percent = [Math]::Min(95, [int](($attempt / [Math]::Max($MaxRetries, 1)) * 60))
            Write-Progress -Activity $Purpose -Status "Attempt $attempt/$MaxRetries" -PercentComplete $percent
            Wait-RequestPace -MinimumDelaySec $RequestDelaySec -Purpose $Purpose
            Write-Info "Attempt $attempt/${MaxRetries}: $Url"

            $request = @{
                Uri        = $Url
                Headers    = $headers
                TimeoutSec = $TimeoutSec
                Method     = "GET"
            }

            if ($PSVersionTable.PSVersion.Major -lt 6) {
                $request.UseBasicParsing = $true
            }

            $response = Invoke-WebRequest @request
            $script:LastHttpRequestAt = Get-Date

            if ($null -eq $response -or [string]::IsNullOrWhiteSpace([string]$response.Content)) {
                throw "Empty response."
            }

            Write-Progress -Activity $Purpose -Completed
            return [string]$response.Content
        }
        catch {
            $script:LastHttpRequestAt = Get-Date
            $lastMessage = $_.Exception.Message
            $statusCode = Get-HttpStatusCode -ErrorRecord $_

            if ($null -ne $statusCode) {
                Write-Warn2 "Attempt $attempt failed (HTTP $statusCode): $lastMessage"
            } else {
                Write-Warn2 "Attempt $attempt failed: $lastMessage"
            }

            if ($null -ne $statusCode -and (Test-IsPermanentHttpStatusCode -StatusCode $statusCode)) {
                Write-Progress -Activity $Purpose -Completed
                throw "Permanent HTTP error ($statusCode) during '$Purpose'. The request will not be retried. Last error: $lastMessage"
            }

            if ($attempt -lt $MaxRetries) {
                $sleepSeconds = Get-RetryDelaySecond -Attempt $attempt -ErrorRecord $_
                Wait-RetryDelay -Seconds $sleepSeconds -Purpose $Purpose
            }
        }
    }

    Write-Progress -Activity $Purpose -Completed
    throw "All attempts failed. Last error: $lastMessage"
}

function Invoke-HttpJson {
    param(
        [string]$Url,
        [int]$TimeoutSec,
        [int]$MaxRetries,
        [string]$Purpose
    )

    $content = Invoke-HttpText -Url $Url -Accept "application/json" -TimeoutSec $TimeoutSec -MaxRetries $MaxRetries -Purpose $Purpose

    try {
        return $content | ConvertFrom-Json
    }
    catch {
        throw "The JSON response could not be read. Detail: $($_.Exception.Message). Response received: $(Get-ResponseSample -Text $content)"
    }
}

function ConvertTo-ClanValue {
    param([object]$Value)

    if ($null -eq $Value) {
        return ""
    }

    return ([string]$Value).Replace([char]0x00A0, " ").Replace([char]0x202F, " ").Trim()
}

function Get-ObjectPropertyValue {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($Name)) {
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]

    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Get-CsvField {
    param(
        [psobject]$Row,
        [string[]]$Names
    )

    foreach ($property in $Row.PSObject.Properties) {
        $propertyName = ConvertTo-ClanValue -Value $property.Name

        foreach ($name in $Names) {
            if ($propertyName -ieq $name) {
                return $property.Value
            }
        }
    }

    return $null
}

function ConvertFrom-Rs3ClanMembersCsv {
    param(
        [string]$CsvText,
        [string]$ClanName
    )

    $trimmed = $CsvText.Trim()

    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        throw "The returned CSV is empty."
    }

    if ($trimmed -match "^\s*(<!doctype|<html|<\?xml)" -or $trimmed -match "(?i)\b(access denied|temporarily unavailable)\b") {
        throw "Jagex returned an error page instead of CSV. Response received: $(Get-ResponseSample -Text $trimmed)"
    }

    $firstLine = ($trimmed -replace "^\uFEFF", "") -split "\r?\n" |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace($firstLine) -or $firstLine -notmatch ",") {
        throw "The response does not look like CSV. Response received: $(Get-ResponseSample -Text $trimmed)"
    }

    $hasHeader = ($firstLine -match "(?i)\b(clanmate|clan rank|total xp|kills)\b")

    try {
        if ($hasHeader) {
            $rows = $trimmed | ConvertFrom-Csv
        } else {
            $rows = $trimmed | ConvertFrom-Csv -Header "Clanmate", "Clan Rank", "Total XP", "Kills"
        }
    }
    catch {
        throw "The returned CSV could not be read. Detail: $($_.Exception.Message). Response received: $(Get-ResponseSample -Text $trimmed)"
    }

    $members = foreach ($row in $rows) {
        $pseudo = ConvertTo-ClanValue -Value (Get-CsvField -Row $row -Names @("Pseudo", "Clanmate", "Clan Mate", "Name"))

        if ($pseudo -ieq "Clanmate") {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($pseudo)) {
            continue
        }

        [PSCustomObject]@{
            Game  = "RS3"
            Clan  = $ClanName
            Pseudo = $pseudo
            Rang  = ConvertTo-ClanValue -Value (Get-CsvField -Row $row -Names @("Rang", "Rank", "Clan Rank"))
            XP    = ConvertTo-ClanValue -Value (Get-CsvField -Row $row -Names @("XP", "Total XP", "TotalXP"))
            Kills = ConvertTo-ClanValue -Value (Get-CsvField -Row $row -Names @("Kills", "Kill Count"))
        }
    }

    $members = @($members)

    if ($members.Count -eq 0) {
        throw "No member could be read from the CSV."
    }

    return $members
}

function Get-Rs3ClanMember {
    param(
        [string]$ClanName,
        [int]$TimeoutSec,
        [int]$MaxRetries,
        [bool]$AllowInsecureFallback
    )

    $encodedClan = [uri]::EscapeDataString($ClanName)
    $urls = @(
        "https://secure.runescape.com/m=clan-hiscores/members_lite.ws?clanName=$encodedClan"
    )

    if ($AllowInsecureFallback) {
        Write-Warn2 "HTTP fallback explicitly enabled. Prefer HTTPS when possible."
        $urls += "http://services.runescape.com/m=clan-hiscores/members_lite.ws?clanName=$encodedClan"
    }

    $lastMessage = $null

    foreach ($url in $urls) {
        try {
            $csvText = Invoke-HttpText -Url $url -Accept "text/csv,text/plain,*/*" -TimeoutSec $TimeoutSec -MaxRetries $MaxRetries -Purpose "RS3 search"
            return ConvertFrom-Rs3ClanMembersCsv -CsvText $csvText -ClanName $ClanName
        }
        catch {
            $lastMessage = $_.Exception.Message
            Write-Warn2 "Endpoint did not return usable data: $url"
        }
    }

    throw "Could not retrieve RS3 members for '$ClanName'. Last error: $lastMessage"
}

function Select-OsrsGroup {
    param(
        [object[]]$Groups,
        [string]$ClanName
    )

    $groups = @($Groups | Where-Object { $null -ne $_ })

    if ($groups.Count -eq 0) {
        throw "No Wise Old Man OSRS group matches '$ClanName'."
    }

    $exact = @($groups | Where-Object {
        ($null -ne $_.name -and $_.name -ieq $ClanName) -or
        ($null -ne $_.clanChat -and $_.clanChat -ieq $ClanName)
    })

    if ($exact.Count -eq 1) {
        return $exact[0]
    }

    if ($groups.Count -eq 1) {
        Write-Warn2 "No exact name found. Selecting the only available result: $($groups[0].name)."
        return $groups[0]
    }

    Write-Warn2 "Several OSRS groups match your search."
    Write-Console ""

    for ($i = 0; $i -lt $groups.Count; $i++) {
        $group = $groups[$i]
        $chat = ""

        if ($null -ne $group.clanChat -and -not [string]::IsNullOrWhiteSpace([string]$group.clanChat)) {
            $chat = " | clan chat: $($group.clanChat)"
        }

        Write-Console ("  {0}) {1} ({2} members{3}, id {4})" -f ($i + 1), $group.name, $group.memberCount, $chat, $group.id)
    }

    if (-not (Test-CanPrompt)) {
        throw "Several OSRS groups match. Run again with a more precise name or with -OsrsGroupId."
    }

    while ($true) {
        $answer = Read-Host "Choose the OSRS group to use [1-$($groups.Count)]"
        $choice = 0

        if ([int]::TryParse($answer, [ref]$choice) -and $choice -ge 1 -and $choice -le $groups.Count) {
            return $groups[$choice - 1]
        }

        Write-Warn2 "Expected answer: a number between 1 and $($groups.Count)."
    }
}

function ConvertFrom-OsrsGroupDetails {
    param(
        [object]$Details,
        [int]$GroupId
    )

    $memberships = Get-ObjectPropertyValue -Object $Details -Name "memberships"

    if ($null -eq $Details -or $null -eq $memberships) {
        throw "Wise Old Man did not return a member list for group id $GroupId."
    }

    $groupName = ConvertTo-ClanValue -Value (Get-ObjectPropertyValue -Object $Details -Name "name")

    if ([string]::IsNullOrWhiteSpace($groupName)) {
        $groupName = "Wise Old Man group $GroupId"
    }

    $members = foreach ($membership in @($memberships)) {
        $player = Get-ObjectPropertyValue -Object $membership -Name "player"

        if ($null -eq $player) {
            continue
        }

        $pseudo = ConvertTo-ClanValue -Value (Get-ObjectPropertyValue -Object $player -Name "displayName")

        if ([string]::IsNullOrWhiteSpace($pseudo)) {
            $pseudo = ConvertTo-ClanValue -Value (Get-ObjectPropertyValue -Object $player -Name "username")
        }

        if ([string]::IsNullOrWhiteSpace($pseudo)) {
            continue
        }

        [PSCustomObject]@{
            Game  = "OSRS"
            Clan  = $groupName
            Pseudo = $pseudo
            Rang  = ConvertTo-ClanValue -Value (Get-ObjectPropertyValue -Object $membership -Name "role")
            XP    = ConvertTo-ClanValue -Value (Get-ObjectPropertyValue -Object $player -Name "exp")
            Kills = ""
        }
    }

    $members = @($members)

    if ($members.Count -eq 0) {
        throw "No readable OSRS member was found for group '$groupName'."
    }

    return $members
}

function Get-OsrsClanMember {
    param(
        [string]$ClanName,
        [int]$OsrsGroupId,
        [int]$TimeoutSec,
        [int]$MaxRetries
    )

    Write-Warn2 "OSRS: searching through Wise Old Man. Data comes from a public WOM group, not from an official Jagex CSV."

    $selectedGroup = $null

    if ($OsrsGroupId -gt 0) {
        $selectedGroup = [PSCustomObject]@{
            id   = $OsrsGroupId
            name = "Wise Old Man group $OsrsGroupId"
        }
    } else {
        $encodedName = [uri]::EscapeDataString($ClanName)
        $searchUrl = "https://api.wiseoldman.net/v2/groups?name=$encodedName&limit=10"
        $groups = @(Invoke-HttpJson -Url $searchUrl -TimeoutSec $TimeoutSec -MaxRetries $MaxRetries -Purpose "OSRS search")
        $selectedGroup = Select-OsrsGroup -Groups $groups -ClanName $ClanName
    }

    Write-Info "Selected OSRS group: $($selectedGroup.name) (id $($selectedGroup.id))"

    $detailsUrl = "https://api.wiseoldman.net/v2/groups/$($selectedGroup.id)"
    $details = Invoke-HttpJson -Url $detailsUrl -TimeoutSec $TimeoutSec -MaxRetries $MaxRetries -Purpose "Read OSRS members"

    return ConvertFrom-OsrsGroupDetails -Details $details -GroupId $selectedGroup.id
}

function Get-OutputDirectory {
    param([string]$OutputDir)

    if ([string]::IsNullOrWhiteSpace($OutputDir)) {
        $OutputDir = ".\output"
    }

    if ([System.IO.Path]::IsPathRooted($OutputDir)) {
        $fullPath = [System.IO.Path]::GetFullPath($OutputDir)
    } else {
        $fullPath = [System.IO.Path]::GetFullPath((Join-Path -Path (Get-ScriptBaseDirectory) -ChildPath $OutputDir))
    }

    if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
        throw "The output path already exists as a file: $fullPath"
    }

    if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
        [System.IO.Directory]::CreateDirectory($fullPath) | Out-Null
    }

    return $fullPath
}

function ConvertTo-MarkdownCell {
    param([object]$Value)

    if ($null -eq $Value) {
        return ""
    }

    $text = [string]$Value
    $text = $text.Replace("|", "\|")
    $text = $text -replace "\r?\n", " "
    return $text.Trim()
}

function Get-Utf8BomEncoding {
    return (New-Object System.Text.UTF8Encoding -ArgumentList $true)
}

function Write-AtomicTextFileUtf8 {
    param(
        [string]$Path,
        [string]$Content,
        [string]$Activity = "Writing file"
    )

    $directory = Split-Path -Path $Path -Parent

    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory -PathType Container)) {
        [System.IO.Directory]::CreateDirectory($directory) | Out-Null
    }

    $tempPath = "$Path.tmp-$PID-$(Get-Date -Format 'yyyyMMddHHmmssfff')"
    $encoding = Get-Utf8BomEncoding
    $writer = $null

    try {
        Write-Progress -Activity $Activity -Status "Writing temporary file" -PercentComplete 40
        $writer = New-Object System.IO.StreamWriter($tempPath, $false, $encoding)
        $writer.Write($Content)
        $writer.Flush()
    }
    catch {
        Write-Warn2 "Write interrupted. Temporary file kept if present: $tempPath"
        throw
    }
    finally {
        if ($null -ne $writer) {
            $writer.Dispose()
        }
    }

    Write-Progress -Activity $Activity -Status "Atomic finalization" -PercentComplete 90
    Move-Item -LiteralPath $tempPath -Destination $Path -Force
    Write-Progress -Activity $Activity -Completed
}

function Write-LinesAtomicUtf8 {
    param(
        [string]$Path,
        [string[]]$Lines,
        [string]$Activity,
        [int]$ChunkSize
    )

    $directory = Split-Path -Path $Path -Parent

    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory -PathType Container)) {
        [System.IO.Directory]::CreateDirectory($directory) | Out-Null
    }

    $lineList = @($Lines)
    $total = [Math]::Max(1, $lineList.Count)
    $tempPath = "$Path.tmp-$PID-$(Get-Date -Format 'yyyyMMddHHmmssfff')"
    $encoding = Get-Utf8BomEncoding
    $writer = $null

    try {
        $writer = New-Object System.IO.StreamWriter($tempPath, $false, $encoding)

        for ($i = 0; $i -lt $lineList.Count; $i++) {
            $writer.WriteLine($lineList[$i])

            if (($i + 1) % $ChunkSize -eq 0 -or ($i + 1) -eq $lineList.Count) {
                $percent = [Math]::Min(95, [int]((($i + 1) / $total) * 90))
                Write-Progress -Activity $Activity -Status "Writing $($i + 1)/$($lineList.Count) line(s)" -PercentComplete $percent
                Write-Info "Writing $($i + 1)/$($lineList.Count) line(s)..."
            }
        }

        $writer.Flush()
    }
    catch {
        Write-Warn2 "Write interrupted. Temporary file kept if present: $tempPath"
        throw
    }
    finally {
        if ($null -ne $writer) {
            $writer.Dispose()
        }
    }

    Write-Progress -Activity $Activity -Status "Atomic finalization" -PercentComplete 98
    Move-Item -LiteralPath $tempPath -Destination $Path -Force
    Write-Progress -Activity $Activity -Completed
}

function ConvertTo-MarkdownLine {
    param(
        [object[]]$Members,
        [string]$Game,
        [string]$ClanName
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss K"

    $lines.Add("# $ClanName Clan Members")
    $lines.Add("")
    $lines.Add("- Game: $Game")
    $lines.Add("- Members: $($Members.Count)")
    $lines.Add("- Generated at: $generatedAt")

    if ($Game -eq "OSRS") {
        $lines.Add("- Source : Wise Old Man API")
    } else {
        $lines.Add("- Source : Jagex Clan Members Lite")
    }

    $lines.Add("")
    $lines.Add("| # | Pseudo | Rang | XP | Kills |")
    $lines.Add("|---:|---|---|---:|---:|")

    $index = 0

    foreach ($member in $Members) {
        $index++
        $pseudo = ConvertTo-MarkdownCell -Value $member.Pseudo
        $rank = ConvertTo-MarkdownCell -Value $member.Rang
        $xp = ConvertTo-MarkdownCell -Value $member.XP
        $kills = ConvertTo-MarkdownCell -Value $member.Kills
        $lines.Add("| $index | $pseudo | $rank | $xp | $kills |")
    }

    return $lines.ToArray()
}

function Save-RecoverySnapshot {
    param(
        [object[]]$Members,
        [string]$Game,
        [string]$ClanName,
        [string]$OutputFormat,
        [string]$OutputDir,
        [string]$FileTimestamp
    )

    $resolvedOutputDir = Get-OutputDirectory -OutputDir $OutputDir
    $slug = Get-SafeSlug -Text $ClanName
    $gameSlug = $Game.ToLowerInvariant()

    if ([string]::IsNullOrWhiteSpace($FileTimestamp)) {
        $FileTimestamp = Get-FileTimestamp
    }

    $recoveryPath = Join-Path -Path $resolvedOutputDir -ChildPath "$gameSlug-$slug-members-$FileTimestamp.recovery.json"

    $snapshot = [PSCustomObject]@{
        Version      = 1
        Status       = "search-complete"
        GeneratedAt  = (Get-Date).ToString("o")
        Game         = $Game
        Clan         = $ClanName
        OutputFormat = $OutputFormat
        MemberCount  = $Members.Count
        Members      = $Members
    }

    Write-Info "Recovery snapshot: $recoveryPath"
    $json = $snapshot | ConvertTo-Json -Depth 8
    Write-AtomicTextFileUtf8 -Path $recoveryPath -Content $json -Activity "Recovery snapshot"

    return $recoveryPath
}

function Remove-RecoverySnapshot {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }

    try {
        if ($PSCmdlet.ShouldProcess($Path, "Delete recovery file")) {
            Remove-Item -LiteralPath $Path -Force
        }
    }
    catch {
        Write-Warn2 "Could not delete the recovery file: $Path"
    }
}

function Export-Member {
    param(
        [object[]]$Members,
        [string]$Game,
        [string]$ClanName,
        [string]$OutputFormat,
        [string]$OutputDir,
        [int]$OutputChunkSize,
        [string]$FileTimestamp
    )

    Write-Progress -Activity "File generation" -Status "Preparing output folder" -PercentComplete 10
    $resolvedOutputDir = Get-OutputDirectory -OutputDir $OutputDir

    $slug = Get-SafeSlug -Text $ClanName
    $gameSlug = $Game.ToLowerInvariant()

    if ([string]::IsNullOrWhiteSpace($FileTimestamp)) {
        $FileTimestamp = Get-FileTimestamp
    }

    if ($OutputFormat -eq "Csv") {
        $outputPath = Join-Path -Path $resolvedOutputDir -ChildPath "$gameSlug-$slug-members-$FileTimestamp.csv"
        Write-Info "CSV generation: $outputPath"

        $csvLines = @($Members |
            Select-Object Game, Clan, Pseudo, Rang, XP, Kills |
            ConvertTo-Csv -NoTypeInformation)

        Write-LinesAtomicUtf8 -Path $outputPath -Lines $csvLines -Activity "CSV generation" -ChunkSize $OutputChunkSize
    } else {
        $outputPath = Join-Path -Path $resolvedOutputDir -ChildPath "$gameSlug-$slug-members-$FileTimestamp.md"
        Write-Info "Markdown generation: $outputPath"

        $markdownLines = ConvertTo-MarkdownLine -Members $Members -Game $Game -ClanName $ClanName
        Write-LinesAtomicUtf8 -Path $outputPath -Lines $markdownLines -Activity "Markdown generation" -ChunkSize $OutputChunkSize
    }

    Write-Progress -Activity "File generation" -Completed
    return $outputPath
}

function Show-MemberResult {
    param(
        [object[]]$Members,
        [string]$Game,
        [string]$ClanName,
        [int]$PreviewCount,
        [bool]$ShowAllInConsole
    )

    Write-Console ""
    Write-Console "$(Get-UiMarker -Kind "Search" -Fallback "==") Search result" -ForegroundColor White
    Write-Console "Game    : $Game"
    Write-Console "Clan    : $ClanName"
    Write-Console "Members : $($Members.Count)"
    Write-Console ""

    if ($ShowAllInConsole -or $Members.Count -le $PreviewCount) {
        $visibleMembers = @($Members)
    } else {
        $visibleMembers = @($Members | Select-Object -First $PreviewCount)
        Write-Warn2 "Display limited to the first $PreviewCount members. The generated file contains the full list."
        Write-Console ""
    }

    $index = 0

    $visibleMembers |
        ForEach-Object {
            $index++

            [PSCustomObject]@{
                "#"    = $index
                Pseudo = $_.Pseudo
                Rang   = $_.Rang
                XP     = $_.XP
                Kills  = $_.Kills
            }
        } |
        Format-Table -AutoSize |
        Out-Host
}

function Complete-ProgressActivity {
    Write-Progress -Activity "RS3 search" -Completed
    Write-Progress -Activity "OSRS search" -Completed
    Write-Progress -Activity "Read OSRS members" -Completed
    Write-Progress -Activity "File generation" -Completed
    Write-Progress -Activity "Recovery snapshot" -Completed
    Write-Progress -Activity "CSV generation" -Completed
    Write-Progress -Activity "Markdown generation" -Completed
}

function Show-HelpfulExample {
    Write-Console ""
    Write-Console "Useful examples:" -ForegroundColor Yellow
    Write-Console '  .\Get-RunescapeClanMembers.ps1 -Game RS3 -ClanName "Wapitiklan Empire" -OutputFormat Csv'
    Write-Console '  .\Get-RunescapeClanMembers.ps1 -Game OSRS -ClanName "KnightSlayer" -OutputFormat Csv'
    Write-Console '  .\Get-RunescapeClanMembers.ps1 -Game Both -ClanName "KnightSlayer" -OutputFormat Markdown'
    Write-Console '  .\Get-RunescapeClanMembers.ps1 -Game OSRS -OsrsGroupId 257 -OutputFormat Csv'
    Write-Console ""
    Write-Console "Notes :" -ForegroundColor Yellow
    Write-Console "  - RS3 uses HTTPS by default; the legacy HTTP fallback requires -AllowInsecureFallback."
    Write-Console "  - OSRS depends on Wise Old Man; the group must exist publicly on Wise Old Man."
    Write-Console "  - Increase -TimeoutSec, -MaxRetries, or -MaxRetryDelaySec if the network is unstable."
}

function Get-FriendlySearchFailureMessage {
    param(
        [string]$Game,
        [string]$ClanName,
        [int]$OsrsGroupId
    )

    if ($Game -eq "OSRS" -and $OsrsGroupId -gt 0) {
        return "No readable Wise Old Man OSRS group found for id $OsrsGroupId."
    }

    if ($Game -eq "OSRS") {
        return "No readable Wise Old Man OSRS group found for '$ClanName'."
    }

    return "No readable RS3 clan found for '$ClanName'."
}

function Invoke-GameExport {
    param(
        [string]$Game,
        [string]$ClanName,
        [string]$OutputFormat,
        [string]$OutputDir,
        [int]$OsrsGroupId,
        [int]$TimeoutSec,
        [int]$MaxRetries,
        [int]$OutputChunkSize,
        [int]$PreviewCount,
        [bool]$ShowAllInConsole,
        [bool]$AllowInsecureFallback,
        [bool]$KeepRecoveryFile
    )

    $recoveryPath = $null
    $stage = "search"

    try {
        Write-Console ""

        if ($Game -eq "OSRS" -and $OsrsGroupId -gt 0 -and [string]::IsNullOrWhiteSpace($ClanName)) {
            Write-Info "OSRS search by Wise Old Man ID: $OsrsGroupId"
        } else {
            Write-Info "$Game search: $ClanName"
        }

        if ($Game -eq "OSRS") {
            $members = Get-OsrsClanMember -ClanName $ClanName -OsrsGroupId $OsrsGroupId -TimeoutSec $TimeoutSec -MaxRetries $MaxRetries
        } else {
            $members = Get-Rs3ClanMember -ClanName $ClanName -TimeoutSec $TimeoutSec -MaxRetries $MaxRetries -AllowInsecureFallback $AllowInsecureFallback
        }

        $members = @($members)

        if ($members.Count -eq 0) {
            throw "No member found for $Game."
        }

        $stage = "snapshot"
        $actualClanName = $members[0].Clan
        $fileTimestamp = Get-FileTimestamp
        $recoveryPath = Save-RecoverySnapshot -Members $members -Game $Game -ClanName $actualClanName -OutputFormat $OutputFormat -OutputDir $OutputDir -FileTimestamp $fileTimestamp

        Show-MemberResult -Members $members -Game $Game -ClanName $actualClanName -PreviewCount $PreviewCount -ShowAllInConsole $ShowAllInConsole

        $stage = "generation"
        $outputPath = Export-Member -Members $members -Game $Game -ClanName $actualClanName -OutputFormat $OutputFormat -OutputDir $OutputDir -OutputChunkSize $OutputChunkSize -FileTimestamp $fileTimestamp

        Write-Console ""
        Write-Ok "$Game export complete."
        Write-LocalPath -Label "Generated file ($Game)" -Path $outputPath

        if ($KeepRecoveryFile) {
            Write-LocalPath -Label "Kept recovery file ($Game)" -Path $recoveryPath
        } else {
            Remove-RecoverySnapshot -Path $recoveryPath
            $recoveryPath = $null
        }

        [PSCustomObject]@{
            Game         = $Game
            Success      = $true
            ClanName     = $actualClanName
            MemberCount  = $members.Count
            OutputPath   = $outputPath
            RecoveryPath = $recoveryPath
            Message      = $null
        }
    }
    catch {
        Complete-ProgressActivity

        Write-Console ""
        Write-Warn2 "${Game}: no export generated."

        if ($stage -eq "search") {
            Write-Warn2 (Get-FriendlySearchFailureMessage -Game $Game -ClanName $ClanName -OsrsGroupId $OsrsGroupId)
        } else {
            Write-Warn2 $_.Exception.Message
        }

        if (-not [string]::IsNullOrWhiteSpace($recoveryPath) -and (Test-Path -LiteralPath $recoveryPath -PathType Leaf)) {
            Write-Warn2 "Search already saved here: $recoveryPath"
            $recoveryUri = ConvertTo-FileUri -Path $recoveryPath

            if (-not [string]::IsNullOrWhiteSpace($recoveryUri)) {
                Write-Info "Local link: $recoveryUri"
            }
        }

        [PSCustomObject]@{
            Game         = $Game
            Success      = $false
            ClanName     = $ClanName
            MemberCount  = 0
            OutputPath   = $null
            RecoveryPath = $recoveryPath
            Message      = $_.Exception.Message
        }
    }
}

function Invoke-ExportSequence {
    param(
        [string]$Game,
        [string]$ClanName,
        [string]$OutputFormat,
        [string]$OutputDir,
        [int]$OsrsGroupId,
        [int]$TimeoutSec,
        [int]$MaxRetries,
        [int]$RequestDelaySec,
        [int]$OutputChunkSize,
        [int]$PreviewCount,
        [bool]$ShowAllInConsole,
        [bool]$OpenFolder,
        [bool]$AllowInsecureFallback,
        [bool]$KeepRecoveryFile
    )

    $resolvedOutputDir = Get-OutputDirectory -OutputDir $OutputDir
    $gamesToRun = if ($Game -eq "Both") { @("RS3", "OSRS") } else { @($Game) }

    Write-Console ""

    if ($Game -eq "Both") {
        Write-Info "Selected games: RS3 and OSRS"
    } else {
        Write-Info "Selected game: $Game"
    }

    if ($Game -eq "OSRS" -and $OsrsGroupId -gt 0 -and [string]::IsNullOrWhiteSpace($ClanName)) {
        Write-Info "Search by Wise Old Man ID: $OsrsGroupId"
    } else {
        Write-Info "Clan/group search: $ClanName"
    }

    Write-Info "Output format: $OutputFormat"
    Write-Info "Output folder: $resolvedOutputDir"
    Write-Info "Network mode: sequential calls, minimum delay $RequestDelaySec s, spaced retries, no credentials required."

    $results = foreach ($gameToRun in $gamesToRun) {
        Invoke-GameExport `
            -Game $gameToRun `
            -ClanName $ClanName `
            -OutputFormat $OutputFormat `
            -OutputDir $resolvedOutputDir `
            -OsrsGroupId $OsrsGroupId `
            -TimeoutSec $TimeoutSec `
            -MaxRetries $MaxRetries `
            -OutputChunkSize $OutputChunkSize `
            -PreviewCount $PreviewCount `
            -ShowAllInConsole $ShowAllInConsole `
            -AllowInsecureFallback $AllowInsecureFallback `
            -KeepRecoveryFile $KeepRecoveryFile
    }

    $results = @($results)
    $successfulResults = @($results | Where-Object { $_.Success })
    $failedResults = @($results | Where-Object { -not $_.Success })

    Write-Console ""
    Write-Console "$(Get-UiMarker -Kind "Summary" -Fallback "==") Summary" -ForegroundColor White

    foreach ($result in $successfulResults) {
        Write-Ok "$($result.Game): $($result.MemberCount) member(s) exported for '$($result.ClanName)'."
        Write-LocalPath -Label "$($result.Game) file" -Path $result.OutputPath
    }

    foreach ($result in $failedResults) {
        Write-Warn2 "$($result.Game): no result exported."
    }

    if ($successfulResults.Count -eq 0) {
        Write-Warn2 "No file was generated for this search."
    }

    if ($OpenFolder -and $successfulResults.Count -gt 0) {
        Open-OutputDirectory -Path $resolvedOutputDir | Out-Null
    }

    return [PSCustomObject]@{
        Results    = $results
        HasSuccess = ($successfulResults.Count -gt 0)
    }
}

function Read-PostSequenceAction {
    if (-not (Test-CanPrompt)) {
        return "Close"
    }

    Write-Console ""
    return Read-Choice -Question "What do you want to do now?" -AllowedValues @("Restart", "Close") -Labels @("Run another search", "Close the window")
}

function Assert-SelfTest {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-SelfTestEqual {
    param(
        [object]$Actual,
        [object]$Expected,
        [string]$Message
    )

    if ([string]$Actual -ne [string]$Expected) {
        throw "$Message Expected: '$Expected'. Actual: '$Actual'."
    }
}

function Assert-SelfTestThrows {
    param(
        [scriptblock]$ScriptBlock,
        [string]$Message
    )

    $hasThrown = $false

    try {
        & $ScriptBlock | Out-Null
    }
    catch {
        $hasThrown = $true
    }

    Assert-SelfTest -Condition $hasThrown -Message $Message
}

function Invoke-SelfTestCase {
    param(
        [string]$Name,
        [scriptblock]$ScriptBlock
    )

    try {
        & $ScriptBlock
        Write-Ok "SelfTest : $Name"
        return $true
    }
    catch {
        Write-Fail "SelfTest : $Name - $($_.Exception.Message)"
        return $false
    }
}

function Invoke-SelfTest {
    $previousProgressPreference = $ProgressPreference
    $ProgressPreference = "SilentlyContinue"
    $failed = 0
    $tempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "rs-clan-roster-exporter-selftest-$PID-$(Get-Date -Format 'yyyyMMddHHmmssfff')"

    try {
        [System.IO.Directory]::CreateDirectory($tempRoot) | Out-Null

        if (-not (Invoke-SelfTestCase -Name "version and User-Agent" -ScriptBlock {
            Assert-SelfTest -Condition ($script:ApplicationVersion -match "^\d+\.\d+\.\d+$") -Message "The application version must be SemVer."

            $versionPath = Join-Path -Path (Get-ScriptBaseDirectory) -ChildPath "VERSION"

            if (Test-Path -LiteralPath $versionPath -PathType Leaf) {
                $versionText = (Get-Content -LiteralPath $versionPath -Raw).Trim()
                Assert-SelfTestEqual -Actual $script:ApplicationVersion -Expected $versionText -Message "VERSION must match the script."
            }

            $headers = Get-HttpHeader -Accept "application/json"
            Assert-SelfTest -Condition ([string]$headers["User-Agent"]).Contains("/$script:ApplicationVersion PowerShell/") -Message "The User-Agent must include the application version."
        })) { $failed++ }

        if (-not (Invoke-SelfTestCase -Name "parameter validation" -ScriptBlock {
            Assert-SelfTestEqual -Actual (ConvertTo-Game -Value "1") -Expected "RS3" -Message "The numeric RS3 choice must be accepted."
            Assert-SelfTestEqual -Actual (ConvertTo-OutputFormat -Value "2") -Expected "Csv" -Message "The numeric CSV choice must be accepted."
            Assert-SelfTestThrows -ScriptBlock { ConvertTo-Game -Value "Nope" } -Message "An invalid game must fail."
            Assert-SelfTestThrows -ScriptBlock { ConvertTo-OutputFormat -Value "xlsx" } -Message "An invalid format must fail."
            Assert-SelfTestThrows -ScriptBlock { ConvertTo-ClanName -Value "A" } -Message "A too-short name must fail."
        })) { $failed++ }

        if (-not (Invoke-SelfTestCase -Name "parsing RS3 CSV" -ScriptBlock {
            $csvText = @"
Clanmate,Clan Rank,Total XP,Kills
Alice,Owner,"1,234",7
Bob,Recruit,0,0
"@
            $members = @(ConvertFrom-Rs3ClanMembersCsv -CsvText $csvText -ClanName "Rune Test")
            Assert-SelfTestEqual -Actual $members.Count -Expected 2 -Message "The RS3 fixture must produce two members."
            Assert-SelfTestEqual -Actual $members[0].Game -Expected "RS3" -Message "The RS3 game value must be preserved."
            Assert-SelfTestEqual -Actual $members[0].Pseudo -Expected "Alice" -Message "The RS3 display name must be read."
            Assert-SelfTestEqual -Actual $members[0].XP -Expected "1,234" -Message "The quoted RS3 XP value must be preserved."
        })) { $failed++ }

        if (-not (Invoke-SelfTestCase -Name "parsing OSRS JSON" -ScriptBlock {
            $details = @"
{
  "name": "Knight Test",
  "memberships": [
    { "role": "leader", "player": { "displayName": "Alpha", "username": "alpha", "exp": 123 } },
    { "role": "member", "player": { "displayName": "", "username": "beta", "exp": 456 } },
    { "role": "ignored", "player": null }
  ]
}
"@ | ConvertFrom-Json

            $members = @(ConvertFrom-OsrsGroupDetails -Details $details -GroupId 257)
            Assert-SelfTestEqual -Actual $members.Count -Expected 2 -Message "The OSRS fixture must produce two members."
            Assert-SelfTestEqual -Actual $members[0].Game -Expected "OSRS" -Message "The OSRS game value must be preserved."
            Assert-SelfTestEqual -Actual $members[1].Pseudo -Expected "beta" -Message "The OSRS username must be used as fallback."
            Assert-SelfTestEqual -Actual $members[0].Kills -Expected "" -Message "Kills must remain empty for OSRS."
        })) { $failed++ }

        if (-not (Invoke-SelfTestCase -Name "exports and special paths" -ScriptBlock {
            $outputDir = Join-Path -Path $tempRoot -ChildPath "exports [selftest]"
            $members = @(
                [PSCustomObject]@{
                    Game  = "RS3"
                    Clan  = "Clan Test"
                    Pseudo = "Alice | Bob"
                    Rang  = "Owner"
                    XP    = "123"
                    Kills = "4"
                }
            )

            $csvPath = Export-Member -Members $members -Game "RS3" -ClanName "Clan Test" -OutputFormat "Csv" -OutputDir $outputDir -OutputChunkSize 25 -FileTimestamp "2026-07-09_12-00-00"
            $markdownPath = Export-Member -Members $members -Game "RS3" -ClanName "Clan Test" -OutputFormat "Markdown" -OutputDir $outputDir -OutputChunkSize 25 -FileTimestamp "2026-07-09_12-00-01"

            Assert-SelfTest -Condition (Test-Path -LiteralPath $csvPath -PathType Leaf) -Message "The CSV must be created."
            Assert-SelfTest -Condition (Test-Path -LiteralPath $markdownPath -PathType Leaf) -Message "The Markdown must be created."

            $csvText = Get-Content -LiteralPath $csvPath -Raw
            $markdownText = Get-Content -LiteralPath $markdownPath -Raw

            Assert-SelfTest -Condition ($csvText.Contains('"Pseudo"')) -Message "The CSV must contain the Pseudo header."
            Assert-SelfTest -Condition ($markdownText.Contains("Alice \| Bob")) -Message "Markdown must escape pipes."
            Assert-SelfTest -Condition (Open-OutputDirectory -Path $outputDir -ProbeOnly) -Message "The open-folder helper must accept an existing folder."
        })) { $failed++ }

        if (-not (Invoke-SelfTestCase -Name "classification HTTP" -ScriptBlock {
            Assert-SelfTest -Condition (Test-IsPermanentHttpStatusCode -StatusCode 404) -Message "HTTP 404 must be permanent."
            Assert-SelfTest -Condition (-not (Test-IsPermanentHttpStatusCode -StatusCode 429)) -Message "HTTP 429 must remain retryable."
        })) { $failed++ }
    }
    finally {
        $ProgressPreference = $previousProgressPreference

        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if ($failed -gt 0) {
        Write-Fail "SelfTest completed with $failed failure(s)."
        return $false
    }

    Write-Ok "SelfTest completed without failure."
    return $true
}

Initialize-Console

if ($Version) {
    Write-Console "RuneScape Clan Roster Exporter v$script:ApplicationVersion"
    exit 0
}

if ($SelfTest) {
    if (Invoke-SelfTest) {
        exit 0
    }

    exit 1
}

$currentGame = $Game
$currentClanName = $ClanName
$currentOutputFormat = $OutputFormat
$currentOsrsGroupId = $OsrsGroupId
$exitCode = 0

while ($true) {
    try {
        Write-Console ""
        Write-Console "$(Get-UiMarker -Kind "Export" -Fallback "==") RuneScape / OSRS member export v$script:ApplicationVersion" -ForegroundColor White
        Write-Console ""

        $options = Resolve-InteractiveOption -Game $currentGame -ClanName $currentClanName -OutputFormat $currentOutputFormat -OsrsGroupId $currentOsrsGroupId
        $sequenceResult = Invoke-ExportSequence `
            -Game $options.Game `
            -ClanName $options.ClanName `
            -OutputFormat $options.OutputFormat `
            -OutputDir $OutputDir `
            -OsrsGroupId $currentOsrsGroupId `
            -TimeoutSec $TimeoutSec `
            -MaxRetries $MaxRetries `
            -RequestDelaySec $RequestDelaySec `
            -OutputChunkSize $OutputChunkSize `
            -PreviewCount $PreviewCount `
            -ShowAllInConsole ([bool]$ShowAllInConsole) `
            -OpenFolder ([bool]$OpenFolder) `
            -AllowInsecureFallback ([bool]$AllowInsecureFallback) `
            -KeepRecoveryFile ([bool]$KeepRecoveryFile)

        if (-not $sequenceResult.HasSuccess -and -not (Test-CanPrompt)) {
            $exitCode = 1
        }
    }
    catch {
        Complete-ProgressActivity

        Write-Console ""
        Write-Fail $_.Exception.Message

        Show-HelpfulExample
        $exitCode = 1
    }

    if ((Read-PostSequenceAction) -eq "Restart") {
        $currentGame = $null
        $currentClanName = $null
        $currentOutputFormat = $null
        $currentOsrsGroupId = 0
        $exitCode = 0
        continue
    }

    break
}

exit $exitCode
