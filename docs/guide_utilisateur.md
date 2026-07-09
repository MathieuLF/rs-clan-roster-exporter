# Guide utilisateur

## Démarrage rapide

Téléchargez `Get-RunescapeClanMembers.ps1`, ouvrez PowerShell dans le dossier du script, puis lancez :

```powershell
.\Get-RunescapeClanMembers.ps1
```

Sur Linux ou macOS, utilisez PowerShell 7+ :

```powershell
pwsh ./Get-RunescapeClanMembers.ps1
```

Le mode interactif demande le jeu cible, le nom du clan ou du groupe, puis le format de sortie.

## Exemples

Exporter un clan RS3 en CSV :

```powershell
.\Get-RunescapeClanMembers.ps1 -Game RS3 -ClanName "Example Clan" -OutputFormat Csv
```

Exporter un groupe OSRS en Markdown :

```powershell
.\Get-RunescapeClanMembers.ps1 -Game OSRS -ClanName "Example Group" -OutputFormat Markdown
```

Rechercher le même nom dans RS3 et OSRS :

```powershell
.\Get-RunescapeClanMembers.ps1 -Game Both -ClanName "Example Clan" -OutputFormat Csv
```

## Fichiers générés

Par défaut, les fichiers sont écrits dans `output`, à côté du script. Les exports générés ne doivent pas être publiés dans le dépôt.

## Vérification locale

Le script peut vérifier ses garde-fous internes sans appel réseau :

```powershell
pwsh -NoProfile -File ./Get-RunescapeClanMembers.ps1 -SelfTest
```

Depuis le dépôt, la validation complète peut aussi faire un smoke test réseau OSRS :

```powershell
pwsh -NoProfile -File ./scripts/Test-Local.ps1 -NetworkSmoke
```

## PowerShell bloque le script

Si PowerShell refuse l'exécution du script local, lancez cette commande pour cette exécution seulement :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-RunescapeClanMembers.ps1
```

## Limites

- RS3 dépend de l'endpoint public Jagex Clan Members Lite.
- OSRS dépend de Wise Old Man.
- `-OpenFolder` tente d'ouvrir le dossier de sortie avec l'association locale du système; si ce n'est pas possible, le chemin affiché reste utilisable.
- Le projet ne remplace pas une validation humaine avant de publier ou partager un roster.
