[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$source = Join-Path $root 'Get-RunescapeClanMembers.ps1'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$errors)
foreach ($definition in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    . ([scriptblock]::Create($definition.Extent.Text))
}
$script:ApplicationVersion = (Get-Content (Join-Path $root 'VERSION') -Raw).Trim()
$script:ConfiguredPlainUi = $true
$script:ConfiguredRetryBaseDelaySec = 1
$script:ConfiguredMaxRetryDelaySec = 120
$NonInteractive = $true
function Assert-Result { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('roster-integration-' + [guid]::NewGuid())
try {
    [void][IO.Directory]::CreateDirectory($scratch)
    $member = [pscustomobject]@{ Game='RS3'; Clan='Synthetic'; Pseudo='A | B'; Rang='Owner'; XP='123'; Kills='4' }
    $snapshot = Save-RecoverySnapshot -Members @($member) -Game RS3 -ClanName Synthetic -OutputFormat Csv -OutputDir $scratch -FileTimestamp 'fixture'
    $data = Get-Content -LiteralPath $snapshot -Raw | ConvertFrom-Json
    Assert-Result ($data.MemberCount -eq 1 -and $data.Members[0].Pseudo -eq $member.Pseudo) 'Recovery snapshot lost member data.'
    $csv = Export-Member -Members @($member) -Game RS3 -ClanName Synthetic -OutputFormat Csv -OutputDir $scratch -OutputChunkSize 25 -FileTimestamp 'fixture'
    $bytes = [IO.File]::ReadAllBytes($csv)
    Assert-Result ($bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) 'CSV must retain UTF-8 BOM.'
    Assert-Result ((Import-Csv -LiteralPath $csv).Pseudo -eq $member.Pseudo) 'CSV round trip changed member data.'
    Remove-RecoverySnapshot -Path $snapshot
    Assert-Result (-not (Test-Path -LiteralPath $snapshot)) 'Recovery deletion failed.'
    $response = [pscustomobject]@{ Headers=@{'Retry-After'='30'}; StatusCode=429 }
    $errorFixture = [pscustomobject]@{ Exception=[pscustomobject]@{ Response=$response } }
    Assert-Result ((Get-RetryDelaySecond -Attempt 1 -ErrorRecord $errorFixture) -eq 30) 'Retry-After seconds ignored.'
    $response.Headers['Retry-After'] = [DateTime]::UtcNow.AddSeconds(60).ToString('r')
    $delay = Get-RetryAfterSecond -ErrorRecord $errorFixture
    Assert-Result ($delay -ge 58 -and $delay -le 61) 'Retry-After HTTP date ignored.'
    Assert-Result (-not (Test-CanPrompt)) 'NonInteractive must disable prompts.'
    $ambiguous = @([pscustomobject]@{name='Alpha';clanChat='';memberCount=1;id=1}, [pscustomobject]@{name='Beta';clanChat='';memberCount=1;id=2})
    Assert-SelfTestThrows { Select-OsrsGroup -Groups $ambiguous -ClanName 'Unknown' } 'Ambiguous groups must fail without prompting.'
    function Get-Rs3ClanMember { return @($member) }
    function Get-OsrsClanMember { throw 'Synthetic API outage' }
    $result = Invoke-ExportSequence -Game Both -ClanName Synthetic -OutputFormat Csv -OutputDir $scratch -OutputChunkSize 25 -PreviewCount 1
    Assert-Result ($result.HasSuccess -and $result.Results.Count -eq 2 -and -not $result.Results[1].Success) 'Partial results must retain the successful game.'
    function Get-Rs3ClanMember { throw 'Synthetic API outage' }
    $result = Invoke-ExportSequence -Game Both -ClanName Synthetic -OutputFormat Csv -OutputDir $scratch -OutputChunkSize 25 -PreviewCount 1
    Assert-Result (-not $result.HasSuccess) 'Total API failure must report no success.'
    $process = Start-Process -FilePath (Get-Command pwsh).Source -ArgumentList @('-NoProfile','-NonInteractive','-File', ('"' + $source + '"'), '-NonInteractive') -PassThru -Wait -NoNewWindow
    Assert-Result ($process.ExitCode -eq 1) 'Missing parameters must fail with exit code 1.'
    Write-Host 'Offline exporter integrations passed.'
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
