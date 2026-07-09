# User Guide

## Quick Start

Download `Get-RunescapeClanMembers.ps1`, open PowerShell in the script folder, then run:

```powershell
.\Get-RunescapeClanMembers.ps1
```

On Linux or macOS, use PowerShell 7+:

```powershell
pwsh ./Get-RunescapeClanMembers.ps1
```

Interactive mode asks for the target game, the clan or group name, and the output format.

## Examples

Export the RS3 clan Wapitiklan Empire to CSV:

```powershell
.\Get-RunescapeClanMembers.ps1 -Game RS3 -ClanName "Wapitiklan Empire" -OutputFormat Csv
```

Export the same RS3 clan to Markdown:

```powershell
.\Get-RunescapeClanMembers.ps1 -Game RS3 -ClanName "Wapitiklan Empire" -OutputFormat Markdown
```

Export an OSRS group to CSV:

```powershell
.\Get-RunescapeClanMembers.ps1 -Game OSRS -ClanName "KnightSlayer" -OutputFormat Csv
```

## Generated Files

By default, files are written to `output`, next to the script. Generated exports should not be committed to the repository.

## Local Validation

The script can verify its internal safeguards without network calls:

```powershell
pwsh -NoProfile -File ./Get-RunescapeClanMembers.ps1 -SelfTest
```

From the repository, the full validation command can also run a real OSRS network smoke test when requested:

```powershell
pwsh -NoProfile -File ./scripts/Test-Local.ps1 -NetworkSmoke
```

## PowerShell Blocks The Script

If PowerShell refuses to run the local script, launch this command for that run only:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-RunescapeClanMembers.ps1
```

## Limits

- RS3 depends on the public Jagex Clan Members Lite endpoint.
- OSRS depends on Wise Old Man.
- `-OpenFolder` tries to open the output folder through the local system association; if that is not possible, the printed path remains usable.
- The project does not replace human review before publishing or sharing a roster.
