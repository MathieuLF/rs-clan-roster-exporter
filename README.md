# RuneScape Clan Roster Exporter

![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE)
![Output Markdown or CSV](https://img.shields.io/badge/Output-Markdown%20%7C%20CSV-2ea44f)
![License MIT](https://img.shields.io/badge/License-MIT-blue)
[![Site GitHub Pages](https://img.shields.io/badge/Site-GitHub%20Pages-167a63)](https://mathieulf.github.io/rs-clan-roster-exporter/)
[![Sponsor](https://img.shields.io/badge/Sponsor-GitHub-ea4aaa)](https://github.com/sponsors/MathieuLF)

Exportateur PowerShell local pour récupérer les membres d'un clan RuneScape 3 ou d'un groupe OSRS, puis générer un fichier Markdown ou CSV.

Tout se lance depuis `Get-RunescapeClanMembers.ps1`, en mode interactif ou avec paramètres.

Site de présentation : [mathieulf.github.io/rs-clan-roster-exporter](https://mathieulf.github.io/rs-clan-roster-exporter/).

## Points clés

- Export RS3 via l'endpoint public Jagex Clan Members Lite.
- Export OSRS via l'API publique Wise Old Man.
- Mode interactif simple avec des choix de menu par chiffre : RS3, OSRS ou les deux.
- Mode automatisable avec paramètres PowerShell.
- Sorties Markdown et CSV en UTF-8 avec BOM, pratiques pour Excel, GitHub et PowerShell.
- Dossier `output` créé à côté du script, peu importe le dossier courant de PowerShell.
- Aperçu console, progression, retries réseau et sauvegarde locale de récupération.
- Fin de séquence claire : relancer une recherche ou fermer la fenêtre.

## Prérequis

- Windows PowerShell 5.1 ou PowerShell 7+.
- Accès Internet pour joindre les endpoints publics RS3 ou Wise Old Man.
- Un terminal PowerShell. Les exemples ci-dessous supposent que tu es dans le dossier du projet.

## Démarrage rapide

Depuis le dossier du script :

```powershell
.\Get-RunescapeClanMembers.ps1
```

Le mode interactif pose trois questions :

1. Jeu cible : `1` pour RS3, `2` pour OSRS, `3` pour RS3 + OSRS
2. Nom du clan ou du groupe
3. Format de sortie : `1` pour Markdown, `2` pour CSV

À la fin, le script affiche le chemin complet du ou des fichiers générés et un lien local `file:///...` lorsque le terminal peut le rendre cliquable. Il demande ensuite si tu veux relancer une recherche ou fermer la fenêtre.

## Exemples

Exporter un clan RS3 en CSV :

```powershell
.\Get-RunescapeClanMembers.ps1 -Game RS3 -ClanName "Wapitiklan Empire" -OutputFormat Csv
```

Exporter un clan RS3 en Markdown :

```powershell
.\Get-RunescapeClanMembers.ps1 -Game RS3 -ClanName "Wapitiklan Empire" -OutputFormat Markdown
```

Exporter un groupe OSRS par son nom, par exemple KnightSlayer :

```powershell
.\Get-RunescapeClanMembers.ps1 -Game OSRS -ClanName "KnightSlayer" -OutputFormat Csv
```

Rechercher le même nom dans RS3 et OSRS :

```powershell
.\Get-RunescapeClanMembers.ps1 -Game Both -ClanName "KnightSlayer" -OutputFormat Markdown
```

Exporter un groupe OSRS par identifiant Wise Old Man :

```powershell
.\Get-RunescapeClanMembers.ps1 -Game OSRS -OsrsGroupId 257 -OutputFormat Csv
```

Utiliser des retries plus patients si le service distant répond lentement :

```powershell
.\Get-RunescapeClanMembers.ps1 -Game RS3 -ClanName "Wapitiklan Empire" -OutputFormat Csv -TimeoutSec 120 -MaxRetries 6 -RetryBaseDelaySec 15 -MaxRetryDelaySec 180
```

## Dossier de sortie

Par défaut, les exports sont écrits dans :

```text
<dossier-du-script>\output
```

Le chemin de sortie relatif est toujours résolu depuis le dossier du script, pas depuis le dossier courant de PowerShell. Donc même si le script est lancé depuis ailleurs, `.\output` reste à côté de `Get-RunescapeClanMembers.ps1`.

Changer le dossier de sortie :

```powershell
.\Get-RunescapeClanMembers.ps1 -Game RS3 -ClanName "Wapitiklan Empire" -OutputFormat Csv -OutputDir ".\exports"
```

Dans cet exemple, `.\exports` sera lui aussi créé à côté du script. Un chemin absolu, lui, sera utilisé tel quel.

## Fichiers générés

Le nom du fichier dépend du jeu, du clan ou groupe, du format choisi et d'un horodatage complet :

```text
rs3-nom-du-clan-members-2026-06-24_13-05-42.csv
rs3-nom-du-clan-members-2026-06-24_13-05-42.md
osrs-nom-du-groupe-members-2026-06-24_13-05-42.csv
osrs-nom-du-groupe-members-2026-06-24_13-05-42.md
```

Le format d'horodatage est `yyyy-MM-dd_HH-mm-ss`, en heure locale. Les fichiers de récupération utilisent le même horodatage que l'export correspondant.

Colonnes principales :

| Colonne | Description |
| --- | --- |
| `Game` | `RS3` ou `OSRS` |
| `Clan` | Nom du clan ou du groupe exporté |
| `Pseudo` | Nom du membre |
| `Rang` | Rang retourné par la source |
| `XP` | XP retournée par la source |
| `Kills` | Valeur RS3 lorsque disponible |

Pour OSRS, `Kills` reste vide parce que Wise Old Man ne fournit pas cette information dans la liste des membres du groupe.

## Paramètres utiles

| Paramètre | Utilité |
| --- | --- |
| `-Game RS3`, `-Game OSRS` ou `-Game Both` | Choisit la source à exporter |
| `-ClanName "Nom"` | Recherche un clan ou groupe par nom |
| `-OsrsGroupId 257` | Cible directement un groupe Wise Old Man |
| `-OutputFormat Markdown` ou `-OutputFormat Csv` | Choisit le format généré |
| `-OutputDir ".\output"` | Définit le dossier de sortie |
| `-PreviewCount 50` | Contrôle le nombre de membres affichés en aperçu |
| `-ShowAllInConsole` | Affiche tous les membres dans la console |
| `-OpenFolder` | Ouvre le dossier de sortie à la fin |
| `-TimeoutSec 120` | Augmente le délai maximal d'un appel réseau |
| `-MaxRetries 6` | Augmente le nombre de tentatives |
| `-RequestDelaySec 2` | Définit le délai minimal entre deux appels HTTP |
| `-KeepRecoveryFile` | Conserve le fichier local de récupération |
| `-RepositoryUrl "https://github.com/..."` | Ajoute l'URL du dépôt au User-Agent |

## Résultats partiels et erreurs

Si tu demandes RS3 + OSRS et que le clan est trouvé seulement d'un côté, le fichier trouvé est généré et l'autre source est indiquée comme non exportée. Si rien n'est trouvé, aucun fichier n'est généré et le résumé l'indique clairement.

Si la recherche des membres a déjà réussi avant une erreur de génération, un fichier `*.recovery.json` peut être conservé pour éviter de perdre les données récupérées.

Les fichiers finaux sont écrits de façon atomique : un fichier complet remplace l'ancien seulement lorsque la génération est terminée. Un fichier temporaire `.tmp-*` peut rester si l'exécution est interrompue au mauvais moment.

## PowerShell bloque le script

Selon la configuration Windows, PowerShell peut refuser l'exécution d'un script local. Dans ce cas, utilise :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-RunescapeClanMembers.ps1
```

Cette commande lance le script pour cette exécution seulement.

## Sécurité et respect des services

- Sources publiques seulement : Jagex Clan Members Lite pour RS3, Wise Old Man pour OSRS.
- Aucun compte RuneScape requis.
- User-Agent explicite.
- HTTPS par défaut pour RS3.
- Fallback HTTP RS3 disponible uniquement avec `-AllowInsecureFallback`.
- Appels réseau séquentiels, avec backoff progressif et respect de `Retry-After`.
- Exports générés (`output/`, `exports/`, fichiers de récupération et temporaires) ignorés par Git.

## Notes

- RS3 dépend de la disponibilité de l'endpoint public Jagex.
- OSRS dépend de Wise Old Man; le groupe doit exister publiquement sur Wise Old Man.
- Si plusieurs groupes OSRS correspondent à une recherche, le script demande de choisir avec un chiffre.
- En mode RS3 + OSRS, chaque source est traitée séparément : un échec OSRS ne bloque pas l'export RS3, et inversement.
- Les paramètres textuels restent disponibles pour l'automatisation, même si le mode interactif privilégie les chiffres.
- Le lien `file:///...` est une aide pratique; son côté cliquable dépend du terminal utilisé.

## Licence

Ce projet est publié sous licence MIT. Voir [LICENSE](LICENSE).

Projet non officiel, sans affiliation avec Jagex, RuneScape ou Wise Old Man.

## Soutenir

Si ce projet t'est utile, tu peux soutenir son développement via [GitHub Sponsors](https://github.com/sponsors/MathieuLF).
