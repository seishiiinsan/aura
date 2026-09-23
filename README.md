# Aura

Ta Rich Presence Discord, automatique et soignée, pour macOS.

Aura vit dans la barre des menus, se lance avec ton Mac et met à jour ta présence Discord selon ce que tu fais : le jeu en cours avec sa jaquette, le morceau avec sa pochette, la vidéo YouTube avec sa miniature, le fichier ouvert dans ton éditeur… Tout est détecté localement, sans rien configurer à part ton application Discord.

## Ce qu'Aura détecte

| Source | Détection | Visuels & extras |
|---|---|---|
| **Jeux** | Bibliothèques Steam (`appmanifest`), apps de la catégorie « Jeux », catalogue officiel Discord (~25 000 jeux), Minecraft Java, règles perso | Icône officielle Discord, jaquette Steam, App Store ; « Joue à *Nom du jeu* » grâce à l'identité officielle ; bouton « Page Steam » |
| **Cloud gaming** | GeForce NOW (jeu et heure de lancement lus dans le journal de session de GFN, sans aucune autorisation), Xbox Cloud Gaming et GeForce NOW dans le navigateur | Identité et icône officielles du jeu, badge de la plateforme |
| **Musique** | Spotify, Apple Music (notifications système + AppleScript), YouTube Music | Pochette (Spotify / iTunes), barre de progression, bouton « Écouter sur… » |
| **Vidéos** | YouTube, Twitch, Netflix, Prime Video, Disney+, Crunchyroll, Apple TV+, Max, Canal+ ; IINA, VLC, QuickTime, TV | Miniature YouTube + chaîne, avatar du streamer Twitch, boutons |
| **Apps** | ~120 apps cataloguées (+ toute la suite JetBrains et Adobe) : éditeurs de code (Xcode, VS Code, Cursor, Zed, JetBrains…), terminaux, design, montage, MAO, messageries, bureautique, notes, IA, navigateurs | Fichier et projet ouverts dans l'éditeur, site visité, icône de l'app (App Store ou site officiel) |
| **Inactivité** | Aucun clavier ni souris pendant N minutes | « Absent » ou présence masquée |

La **priorité** entre les sources se règle par glisser-déposer (par défaut : jeu > vidéo > musique > app au premier plan).

## Personnalisation

- **Règles par app** : textes avec variables (`{app}`, `{file}`, `{project}`, `{track}`, `{artist}`, `{game}`…), image, bouton, type d'activité (Joue / Écoute / Regarde / En compétition), Application ID dédiée, ou **masquage complet** d'une app pour la confidentialité. Une règle peut aussi marquer une app comme jeu.
- **Applications Discord par catégorie** : un nom différent après « Joue à » pour les jeux, la musique, les vidéos ou le code.
- Langue de la présence (FR / EN), temps écoulé, petite icône, boutons, titres de fenêtres et de pages web.

## Installation

Pas besoin de Xcode : les Command Line Tools suffisent.

```bash
scripts/build-app.sh --install
```

Le script compile en release, génère l'icône, assemble et signe `Aura.app`, l'installe dans `/Applications` et la lance. Au premier lancement, Aura s'inscrit dans les éléments d'ouverture de session (désactivable dans Réglages → Général).

### Configurer Discord (1 minute)

1. Va sur <https://discord.com/developers/applications> → **New Application**.
2. Donne-lui le nom qui s'affichera après « Joue à » (et une icône si tu veux : elle sert d'image par défaut).
3. Copie l'**Application ID** et colle-le dans Aura → Réglages → Discord.

### Autorisations macOS

- **Automatisation** (demandée automatiquement) : lire Spotify, Musique et l'onglet actif du navigateur.
- **Accessibilité** (optionnelle) : lire le titre de la fenêtre active (fichier ouvert, jeu GeForce NOW…).

Avec une signature ad hoc, macOS peut redemander ces autorisations après chaque recompilation. Pour les garder, signe avec un certificat stable : `AURA_SIGN_IDENTITY="Mon certificat" scripts/build-app.sh --install`.

## Architecture

```
Sources/Aura
├── App/          Point d'entrée SwiftUI (MenuBarExtra + fenêtre de réglages), autotest
├── Core/         Réglages (JSON), lancement à l'ouverture de session (SMAppService), AppleScript, HTTP
├── Discord/      Client IPC (socket Unix, protocole RPC) et modèle d'activité
├── Detectors/    Musique, jeux (Steam / Discord / cloud), fenêtres (Accessibilité), navigateurs, inactivité
├── Artwork/      Recherche d'images : iTunes, Steam, YouTube, Discord, favicons
├── Engine/       Moteur de présence, catalogue d'apps et de sites, textes FR/EN
└── UI/           Barre des menus, aperçu façon Discord, réglages, règles
```

Frameworks Apple utilisés : SwiftUI, AppKit, Observation, ServiceManagement, ApplicationServices (Accessibility), Foundation (NSAppleScript, URLSession, DistributedNotificationCenter), CoreGraphics, OSLog.

### Diagnostic

```bash
/Applications/Aura.app/Contents/MacOS/Aura --selftest
```

Fait un handshake avec Discord (rien n'est affiché sur ton profil). `AURA_DEBUG=1` affiche chaque présence calculée dans le terminal.
