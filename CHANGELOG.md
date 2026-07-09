# Journal des changements

Toutes les versions officielles publiées sur GitHub doivent reprendre la section de version correspondante.

## [Non publié]

## [0.2.0] - 2026-07-09

- Ajout de `-SelfTest` et de `scripts/Test-Local.ps1` pour valider localement le parsing, les exports, les chemins spéciaux et les garde-fous HTTP sans appel réseau.
- Amélioration de l'interopérabilité Windows/Linux/macOS avec shebang `pwsh`, ouverture de dossier best-effort et chemins de sortie durcis.
- Cohérence du User-Agent avec la version applicative et arrêt plus rapide sur les erreurs HTTP permanentes.
- La publication officielle lance maintenant la validation locale avant de créer les assets, le tag et la release.
- Ajout d'un mode `-NetworkSmoke` à `scripts/Test-Local.ps1` pour valider un export OSRS réel à la demande.
- Interface console et microsite plus vivants : symboles colorés en PowerShell 7, palette enrichie, boutons illustrés et animations légères.

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
