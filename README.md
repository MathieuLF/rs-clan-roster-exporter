# RuneScape Clan Roster Exporter

![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE)
![Output Markdown or CSV](https://img.shields.io/badge/Output-Markdown%20%7C%20CSV-2ea44f)
![License MIT](https://img.shields.io/badge/License-MIT-blue)
[![Release](https://img.shields.io/github/v/release/MathieuLF/rs-clan-roster-exporter?label=Release)](https://github.com/MathieuLF/rs-clan-roster-exporter/releases)
[![Sponsor](https://img.shields.io/badge/Sponsor-GitHub-ea4aaa)](https://github.com/sponsors/MathieuLF)

Local PowerShell exporter for RuneScape 3 clan members and OSRS group members. It fetches public roster data and writes Markdown or CSV files that are ready to archive, review, or share.

Everything runs through `Get-RunescapeClanMembers.ps1`, either interactively or with PowerShell parameters.

Official versions: [GitHub Releases](https://github.com/MathieuLF/rs-clan-roster-exporter/releases).

This public repository documents the local exporter and its GitHub releases. It does not describe or assert the status of any separately hosted service.

## Lifecycle

The exporter is a local, release-based utility. A GitHub release identifies a downloadable version; it does not imply that Jagex, Wise Old Man or a separately hosted presentation is available.

## Highlights

- RS3 export through the public Jagex Clan Members Lite endpoint.
- OSRS export through the public Wise Old Man API.
- Simple interactive menu with numbered choices: RS3, OSRS, or both.
- Automation-friendly PowerShell parameters.
- Compatible with Windows PowerShell 5.1 on Windows and PowerShell 7+ on Windows, Linux, and macOS.
- Markdown and CSV outputs in UTF-8 with BOM, suitable for Excel, GitHub, and PowerShell.
- `output` folder created next to the script, regardless of the current PowerShell working directory.
- Console preview, progress display, network retries, and local recovery files.
- Clear end flow: run another lookup or close the window.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+ on Windows.
- PowerShell 7+ on Linux or macOS.
- Internet access to reach the public RS3 or Wise Old Man endpoints.
- A PowerShell terminal. The examples below assume you are in the project folder.

## Quick Start

From the script folder:

```powershell
.\Get-RunescapeClanMembers.ps1
```

On Linux or macOS with PowerShell 7+:

```powershell
pwsh ./Get-RunescapeClanMembers.ps1
```

Show the script version:

```powershell
.\Get-RunescapeClanMembers.ps1 -Version
```

Interactive mode asks three questions:

1. Target game: `1` for RS3, `2` for OSRS, `3` for RS3 + OSRS
2. Clan or group name
3. Output format: `1` for Markdown, `2` for CSV

At the end, the script prints the full path of every generated file and a local `file:///...` link when the terminal can render it as clickable. It then asks whether to run another lookup or close the window.

## Examples

Export an RS3 clan to CSV:

```powershell
.\Get-RunescapeClanMembers.ps1 -Game RS3 -ClanName "Wapitiklan Empire" -OutputFormat Csv
```

Export an RS3 clan to Markdown:

```powershell
.\Get-RunescapeClanMembers.ps1 -Game RS3 -ClanName "Wapitiklan Empire" -OutputFormat Markdown
```

Export an OSRS group by name, for example KnightSlayer:

```powershell
.\Get-RunescapeClanMembers.ps1 -Game OSRS -ClanName "KnightSlayer" -OutputFormat Csv
```

Search the same name in RS3 and OSRS:

```powershell
.\Get-RunescapeClanMembers.ps1 -Game Both -ClanName "KnightSlayer" -OutputFormat Markdown
```

Export an OSRS group by Wise Old Man ID:

```powershell
.\Get-RunescapeClanMembers.ps1 -Game OSRS -OsrsGroupId 257 -OutputFormat Csv
```

Use more patient retries when a remote service is slow:

```powershell
.\Get-RunescapeClanMembers.ps1 -Game RS3 -ClanName "Wapitiklan Empire" -OutputFormat Csv -TimeoutSec 120 -MaxRetries 6 -RetryBaseDelaySec 15 -MaxRetryDelaySec 180
```

## Output Folder

By default, exports are written to:

```text
<script-folder>\output
```

Relative output paths are always resolved from the script folder, not from the current PowerShell working directory. Even when the script is launched from somewhere else, `.\output` stays next to `Get-RunescapeClanMembers.ps1`.

Change the output folder:

```powershell
.\Get-RunescapeClanMembers.ps1 -Game RS3 -ClanName "Wapitiklan Empire" -OutputFormat Csv -OutputDir ".\exports"
```

In this example, `.\exports` is also created next to the script. Absolute paths are used as provided.

## Generated Files

The file name includes the game, clan or group, selected format, and a full timestamp:

```text
rs3-clan-name-members-2026-06-24_13-05-42.csv
rs3-clan-name-members-2026-06-24_13-05-42.md
osrs-group-name-members-2026-06-24_13-05-42.csv
osrs-group-name-members-2026-06-24_13-05-42.md
```

The timestamp format is `yyyy-MM-dd_HH-mm-ss` in local time. Recovery files use the same timestamp as the matching export.

Main columns:

| Column | Description |
| --- | --- |
| `Game` | `RS3` or `OSRS` |
| `Clan` | Exported clan or group name |
| `Pseudo` | Member display name |
| `Rang` | Rank returned by the source |
| `XP` | XP returned by the source |
| `Kills` | RS3 value when available |

For OSRS, `Kills` stays empty because Wise Old Man does not provide that value in the group member list.

## Useful Parameters

| Parameter | Purpose |
| --- | --- |
| `-Game RS3`, `-Game OSRS`, or `-Game Both` | Selects the source to export |
| `-ClanName "Name"` | Searches a clan or group by name |
| `-OsrsGroupId 257` | Targets a Wise Old Man group directly |
| `-OutputFormat Markdown` or `-OutputFormat Csv` | Selects the generated format |
| `-OutputDir ".\output"` | Sets the output folder |
| `-PreviewCount 50` | Controls how many members are shown in the console preview |
| `-ShowAllInConsole` | Shows all members in the console |
| `-OpenFolder` | Opens the output folder at the end |
| `-TimeoutSec 120` | Increases the maximum duration of a network call |
| `-MaxRetries 6` | Increases the retry count |
| `-RequestDelaySec 2` | Sets the minimum delay between HTTP calls |
| `-KeepRecoveryFile` | Keeps the local recovery file |
| `-RepositoryUrl "https://github.com/..."` | Adds the repository URL to the User-Agent |
| `-SelfTest` | Runs local internal tests without network calls |
| `-NonInteractive` | Disables prompts and fails when required parameters are missing |

## Partial Results And Errors

If you request RS3 + OSRS and the clan is found only on one side, the matching file is generated and the other source is reported as not exported. If nothing is found, no file is generated and the summary states that clearly.

If member retrieval already succeeded before an export generation error, a `*.recovery.json` file can be kept to avoid losing the fetched data.

Final files are written atomically: a complete file replaces the old one only after generation finishes. A temporary `.tmp-*` file can remain if execution is interrupted at the wrong moment.

## PowerShell Blocks The Script

Depending on the Windows configuration, PowerShell may refuse to run a local script. In that case, use:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-RunescapeClanMembers.ps1
```

This command changes the execution policy only for that run.

## Security And Service Use

- Public sources only: Jagex Clan Members Lite for RS3 and Wise Old Man for OSRS.
- No RuneScape account required.
- Explicit User-Agent.
- HTTPS by default for RS3.
- RS3 HTTP fallback available only with `-AllowInsecureFallback`.
- Sequential network calls with progressive backoff and `Retry-After` support.
- Generated exports (`output/`, `exports/`, recovery files, and temporary files) ignored by Git.

## Notes

- RS3 depends on the availability of the public Jagex endpoint.
- OSRS depends on Wise Old Man; the group must exist publicly on Wise Old Man.
- If several OSRS groups match a search, the script asks you to select one by number.
- In RS3 + OSRS mode, each source is handled separately: an OSRS failure does not block the RS3 export, and the reverse is also true.
- Text parameters remain available for automation, even though interactive mode favors numbered choices.
- The `file:///...` link is a convenience; whether it is clickable depends on the terminal.
- `-OpenFolder` tries to open the output folder through the local system association. If the environment cannot do that, the path remains visible and the export does not fail.

## Local Validation

Contributor commands require a Git clone. The portable ZIP contains the
standalone exporter and documentation; its `-SelfTest` works without contributor tools.

### Reproducible setup and architecture

The root script handles input, HTTP/retries, parsing, recovery and exports.
`scripts/` contains contributor tooling; `tests/` contains synthetic fixtures.
`docs/` is a static site with a client-side GitHub release card. There is no
database, migration, application package manager, local service or required secret.

On Ubuntu 24.04 x86_64, with Git, Python 3, curl, tar, xz, CA certificates and the
standard PowerShell runtime libraries (including ICU, OpenSSL and zlib):

```bash
bash scripts/setup-cloud.sh
export PATH="$HOME/.local/bin:$PATH"
pwsh -NoProfile -File scripts/Test-Local.ps1 -Profile Dev
```

Setup installs PowerShell 7.6.5 and Node.js 22.22.0 outside the checkout,
verifies pinned SHA256 archive hashes and installs PSScriptAnalyzer 1.25.0.
Versions are in `scripts/toolchain.json`; rerun setup when they change.
Setup is noninteractive and safe to repeat. HTTPS access to GitHub release
assets, nodejs.org and PowerShell Gallery is required. TLS verification stays
enabled; provision a corporate proxy CA in the OS trust store if needed.

On Windows, install PowerShell 7 and Node.js (the pinned versions are recommended),
then run `pwsh -NoProfile -File scripts/Setup-Tools.ps1`.

### Validation profiles

| Profile | Command | Scope |
| --- | --- | --- |
| Daily | `pwsh -NoProfile -File scripts/Test-Local.ps1 -Profile Dev` | Internal tests, PowerShell parsing, pinned analyzer, offline exporter integrations, JS syntax and simulated site/release states |
| Full offline | `pwsh -NoProfile -File scripts/Test-Local.ps1 -Profile Full` | Dev plus isolated packaging, archive contents, checksums, manifest and packaged exporter tests |
| Live OSRS | `pwsh -NoProfile -File scripts/Test-Local.ps1 -Profile Dev -NetworkSmoke` | Dev plus a real group 257 export in a temporary directory |

The original command without a profile runs Full. Windows also tests the real
file under PowerShell 5.1 when available. CI runs Full on Ubuntu and Windows
without publishing. Checks reuse installed tools and preserve tracked files.
Missing PowerShell, Node or the exact analyzer fails validation. Analyzer Error
severity is enforced; this is not a full style or formatting policy.

Dev excludes packaging, live APIs and browser rendering. Full is offline and
does not certify live services, browser rendering, signatures or production.
Add integrations matching the changed behavior and browser checks for UI changes.
A daily check is not release certification.

### Automation and site preview

```bash
pwsh -NoProfile -File Get-RunescapeClanMembers.ps1 -NonInteractive -Game OSRS -OsrsGroupId 257 -OutputFormat Csv
python3 -m http.server 8000 --bind 127.0.0.1 --directory docs
```

The explicit script switch `-NonInteractive` disables all prompts; supply the
required parameters. OSRS IDs avoid ambiguous searches. The preview serves
`http://127.0.0.1:8000/`; Ctrl+C stops it. The CLI has no health endpoint:
`-Version`/`-SelfTest` verify it offline and `-NetworkSmoke` verifies a real export.
RS3 needs `secure.runescape.com`; OSRS needs `api.wiseoldman.net`. The site reads
`api.github.com` and GitHub release assets, with a repository fallback on failure.
The self-hosted GoatCounter analytics service is not required for development.

`RS_CLAN_PLAIN_UI=1` is optional. There is no dotenv loader. Use synthetic data
and temporary output outside the repository; arbitrary OutputDir folders are
not automatically ignored.

For Codex Cloud, setup is `bash scripts/setup-cloud.sh`; daily validation is
`bash scripts/check-cloud.sh Dev` (or `Full` before publication). This wrapper puts
`$HOME/.local/bin` ahead of existing tools so the prepared runtimes are found.
Setup exports do not persist into the agent phase. No secrets or
local services are needed; enable targeted network access only for live tests.
These scripts do not modify the Cloud UI configuration.

### Publication boundaries and troubleshooting

Publishing requires Git, authenticated `gh`, clean `main`, an unused tag,
matching VERSION/script/changelog and Full validation. It pushes main and the
tag before creating the release; `-Draft` still pushes. Partial failures are not
rolled back: inspect local/remote tags and the release before resuming.
Timestamps make ZIP/manifest bytes vary between builds.

`.dockpanel/deploy.sh` prepares ignored `public/` from `docs/`; the external
platform handles deployment. Publication and deployment require explicit
instructions and must never run during setup or normal validation.
`Build-Release.ps1 -Clean` deletes local `dist/`; validation packages in isolation.

- Missing tools: rerun setup and check the agent PATH.
- Analyzer import error: run `scripts/Setup-Tools.ps1`; exact version required.
- Linux loader/ICU failure: provision the standard Ubuntu runtime libraries.
- Timeout/ambiguous group: check network access and use an OSRS ID with bounded retries.
- Release fallback: inspect the GitHub response/browser console; fixtures do not prove CORS or rendering.

Run the local safeguards without contacting Jagex or Wise Old Man:

```powershell
pwsh -NoProfile -File .\Get-RunescapeClanMembers.ps1 -SelfTest
```

From the repository, the full local command also checks the available PowerShell hosts and runs static analysis when `PSScriptAnalyzer` is installed:

```powershell
pwsh -NoProfile -File .\scripts\Test-Local.ps1
```

Add a real OSRS network smoke test on top of the local validations:

```powershell
pwsh -NoProfile -File .\scripts\Test-Local.ps1 -NetworkSmoke
```

The standard validation command intentionally makes no network calls. For plain text console output, set `RS_CLAN_PLAIN_UI=1` before running the script.

## Official Release

The repository uses a SemVer value in `VERSION`, a `CHANGELOG.md`, and locally generated release assets.

Prepare the release files:

```powershell
.\scripts\Test-Local.ps1
.\scripts\Build-Release.ps1 -Version 0.2.0 -Clean
```

Publish an official release from `main`:

```powershell
.\scripts\Publish-Release.ps1 -Version 0.2.0
```

Publishing creates a `vX.Y.Z` tag, pushes the tag, and attaches the versioned script, portable ZIP, SHA256 checksums, JSON manifest, and release notes.

## License

This project is released under the MIT License. See [LICENSE](LICENSE).

Unofficial project, not affiliated with Jagex, RuneScape, or Wise Old Man.

## Support

If this project is useful to you, you can support development through [GitHub Sponsors](https://github.com/sponsors/MathieuLF).
