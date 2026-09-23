# Aura

[![CI](https://github.com/seishiiinsan/aura/actions/workflows/ci.yml/badge.svg)](https://github.com/seishiiinsan/aura/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/seishiiinsan/aura?label=release&color=8a5cf6)](https://github.com/seishiiinsan/aura/releases/latest)

Ta Rich Presence Discord, automatique et soignée, pour macOS — et **Aura Insights**, l'app qui transforme tout ce que tu fais en statistiques.

Aura vit dans la barre des menus (et dans une vraie fenêtre quand tu l'ouvres), se lance avec ton Mac et met à jour ta présence Discord selon ce que tu fais : le jeu en cours avec sa jaquette, le morceau avec sa pochette, la vidéo avec sa miniature, le fichier ouvert dans ton éditeur avec le logo du langage… Tout est détecté localement.

## Ce qu'Aura détecte

| Source | Détection | Visuels & extras |
|---|---|---|
| **Jeux** | Steam, Epic Games, Heroic (Epic/GOG), GOG Galaxy, Battle.net, apps de la catégorie « Jeux », catalogue officiel Discord (~25 000 jeux), jeux Windows via **CrossOver / Whisky / Wine**, Minecraft Java | Jaquettes **SteamGridDB** (animées en option), icône officielle Discord, Steam ; « Joue à *Nom du jeu* » avec l'identité officielle ; statut Steam détaillé (mode, carte…) |
| **Cloud gaming** | **GeForce NOW** (jeu et heure lus dans son journal de session, sans autorisation), Xbox Cloud Gaming et GFN dans le navigateur | Identité et icône officielles du jeu |
| **Steam partout** | API Web Steam : parties lancées sur Steam Deck, PC, Steam Link | Statut Rich Presence de Steam |
| **Musique** | Spotify, Apple Music (natif) ; YouTube Music, SoundCloud, Deezer, Spotify Web, TIDAL, Bandcamp, Amazon Music dans **n'importe quel onglet**, même en arrière-plan ; apps TIDAL, Deezer, Qobuz | Pochette, barre de progression, bouton « Écouter sur… » |
| **Vidéos** | YouTube, Twitch, Netflix, Prime Video, Disney+, Crunchyroll, Apple TV+, Max, Canal+ ; IINA, VLC, QuickTime, TV | Miniature et chaîne YouTube, avatar Twitch, **titre, épisode, affiche et progression** des séries (via `navigator.mediaSession`) |
| **Apps** | ~120 apps cataloguées + suites JetBrains et Adobe | Fichier, projet, **branche git**, **logo du langage**, site visité, **vraies icônes macOS** hébergées dans ce dépôt |
| **Inactivité** | Aucun clavier ni souris pendant N minutes | « Absent » ou présence masquée |

## Personnalisation

- **Profils** (Normal, Discret, Streaming, Travail, Invisible + les tiens), changés depuis la barre des menus, un raccourci, un lien ou **automatiquement avec les modes Concentration** de macOS.
- **Règles par app** : textes avec variables (`{app}` `{file}` `{project}` `{branch}` `{language}` `{track}` `{artist}` `{game}` `{status}`…), image (GIF acceptés), bouton, type d'activité, Application ID dédiée, masquage complet ; **conditions** (heures, jours, titre de fenêtre, écran externe) ; plusieurs règles par app ; **aperçu en direct 10 s** sur Discord.
- Applications Discord par catégorie, langue FR/EN, temps écoulé, boutons, titres de fenêtres et de pages…

## Aura Insights

Une app à part qui lit l'historique enregistré par Aura (base SQLite locale, flux parallèles : tu peux coder en écoutant de la musique) :

- **Vue d'ensemble** : temps actif, jeu, musique, vidéos, apps, séries de jours, tendances vs période précédente, jour par jour, répartition, journée type, tops.
- **Chronologie** d'une journée (flux en parallèle) et détail de chaque session.
- **Wrapped** : ton app, ton jeu, ton artiste, ton titre en boucle, ton langage, ton profil (lève-tôt / oiseau de nuit)…
- **Apps** (classement, catégories, carte de chaleur), **Code** (langages, éditeurs, projets, branches, fichiers), **Musique** (titres, artistes, albums, nouveaux artistes, lecteurs, heures d'écoute), **Jeux** (temps, sessions, plateformes, record), **Vidéos & web** (services, chaînes, vidéos, sites), **Habitudes & records** (premier/dernier signe de vie, journée record, heure de pointe, jours de la semaine…).
- Périodes : aujourd'hui, hier, 7 / 30 / 90 jours, 12 mois, depuis le début. Export CSV / JSON, suppression par période.

## Piloter Aura

| Raccourci global | Action |
|---|---|
| ⌃⌥⌘P | Pause / reprise |
| ⌃⌥⌘N | Profil suivant |
| ⌃⌥⌘S | Changer la source prioritaire |
| ⌃⌥⌘A | Ouvrir Aura |

Liens `aura://` (app Raccourcis → « Ouvrir les URL », automatisations de Concentration, terminal) :

```
aura://pause   aura://resume   aura://toggle   aura://next-profile
aura://profile/Discret
aura://source/game/off
aura://custom?details=En%20réunion&state=Ne%20pas%20déranger&minutes=45
aura://clear   aura://open   aura://settings   aura://insights
```

## Installation

### Télécharger

**[⬇︎ Télécharger Aura.dmg](https://github.com/seishiiinsan/aura/releases/latest/download/Aura.dmg)** (macOS 15 ou plus récent), puis glisse **Aura** et **Aura Insights** dans Applications.

La release n'étant pas notarisée, macOS bloque le premier lancement : clic droit → **Ouvrir**, ou Réglages Système → Confidentialité et sécurité → **Ouvrir quand même**. Les mises à jour suivantes s'installent depuis Aura → À propos.

### Compiler depuis les sources

Pas besoin de Xcode : les Command Line Tools suffisent.

```bash
scripts/build-app.sh --install
```

Compile en release, génère les icônes, assemble et signe `Aura.app` et `Aura Insights.app`, les installe dans `/Applications` et lance Aura. Au premier lancement, Aura s'inscrit dans les éléments d'ouverture de session. Les versions publiées sur GitHub (`Aura.dmg`) se mettent ensuite à jour depuis Réglages → À propos.

### Configurer Discord (1 minute)

1. <https://discord.com/developers/applications> → **New Application**, avec le nom à afficher après « Joue à ».
2. Copie l'**Application ID** dans Aura → Discord.

### Services optionnels (Aura → Services)

- **Steam** : SteamID + clé API Web (stockée dans le trousseau).
- **SteamGridDB** : clé API gratuite pour les jaquettes.
- **Icônes hébergées** : `swift scripts/export-icons.swift <bundle.id>` exporte de vraies icônes d'apps dans `assets/icons`.

### Autorisations macOS

- **Automatisation** : Spotify, Musique, navigateurs (demandée automatiquement).
- **Accessibilité** (optionnel) : titres de fenêtres, apps TIDAL/Deezer.
- **Accès complet au disque** (optionnel) : détection automatique des modes Concentration.
- Détails des séries : activer « Autoriser JavaScript depuis les Apple Events » dans le navigateur.

## Développement

```bash
swift build          # Aura + Aura Insights
swift test           # 26 tests (Swift Testing), dont un faux serveur IPC Discord
scripts/build-app.sh # bundles .app
scripts/package-release.sh  # Aura.zip + Aura.dmg (notarisés si APPLE_ID/APPLE_TEAM_ID/APPLE_APP_PASSWORD)
```

- **CI** : build, tests et bundles à chaque push (`.github/workflows/ci.yml`).
- **Release** : pousser un tag `vX.Y.Z` publie `Aura.zip` + `Aura.dmg` (signés/notarisés si les secrets `MACOS_CERT_P12`, `MACOS_CERT_PASSWORD`, `AURA_SIGN_IDENTITY`, `APPLE_*` existent).

```
Sources/
├── Aura/            App barre des menus + fenêtre : détecteurs, moteur, Discord IPC, UI
│   ├── App/         Point d'entrée, liens aura://, diagnostics
│   ├── Core/        Réglages, profils, trousseau, raccourcis, mises à jour, démarrage
│   ├── Discord/     Client IPC (socket Unix) et modèle d'activité
│   ├── Detectors/   Musique, jeux (Steam/Epic/GOG/Wine/cloud), Steam Web, Concentration, git, fenêtres, navigateurs
│   ├── Artwork/     iTunes, Steam, SteamGridDB, YouTube, Discord, icônes hébergées
│   ├── Engine/      Moteur de présence, catalogues, langages, textes FR/EN
│   └── UI/          Barre des menus, tableau de bord, réglages, règles, profils, services
├── AuraKit/         Historique SQLite, enregistreur de sessions, statistiques (partagé)
└── AuraInsights/    App de statistiques (Swift Charts)
```

Frameworks Apple uniquement : SwiftUI, AppKit, Charts, Observation, ServiceManagement, Security, Carbon (raccourcis), ApplicationServices, CoreGraphics, SQLite3, Foundation, OSLog.

Diagnostic : `/Applications/Aura.app/Contents/MacOS/Aura --selftest` (handshake Discord sans rien afficher) ; `AURA_DEBUG=1` affiche chaque présence calculée et les réponses de Discord.
