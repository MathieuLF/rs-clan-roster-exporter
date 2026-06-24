<#
.SYNOPSIS
  Exporte les membres d'un clan RuneScape 3 ou d'un groupe OSRS.

.DESCRIPTION
  Le script peut fonctionner en mode interactif ou avec paramètres.

  RS3 utilise l'endpoint public Jagex Clan Members Lite.
  OSRS utilise l'API publique Wise Old Man, car OSRS n'expose pas le même CSV
  public Jagex pour les clans.

  Formats de sortie disponibles :
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
  Compatible Windows PowerShell 5.1+ et PowerShell 7+.
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
    [switch]$Version
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$script:ApplicationVersion = "0.1.0"
$script:LastHttpRequestAt = $null
$script:ConfiguredRetryBaseDelaySec = $RetryBaseDelaySec
$script:ConfiguredMaxRetryDelaySec = $MaxRetryDelaySec
$script:ConfiguredRepositoryUrl = $RepositoryUrl

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
        Write-Verbose "Impossible d'ajuster l'encodage de la console : $($_.Exception.Message)"
    }

    if ($env:OS -eq "Windows_NT" -and -not [Console]::IsOutputRedirected) {
        try {
            cmd.exe /c "chcp 65001 >nul" | Out-Null
        } catch {
            Write-Verbose "Impossible de changer la page de code console : $($_.Exception.Message)"
        }
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    } catch {
        Write-Verbose "Impossible de forcer TLS 1.2 dans cet hôte : $($_.Exception.Message)"
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
        Write-Verbose "Écriture via l'hôte PowerShell impossible : $($_.Exception.Message)"
        Write-Information -MessageData $Message -InformationAction Continue
    }
}

function Write-Info {
    param([string]$Message)
    Write-Console "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Console "[OK]   $Message" -ForegroundColor Green
}

function Write-Warn2 {
    param([string]$Message)
    Write-Console "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Console "[FAIL] $Message" -ForegroundColor Red
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
    Write-Ok "$Label : $fullPath"

    $fileUri = ConvertTo-FileUri -Path $fullPath

    if (-not [string]::IsNullOrWhiteSpace($fileUri)) {
        Write-Info "Lien local : $fileUri"
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

    throw "Jeu invalide : '$Value'. Valeurs acceptées : RS3, OSRS ou Both."
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

    throw "Format invalide : '$Value'. Valeurs acceptées : Markdown ou CSV."
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
        throw "Le nom du clan doit contenir au moins 2 caractères."
    }

    if ($clean.Length -gt 100) {
        throw "Le nom du clan est trop long. Limite : 100 caractères."
    }

    if ($clean -match "[\x00-\x1F]") {
        throw "Le nom du clan contient un caractère de contrôle invalide."
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
        throw "Aucun choix disponible pour la question : $Question"
    }

    if ($null -ne $Labels -and $Labels.Count -ne $AllowedValues.Count) {
        throw "La liste des libellés doit contenir autant d'éléments que la liste des choix."
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

        $answer = Read-Host "Ton choix ($range)"

        $choice = 0

        if ([int]::TryParse($answer, [ref]$choice) -and $choice -ge 1 -and $choice -le $AllowedValues.Count) {
            return $AllowedValues[$choice - 1]
        }

        Write-Warn2 "Réponse attendue : un chiffre entre 1 et $($AllowedValues.Count)."
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
            throw "Le paramètre -Game est requis en mode non interactif. Valeurs : RS3, OSRS ou Both."
        }

        Write-Console ""
        $resolvedGame = Read-Choice -Question "Jeu cible" -AllowedValues @("RS3", "OSRS", "Both") -Labels @("RS3 : clan RuneScape 3 via Jagex", "OSRS : groupe OSRS via Wise Old Man", "Les deux : rechercher dans RS3 et OSRS")
    }

    if ([string]::IsNullOrWhiteSpace($resolvedClan) -and -not ($resolvedGame -eq "OSRS" -and $OsrsGroupId -gt 0)) {
        if (-not (Test-CanPrompt)) {
            throw "Le paramètre -ClanName est requis en mode non interactif."
        }

        if ($resolvedGame -eq "OSRS") {
            $resolvedClan = Read-RequiredText -Question "Nom du groupe/clan OSRS à rechercher"
        } elseif ($resolvedGame -eq "Both") {
            $resolvedClan = Read-RequiredText -Question "Nom du clan/groupe à rechercher dans RS3 et OSRS"
        } else {
            $resolvedClan = Read-RequiredText -Question "Nom du clan RS3 à rechercher"
        }
    }

    if ([string]::IsNullOrWhiteSpace($resolvedFormat)) {
        if (-not (Test-CanPrompt)) {
            throw "Le paramètre -OutputFormat est requis en mode non interactif. Valeurs : Markdown ou CSV."
        }

        $resolvedFormat = Read-Choice -Question "Format de sortie" -AllowedValues @("Markdown", "Csv") -Labels @("Markdown (.md)", "CSV (.csv)")
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

    $userAgent = "RunescapeClanMembersExporter/1.1 PowerShell/$($PSVersionTable.PSVersion)"

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

    Write-Info "Pause réseau douce de $remaining seconde(s) avant le prochain appel."

    for ($i = $remaining; $i -gt 0; $i--) {
        Write-Progress -Activity $Purpose -Status "Pause réseau respectueuse ($i s)" -SecondsRemaining $i -PercentComplete 5
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

    Write-Info "Pause $Seconds seconde(s), puis nouvelle tentative."

    for ($remaining = $Seconds; $remaining -gt 0; $remaining--) {
        Write-Progress -Activity $Purpose -Status "Nouvelle tentative dans $remaining s" -SecondsRemaining $remaining -PercentComplete 10

        if ($remaining -le 3 -or $remaining % 10 -eq 0) {
            Write-Info "Reprise dans $remaining seconde(s)..."
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
            Write-Progress -Activity $Purpose -Status "Tentative $attempt/$MaxRetries" -PercentComplete $percent
            Wait-RequestPace -MinimumDelaySec $RequestDelaySec -Purpose $Purpose
            Write-Info "Tentative $attempt/$MaxRetries : $Url"

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
                throw "Réponse vide."
            }

            Write-Progress -Activity $Purpose -Completed
            return [string]$response.Content
        }
        catch {
            $script:LastHttpRequestAt = Get-Date
            $lastMessage = $_.Exception.Message
            $statusCode = Get-HttpStatusCode -ErrorRecord $_

            if ($null -ne $statusCode) {
                Write-Warn2 "Échec tentative $attempt (HTTP $statusCode) : $lastMessage"
            } else {
                Write-Warn2 "Échec tentative $attempt : $lastMessage"
            }

            if ($attempt -lt $MaxRetries) {
                $sleepSeconds = Get-RetryDelaySecond -Attempt $attempt -ErrorRecord $_
                Wait-RetryDelay -Seconds $sleepSeconds -Purpose $Purpose
            }
        }
    }

    Write-Progress -Activity $Purpose -Completed
    throw "Toutes les tentatives ont échoué. Dernière erreur : $lastMessage"
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
        throw "La réponse JSON n'a pas pu être lue. Détail : $($_.Exception.Message). Réponse reçue : $(Get-ResponseSample -Text $content)"
    }
}

function ConvertTo-ClanValue {
    param([object]$Value)

    if ($null -eq $Value) {
        return ""
    }

    return ([string]$Value).Replace([char]0x00A0, " ").Replace([char]0x202F, " ").Trim()
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
        throw "Le CSV retourné est vide."
    }

    if ($trimmed -match "^\s*(<!doctype|<html|<\?xml)" -or $trimmed -match "(?i)\b(access denied|temporarily unavailable)\b") {
        throw "Jagex a retourné une page d'erreur au lieu du CSV. Réponse reçue : $(Get-ResponseSample -Text $trimmed)"
    }

    $firstLine = ($trimmed -replace "^\uFEFF", "") -split "\r?\n" |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace($firstLine) -or $firstLine -notmatch ",") {
        throw "La réponse ne ressemble pas à un CSV. Réponse reçue : $(Get-ResponseSample -Text $trimmed)"
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
        throw "Le CSV retourné n'a pas pu être lu. Détail : $($_.Exception.Message). Réponse reçue : $(Get-ResponseSample -Text $trimmed)"
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
        throw "Aucun membre n'a pu être lu dans le CSV."
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
        Write-Warn2 "Fallback HTTP activé explicitement. Préfère HTTPS quand c'est possible."
        $urls += "http://services.runescape.com/m=clan-hiscores/members_lite.ws?clanName=$encodedClan"
    }

    $lastMessage = $null

    foreach ($url in $urls) {
        try {
            $csvText = Invoke-HttpText -Url $url -Accept "text/csv,text/plain,*/*" -TimeoutSec $TimeoutSec -MaxRetries $MaxRetries -Purpose "Recherche RS3"
            return ConvertFrom-Rs3ClanMembersCsv -CsvText $csvText -ClanName $ClanName
        }
        catch {
            $lastMessage = $_.Exception.Message
            Write-Warn2 "Endpoint non concluant : $url"
        }
    }

    throw "Impossible de récupérer les membres RS3 pour '$ClanName'. Dernière erreur : $lastMessage"
}

function Select-OsrsGroup {
    param(
        [object[]]$Groups,
        [string]$ClanName
    )

    $groups = @($Groups | Where-Object { $null -ne $_ })

    if ($groups.Count -eq 0) {
        throw "Aucun groupe OSRS Wise Old Man ne correspond à '$ClanName'."
    }

    $exact = @($groups | Where-Object {
        ($null -ne $_.name -and $_.name -ieq $ClanName) -or
        ($null -ne $_.clanChat -and $_.clanChat -ieq $ClanName)
    })

    if ($exact.Count -eq 1) {
        return $exact[0]
    }

    if ($groups.Count -eq 1) {
        Write-Warn2 "Aucun nom exact trouvé. Sélection du seul résultat disponible : $($groups[0].name)."
        return $groups[0]
    }

    Write-Warn2 "Plusieurs groupes OSRS correspondent à ta recherche."
    Write-Console ""

    for ($i = 0; $i -lt $groups.Count; $i++) {
        $group = $groups[$i]
        $chat = ""

        if ($null -ne $group.clanChat -and -not [string]::IsNullOrWhiteSpace([string]$group.clanChat)) {
            $chat = " | clan chat: $($group.clanChat)"
        }

        Write-Console ("  {0}) {1} ({2} membres{3}, id {4})" -f ($i + 1), $group.name, $group.memberCount, $chat, $group.id)
    }

    if (-not (Test-CanPrompt)) {
        throw "Plusieurs groupes OSRS correspondent. Relance avec un nom plus précis ou avec -OsrsGroupId."
    }

    while ($true) {
        $answer = Read-Host "Choisis le groupe OSRS à utiliser [1-$($groups.Count)]"
        $choice = 0

        if ([int]::TryParse($answer, [ref]$choice) -and $choice -ge 1 -and $choice -le $groups.Count) {
            return $groups[$choice - 1]
        }

        Write-Warn2 "Réponse attendue : un chiffre entre 1 et $($groups.Count)."
    }
}

function Get-OsrsClanMember {
    param(
        [string]$ClanName,
        [int]$OsrsGroupId,
        [int]$TimeoutSec,
        [int]$MaxRetries
    )

    Write-Warn2 "OSRS : recherche via Wise Old Man. Les données viennent d'un groupe public WOM, pas d'un CSV Jagex officiel."

    $selectedGroup = $null

    if ($OsrsGroupId -gt 0) {
        $selectedGroup = [PSCustomObject]@{
            id   = $OsrsGroupId
            name = "Wise Old Man group $OsrsGroupId"
        }
    } else {
        $encodedName = [uri]::EscapeDataString($ClanName)
        $searchUrl = "https://api.wiseoldman.net/v2/groups?name=$encodedName&limit=10"
        $groups = @(Invoke-HttpJson -Url $searchUrl -TimeoutSec $TimeoutSec -MaxRetries $MaxRetries -Purpose "Recherche OSRS")
        $selectedGroup = Select-OsrsGroup -Groups $groups -ClanName $ClanName
    }

    Write-Info "Groupe OSRS sélectionné : $($selectedGroup.name) (id $($selectedGroup.id))"

    $detailsUrl = "https://api.wiseoldman.net/v2/groups/$($selectedGroup.id)"
    $details = Invoke-HttpJson -Url $detailsUrl -TimeoutSec $TimeoutSec -MaxRetries $MaxRetries -Purpose "Lecture des membres OSRS"

    if ($null -eq $details -or $null -eq $details.memberships) {
        throw "Wise Old Man n'a pas retourné de liste de membres pour le groupe id $($selectedGroup.id)."
    }

    $members = foreach ($membership in @($details.memberships)) {
        if ($null -eq $membership.player) {
            continue
        }

        $pseudo = ConvertTo-ClanValue -Value $membership.player.displayName

        if ([string]::IsNullOrWhiteSpace($pseudo)) {
            $pseudo = ConvertTo-ClanValue -Value $membership.player.username
        }

        if ([string]::IsNullOrWhiteSpace($pseudo)) {
            continue
        }

        [PSCustomObject]@{
            Game  = "OSRS"
            Clan  = ConvertTo-ClanValue -Value $details.name
            Pseudo = $pseudo
            Rang  = ConvertTo-ClanValue -Value $membership.role
            XP    = ConvertTo-ClanValue -Value $membership.player.exp
            Kills = ""
        }
    }

    $members = @($members)

    if ($members.Count -eq 0) {
        throw "Aucun membre OSRS lisible n'a été trouvé pour le groupe '$($details.name)'."
    }

    return $members
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
        throw "Le chemin de sortie existe déjà comme fichier : $fullPath"
    }

    if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
        New-Item -Path $fullPath -ItemType Directory | Out-Null
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
        [string]$Activity = "Écriture du fichier"
    )

    $directory = Split-Path -Path $Path -Parent

    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -Path $directory -ItemType Directory | Out-Null
    }

    $tempPath = "$Path.tmp-$PID-$(Get-Date -Format 'yyyyMMddHHmmssfff')"
    $encoding = Get-Utf8BomEncoding
    $writer = $null

    try {
        Write-Progress -Activity $Activity -Status "Écriture temporaire" -PercentComplete 40
        $writer = New-Object System.IO.StreamWriter($tempPath, $false, $encoding)
        $writer.Write($Content)
        $writer.Flush()
    }
    catch {
        Write-Warn2 "Écriture interrompue. Fichier temporaire conservé si présent : $tempPath"
        throw
    }
    finally {
        if ($null -ne $writer) {
            $writer.Dispose()
        }
    }

    Write-Progress -Activity $Activity -Status "Finalisation atomique" -PercentComplete 90
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

    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -Path $directory -ItemType Directory | Out-Null
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
                Write-Progress -Activity $Activity -Status "Écriture $($i + 1)/$($lineList.Count) ligne(s)" -PercentComplete $percent
                Write-Info "Écriture $($i + 1)/$($lineList.Count) ligne(s)..."
            }
        }

        $writer.Flush()
    }
    catch {
        Write-Warn2 "Écriture interrompue. Fichier temporaire conservé si présent : $tempPath"
        throw
    }
    finally {
        if ($null -ne $writer) {
            $writer.Dispose()
        }
    }

    Write-Progress -Activity $Activity -Status "Finalisation atomique" -PercentComplete 98
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

    $lines.Add("# Membres du clan $ClanName")
    $lines.Add("")
    $lines.Add("- Jeu : $Game")
    $lines.Add("- Membres : $($Members.Count)")
    $lines.Add("- Généré le : $generatedAt")

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

    Write-Info "Sauvegarde de récupération : $recoveryPath"
    $json = $snapshot | ConvertTo-Json -Depth 8
    Write-AtomicTextFileUtf8 -Path $recoveryPath -Content $json -Activity "Sauvegarde de récupération"

    return $recoveryPath
}

function Remove-RecoverySnapshot {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }

    try {
        if ($PSCmdlet.ShouldProcess($Path, "Supprimer le fichier de récupération")) {
            Remove-Item -LiteralPath $Path -Force
        }
    }
    catch {
        Write-Warn2 "Impossible de supprimer le fichier de récupération : $Path"
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

    Write-Progress -Activity "Génération du fichier" -Status "Préparation du dossier de sortie" -PercentComplete 10
    $resolvedOutputDir = Get-OutputDirectory -OutputDir $OutputDir

    $slug = Get-SafeSlug -Text $ClanName
    $gameSlug = $Game.ToLowerInvariant()

    if ([string]::IsNullOrWhiteSpace($FileTimestamp)) {
        $FileTimestamp = Get-FileTimestamp
    }

    if ($OutputFormat -eq "Csv") {
        $outputPath = Join-Path -Path $resolvedOutputDir -ChildPath "$gameSlug-$slug-members-$FileTimestamp.csv"
        Write-Info "Génération CSV : $outputPath"

        $csvLines = @($Members |
            Select-Object Game, Clan, Pseudo, Rang, XP, Kills |
            ConvertTo-Csv -NoTypeInformation)

        Write-LinesAtomicUtf8 -Path $outputPath -Lines $csvLines -Activity "Génération CSV" -ChunkSize $OutputChunkSize
    } else {
        $outputPath = Join-Path -Path $resolvedOutputDir -ChildPath "$gameSlug-$slug-members-$FileTimestamp.md"
        Write-Info "Génération Markdown : $outputPath"

        $markdownLines = ConvertTo-MarkdownLine -Members $Members -Game $Game -ClanName $ClanName
        Write-LinesAtomicUtf8 -Path $outputPath -Lines $markdownLines -Activity "Génération Markdown" -ChunkSize $OutputChunkSize
    }

    Write-Progress -Activity "Génération du fichier" -Completed
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
    Write-Console "Résultat de la recherche" -ForegroundColor White
    Write-Console "Jeu     : $Game"
    Write-Console "Clan    : $ClanName"
    Write-Console "Membres : $($Members.Count)"
    Write-Console ""

    if ($ShowAllInConsole -or $Members.Count -le $PreviewCount) {
        $visibleMembers = @($Members)
    } else {
        $visibleMembers = @($Members | Select-Object -First $PreviewCount)
        Write-Warn2 "Affichage limité aux $PreviewCount premiers membres. Le fichier généré contient la liste complète."
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
    Write-Progress -Activity "Recherche RS3" -Completed
    Write-Progress -Activity "Recherche OSRS" -Completed
    Write-Progress -Activity "Lecture des membres OSRS" -Completed
    Write-Progress -Activity "Génération du fichier" -Completed
    Write-Progress -Activity "Sauvegarde de récupération" -Completed
    Write-Progress -Activity "Génération CSV" -Completed
    Write-Progress -Activity "Génération Markdown" -Completed
}

function Show-HelpfulExample {
    Write-Console ""
    Write-Console "Exemples utiles :" -ForegroundColor Yellow
    Write-Console '  .\Get-RunescapeClanMembers.ps1 -Game RS3 -ClanName "Wapitiklan Empire" -OutputFormat Csv'
    Write-Console '  .\Get-RunescapeClanMembers.ps1 -Game OSRS -ClanName "KnightSlayer" -OutputFormat Csv'
    Write-Console '  .\Get-RunescapeClanMembers.ps1 -Game Both -ClanName "KnightSlayer" -OutputFormat Markdown'
    Write-Console '  .\Get-RunescapeClanMembers.ps1 -Game OSRS -OsrsGroupId 257 -OutputFormat Csv'
    Write-Console ""
    Write-Console "Notes :" -ForegroundColor Yellow
    Write-Console "  - RS3 utilise HTTPS par défaut; l'ancien fallback HTTP demande -AllowInsecureFallback."
    Write-Console "  - OSRS dépend de Wise Old Man; le groupe doit exister publiquement sur Wise Old Man."
    Write-Console "  - Tu peux augmenter -TimeoutSec, -MaxRetries ou -MaxRetryDelaySec si le réseau est instable."
}

function Get-FriendlySearchFailureMessage {
    param(
        [string]$Game,
        [string]$ClanName,
        [int]$OsrsGroupId
    )

    if ($Game -eq "OSRS" -and $OsrsGroupId -gt 0) {
        return "Aucun groupe OSRS Wise Old Man trouvé ou lisible pour l'identifiant $OsrsGroupId."
    }

    if ($Game -eq "OSRS") {
        return "Aucun groupe OSRS Wise Old Man trouvé ou lisible pour '$ClanName'."
    }

    return "Aucun clan RS3 trouvé ou lisible pour '$ClanName'."
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
    $stage = "recherche"

    try {
        Write-Console ""

        if ($Game -eq "OSRS" -and $OsrsGroupId -gt 0 -and [string]::IsNullOrWhiteSpace($ClanName)) {
            Write-Info "Recherche OSRS par identifiant Wise Old Man : $OsrsGroupId"
        } else {
            Write-Info "Recherche $Game : $ClanName"
        }

        if ($Game -eq "OSRS") {
            $members = Get-OsrsClanMember -ClanName $ClanName -OsrsGroupId $OsrsGroupId -TimeoutSec $TimeoutSec -MaxRetries $MaxRetries
        } else {
            $members = Get-Rs3ClanMember -ClanName $ClanName -TimeoutSec $TimeoutSec -MaxRetries $MaxRetries -AllowInsecureFallback $AllowInsecureFallback
        }

        $members = @($members)

        if ($members.Count -eq 0) {
            throw "Aucun membre trouvé pour $Game."
        }

        $stage = "sauvegarde"
        $actualClanName = $members[0].Clan
        $fileTimestamp = Get-FileTimestamp
        $recoveryPath = Save-RecoverySnapshot -Members $members -Game $Game -ClanName $actualClanName -OutputFormat $OutputFormat -OutputDir $OutputDir -FileTimestamp $fileTimestamp

        Show-MemberResult -Members $members -Game $Game -ClanName $actualClanName -PreviewCount $PreviewCount -ShowAllInConsole $ShowAllInConsole

        $stage = "génération"
        $outputPath = Export-Member -Members $members -Game $Game -ClanName $actualClanName -OutputFormat $OutputFormat -OutputDir $OutputDir -OutputChunkSize $OutputChunkSize -FileTimestamp $fileTimestamp

        Write-Console ""
        Write-Ok "Export $Game terminé."
        Write-LocalPath -Label "Fichier généré ($Game)" -Path $outputPath

        if ($KeepRecoveryFile) {
            Write-LocalPath -Label "Fichier de récupération conservé ($Game)" -Path $recoveryPath
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
        Write-Warn2 "$Game : aucun export généré."

        if ($stage -eq "recherche") {
            Write-Warn2 (Get-FriendlySearchFailureMessage -Game $Game -ClanName $ClanName -OsrsGroupId $OsrsGroupId)
        } else {
            Write-Warn2 $_.Exception.Message
        }

        if (-not [string]::IsNullOrWhiteSpace($recoveryPath) -and (Test-Path -LiteralPath $recoveryPath -PathType Leaf)) {
            Write-Warn2 "Recherche déjà sauvegardée ici : $recoveryPath"
            $recoveryUri = ConvertTo-FileUri -Path $recoveryPath

            if (-not [string]::IsNullOrWhiteSpace($recoveryUri)) {
                Write-Info "Lien local : $recoveryUri"
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
        Write-Info "Jeux sélectionnés : RS3 et OSRS"
    } else {
        Write-Info "Jeu sélectionné : $Game"
    }

    if ($Game -eq "OSRS" -and $OsrsGroupId -gt 0 -and [string]::IsNullOrWhiteSpace($ClanName)) {
        Write-Info "Recherche par identifiant Wise Old Man : $OsrsGroupId"
    } else {
        Write-Info "Recherche du clan/groupe : $ClanName"
    }

    Write-Info "Format de sortie : $OutputFormat"
    Write-Info "Dossier de sortie : $resolvedOutputDir"
    Write-Info "Mode réseau : appels séquentiels, délai minimum $RequestDelaySec s, retries espacés, aucun identifiant requis."

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
    Write-Console "Résumé" -ForegroundColor White

    foreach ($result in $successfulResults) {
        Write-Ok "$($result.Game) : $($result.MemberCount) membre(s) exporté(s) pour '$($result.ClanName)'."
        Write-LocalPath -Label "Fichier $($result.Game)" -Path $result.OutputPath
    }

    foreach ($result in $failedResults) {
        Write-Warn2 "$($result.Game) : aucun résultat exporté."
    }

    if ($successfulResults.Count -eq 0) {
        Write-Warn2 "Aucun fichier n'a été généré pour cette recherche."
    }

    if ($OpenFolder -and $successfulResults.Count -gt 0) {
        Start-Process -FilePath explorer.exe -ArgumentList @($resolvedOutputDir)
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
    return Read-Choice -Question "Que veux-tu faire maintenant ?" -AllowedValues @("Restart", "Close") -Labels @("Relancer une recherche", "Fermer la fenêtre")
}

Initialize-Console

if ($Version) {
    Write-Console "RuneScape Clan Roster Exporter v$script:ApplicationVersion"
    exit 0
}

$currentGame = $Game
$currentClanName = $ClanName
$currentOutputFormat = $OutputFormat
$currentOsrsGroupId = $OsrsGroupId
$exitCode = 0

while ($true) {
    try {
        Write-Console ""
        Write-Console "Export de membres RuneScape / OSRS v$script:ApplicationVersion" -ForegroundColor White
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
