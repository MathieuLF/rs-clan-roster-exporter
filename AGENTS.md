# Working in this repository

This is a local PowerShell roster exporter and a static presentation site, not a backend application. There is no database, application package manager, Docker stack or required application secret.

## Setup and validation

- Ubuntu 24.04 x86_64: `bash scripts/setup-cloud.sh`. Pinned versions and archive hashes are in `scripts/toolchain.json`. Add `$HOME/.local/bin` to PATH, or use `~/.local/bin/pwsh` explicitly. Setup needs HTTPS; normal checks do not.
- Windows: install PowerShell 7 and Node.js, then run `pwsh -NoProfile -File scripts/Setup-Tools.ps1` to install the pinned analyzer.
- Daily: `pwsh -NoProfile -File scripts/Test-Local.ps1 -Profile Dev`.
- Cloud wrapper: `bash scripts/check-cloud.sh Dev` selects the prepared PATH; use `Full` for packaging validation.
- Before release: `pwsh -NoProfile -File scripts/Test-Local.ps1 -Profile Full`. The original command without a profile runs Full.
- Live OSRS integration: add `-NetworkSmoke`; it uses public group 257 and temporary output. Network success is not guaranteed by offline tests.
- UI changes also need browser checks of `docs/`, including download links, release fallback, keyboard navigation and narrow screens. The Node fixtures test behavior, not browser rendering.

After setup, use Dev for daily verification. Add integrations corresponding to the changed behavior and browser tests for UI changes. A successful Dev check is not full validation or release certification. Re-run setup after toolchain changes. Checks must preserve tracked files; never restore files automatically to hide generated differences.

## Architecture and contracts

- `Get-RunescapeClanMembers.ps1`: parameters/UI; HTTP/retries; RS3 CSV and OSRS JSON parsing; output/recovery; export orchestration; embedded self-tests. Keep Windows PowerShell 5.1 compatibility in this file.
- `scripts/`: setup, validation, packaging and explicit publication. `tests/` uses synthetic fixtures only.
- `docs/`: static HTML/CSS/JS; GitHub release data is fetched client-side. `.dockpanel/deploy.sh` prepares the static deployment directory.
- Keep output columns `Game, Clan, Pseudo, Rang, XP, Kills`, UTF-8 BOM, script-relative output directories, recovery snapshots and partial RS3/OSRS success semantics.
- Use `-NonInteractive` for automation, supply all parameters, and prefer `-OsrsGroupId` to ambiguous names. Preserve HTTPS by default, explicit opt-in HTTP fallback, paced calls and retry controls.
- Keep `VERSION`, application version and `CHANGELOG.md` coherent. Do not bump versions merely for onboarding changes.

## Boundaries

- Never commit real rosters, recovery data, tokens or credentials. Generate synthetic outputs outside the checkout; an arbitrary custom OutputDir is not automatically ignored.
- Publication, tags, pushes, infrastructure access and deployment execution require explicit instructions. `Publish-Release.ps1 -Draft` still pushes main and a tag.
- Changing publication/network/analytics settings requires attention to the requested scope. Do not turn setup or CI into a deployment.
- Build outputs belong in ignored `dist/` or isolated temporary directories. Preserve existing user output and unrelated changes.
