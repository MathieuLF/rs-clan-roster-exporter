# Changelog

Every official GitHub release must reuse the matching version section.

## [Unreleased]

## [0.2.0] - 2026-07-09

- Added `-SelfTest` and `scripts/Test-Local.ps1` to validate parsing, exports, special-character paths, and HTTP safeguards locally without network calls.
- Improved Windows/Linux/macOS interoperability with a `pwsh` shebang, best-effort folder opening, and hardened output paths.
- Aligned the User-Agent with the application version and fail faster on permanent HTTP errors.
- Official publishing now runs local validation before creating assets, the tag, and the GitHub release.
- Added `-NetworkSmoke` to `scripts/Test-Local.ps1` for an optional real OSRS export validation.
- Refreshed the console UI and microsite with richer styling, PowerShell 7 color markers, illustrated buttons, and light animations.
- Converted public documentation and the microsite to English-only content.

## [0.1.0] - 2026-06-24

- First official release of RuneScape Clan Roster Exporter.
- RS3 export through the public Jagex Clan Members Lite endpoint.
- OSRS export through the public Wise Old Man API.
- Interactive mode with numbered choices and automation-friendly PowerShell parameters.
- Markdown and CSV outputs in UTF-8 with BOM.
- Output folder resolved next to the script, with atomic writes and temporary recovery files.
- Network retries, progressive backoff, and `Retry-After` support.
- GitHub Pages microsite with a dynamic card powered by GitHub Releases.
- SemVer versioning, changelog, ZIP packaging, versioned script, SHA256 checksums, and release manifest.
