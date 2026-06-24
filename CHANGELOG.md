# Journal des changements

Toutes les versions officielles publiées sur GitHub doivent reprendre la section de version correspondante.

## [Non publié]

## [0.1.0] - 2026-06-24

- Première mise en ligne officielle de RuneScape Clan Roster Exporter.
- Export RS3 via l'endpoint public Jagex Clan Members Lite.
- Export OSRS via l'API publique Wise Old Man.
- Mode interactif avec choix par chiffres et mode automatisable par paramètres PowerShell.
- Sorties Markdown et CSV en UTF-8 avec BOM.
- Dossier de sortie résolu à côté du script, avec écriture atomique et fichier de récupération temporaire.
- Retries réseau, backoff progressif et respect de `Retry-After`.
- Microsite GitHub Pages avec encart dynamique alimenté par GitHub Releases.
- Version SemVer, journal des changements, packaging ZIP, script versionné, checksums SHA256 et manifeste de release.
