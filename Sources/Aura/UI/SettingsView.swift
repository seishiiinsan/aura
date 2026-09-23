import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, discord, sources, display, rules, services, permissions, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "Général"
        case .discord: "Discord"
        case .sources: "Sources"
        case .display: "Affichage"
        case .rules: "Règles par app"
        case .services: "Services"
        case .permissions: "Autorisations"
        case .about: "À propos"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .discord: "bubble.left.and.bubble.right"
        case .sources: "square.stack.3d.up"
        case .display: "paintbrush"
        case .rules: "slider.horizontal.3"
        case .services: "network"
        case .permissions: "lock.shield"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @Environment(SettingsStore.self) private var store
    @ViewState private var pane: SettingsPane? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { p in
                Label(p.title, systemImage: p.symbol).tag(p)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            Group {
                switch pane ?? .general {
                case .general: GeneralPane()
                case .discord: DiscordPane()
                case .sources: SourcesPane()
                case .display: DisplayPane()
                case .rules: RulesPane()
                case .services: ServicesPane()
                case .permissions: PermissionsPane()
                case .about: AboutPane()
                }
            }
            .formStyle(.grouped)
            .navigationTitle((pane ?? .general).title)
        }
        .frame(minWidth: 760, minHeight: 540)
        .onAppear {
            if store.settings.clientID.isEmpty { pane = .discord }
        }
    }
}

// MARK: - Général

struct GeneralPane: View {
    @Environment(SettingsStore.self) private var store
    @Environment(PresenceEngine.self) private var engine
    @ViewState private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                PresenceCard(
                    snapshot: engine.snapshot,
                    appName: engine.snapshot.flatMap { engine.appInfo[$0.clientID]?.name },
                    paused: store.settings.paused
                )
                .listRowInsets(EdgeInsets())
            } header: {
                Text("Aperçu en direct")
            }

            Section("Démarrage") {
                Toggle("Lancer Aura à l'ouverture de session", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, new in
                        LaunchAtLogin.set(new)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                if LaunchAtLogin.requiresApproval {
                    HStack {
                        Text("macOS demande ton autorisation dans Réglages Système.").foregroundStyle(.secondary)
                        Spacer()
                        Button("Ouvrir") { LaunchAtLogin.openSystemSettings() }
                    }
                }
                Toggle("Mettre la diffusion en pause", isOn: $store.settings.paused)
            }

            Section("Langue de la présence") {
                Picker("Textes envoyés sur Discord", selection: $store.settings.language) {
                    ForEach(PresenceLanguage.allCases) { Text($0.title).tag($0) }
                }
            }

            Section {
                Toggle("Détecter l'inactivité", isOn: $store.settings.idleEnabled)
                if store.settings.idleEnabled {
                    Stepper(value: $store.settings.idleMinutes, in: 1...120) {
                        Text("Inactif après \(store.settings.idleMinutes) min sans clavier ni souris")
                    }
                    Picker("Quand tu es inactif", selection: $store.settings.idleBehavior) {
                        ForEach(IdleBehavior.allCases) { Text($0.title).tag($0) }
                    }
                }
            } header: {
                Text("Inactivité")
            } footer: {
                Text("Les jeux, la musique et les vidéos ne sont jamais considérés comme de l'inactivité.")
            }
        }
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }
}

// MARK: - Discord

struct DiscordPane: View {
    @Environment(SettingsStore.self) private var store
    @Environment(PresenceEngine.self) private var engine

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                HStack {
                    StatusPill(status: engine.status, hasClientID: !store.settings.clientID.isEmpty)
                    Spacer()
                    Button("Reconnecter") { engine.reconnect() }
                }
                ClientIDField(title: "Application ID principal", text: $store.settings.clientID, engine: engine)
            } header: {
                Text("Connexion")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Discord affiche le **nom de l'application** après « Joue à ». Crée-la en 1 minute :")
                    Text("1. Ouvre le portail développeur Discord et clique sur **New Application**.")
                    Text("2. Donne-lui le nom que tu veux voir (ex. « sur son Mac », « Aura »…), ajoute une icône si tu veux.")
                    Text("3. Copie l'**Application ID** de la page *General Information* et colle-le ci-dessus.")
                    Link("Ouvrir le portail développeur →", destination: URL(string: "https://discord.com/developers/applications")!)
                        .padding(.top, 2)
                }
                .font(.callout)
            }

            Section {
                ClientIDField(title: "Jeux", text: $store.settings.gameClientID, engine: engine)
                ClientIDField(title: "Musique", text: $store.settings.musicClientID, engine: engine)
                ClientIDField(title: "Vidéos", text: $store.settings.videoClientID, engine: engine)
                ClientIDField(title: "Code", text: $store.settings.codingClientID, engine: engine)
            } header: {
                Text("Applications par catégorie (optionnel)")
            } footer: {
                Text("Laisse vide pour utiliser l'application principale. Utile pour afficher « Écoute Musique » ou « Joue à Xcode » avec des noms différents.")
            }

            Section {
                Toggle("Utiliser l'identité officielle des jeux reconnus par Discord", isOn: $store.settings.useOfficialGameIdentity)
            } footer: {
                Text("Pour les ~25 000 jeux connus de Discord, ta présence affichera « Joue à <nom du jeu> » avec son icône officielle.")
            }
        }
    }
}

struct ClientIDField: View {
    let title: String
    @Binding var text: String
    let engine: PresenceEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(title, text: $text, prompt: Text("ex. 1234567890123456789"))
                .textFieldStyle(.roundedBorder)
                .font(.body.monospacedDigit())
                .onChange(of: text) { _, new in
                    let digits = new.filter(\.isNumber)
                    if digits != new { text = digits }
                }
            let id = text.trimmingCharacters(in: .whitespaces)
            if !id.isEmpty {
                if let info = engine.appInfo[id] {
                    HStack(spacing: 6) {
                        RemoteImage(url: info.iconURL, symbol: "app.fill").frame(width: 16, height: 16).clipShape(RoundedRectangle(cornerRadius: 4))
                        Text("Affiché comme « \(info.name) »").font(.caption).foregroundStyle(.green)
                    }
                } else if id.count < 17 {
                    Text("Un Application ID fait 17 à 20 chiffres.").font(.caption).foregroundStyle(.orange)
                } else {
                    Text("Vérification…").font(.caption).foregroundStyle(.secondary)
                        .task(id: id) { await engine.loadAppInfo(id) }
                }
            }
        }
    }
}

// MARK: - Sources

struct SourcesPane: View {
    @Environment(SettingsStore.self) private var store
    @Environment(PresenceEngine.self) private var engine

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                List {
                    ForEach(store.settings.priority) { kind in
                        HStack(spacing: 10) {
                            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                            Image(systemName: kind.symbol).frame(width: 20).foregroundStyle(Color.accentColor)
                            Text(kind.title)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { store.settings.isEnabled(kind) },
                                set: { on in
                                    if on { store.settings.disabledSources.remove(kind) } else { store.settings.disabledSources.insert(kind) }
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }
                        .padding(.vertical, 2)
                    }
                    .onMove { from, to in store.settings.priority.move(fromOffsets: from, toOffset: to) }
                }
                .frame(minHeight: 150)
            } header: {
                Text("Priorité")
            } footer: {
                Text("Glisse pour réordonner. Aura affiche la première source active de la liste : par défaut un jeu passe avant une vidéo, qui passe avant la musique, puis l'app au premier plan.")
            }

            Section("Jeux") {
                if engine.runningGames.isEmpty {
                    Text("Aucun jeu détecté en ce moment.").foregroundStyle(.secondary)
                } else {
                    ForEach(engine.runningGames, id: \.pid) { game in
                        HStack {
                            Image(systemName: "gamecontroller.fill").foregroundStyle(.green)
                            Text(game.name)
                            Spacer()
                            if let platform = game.platform { Text(platform).foregroundStyle(.secondary) }
                            if game.discordAppID != nil { Text("Reconnu par Discord").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                Text("Détection : bibliothèque Steam, catégorie « Jeux » de l'app, et catalogue officiel de Discord. Un jeu non détecté ? Ajoute une règle « Considérer comme un jeu ».")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Musique") {
                Toggle("Afficher aussi la musique en pause", isOn: $store.settings.musicShowPaused)
                Toggle("Barre de progression du morceau", isOn: $store.settings.showMusicProgress)
                Toggle("Autres lecteurs (onglets web, TIDAL, Deezer…)", isOn: $store.settings.musicOtherPlayers)
                Text("Spotify et Apple Music en natif ; YouTube Music, SoundCloud, Deezer, Spotify Web, TIDAL, Bandcamp, Amazon Music dans n'importe quel onglet, même en arrière-plan ; apps TIDAL, Deezer, Qobuz via leur fenêtre (Accessibilité).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Vidéos & navigateurs") {
                Toggle("Afficher le titre des pages web", isOn: $store.settings.showBrowserPageTitles)
                Toggle("Détails des films et séries (titre, épisode, affiche, progression)", isOn: $store.settings.readStreamingDetails)
                if store.settings.readStreamingDetails {
                    Text("Active « Autoriser JavaScript depuis les Apple Events » : Chrome/Arc/Brave → menu Affichage › Options pour les développeurs ; Safari → Réglages › Avancés › « Afficher les fonctionnalités pour les développeurs », puis menu Développement.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Text("YouTube (miniature + chaîne), Twitch (avatar du streamer), Netflix, Prime Video, Disney+, Crunchyroll, GitHub… dans Safari, Chrome, Arc, Brave, Edge, Vivaldi, Opera.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("App au premier plan") {
                Toggle("Afficher les noms de fichiers et de projets", isOn: $store.settings.showWindowTitles)
                Toggle("Lire les titres de fenêtres (Accessibilité)", isOn: $store.settings.readWindowTitlesWithAccessibility)
                    .onChange(of: store.settings.readWindowTitlesWithAccessibility) { _, on in
                        if on && !WindowInspector.isTrusted { WindowInspector.requestAccess() }
                    }
            }
        }
    }
}

// MARK: - Affichage

struct DisplayPane: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Section("Éléments de la présence") {
                Toggle("Temps écoulé", isOn: $store.settings.showElapsedTime)
                Toggle("Petite icône (plateforme, lecteur, navigateur)", isOn: $store.settings.showSmallIcon)
                Toggle("Boutons (Écouter sur Spotify, Voir sur YouTube…)", isOn: $store.settings.showButtons)
            }
            Section {
                Text("Les boutons ne sont visibles que par les autres membres, pas sur ton propre profil : c'est une limite de Discord.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Permissions

struct PermissionsPane: View {
    @Environment(PresenceEngine.self) private var engine

    var body: some View {
        Form {
            Section {
                PermissionRow(
                    title: "Accessibilité",
                    detail: "Lire le titre de la fenêtre active (fichier ouvert dans ton éditeur, document…).",
                    granted: engine.accessibilityGranted,
                    action: {
                        WindowInspector.requestAccess()
                        WindowInspector.openAccessibilitySettings()
                    }
                )
                PermissionRow(
                    title: "Automatisation",
                    detail: "Interroger Spotify, Musique et ton navigateur. macOS te le demande à la première utilisation de chaque app.",
                    granted: engine.automationDenied.isEmpty,
                    deniedDetail: engine.automationDenied.isEmpty ? nil : "Refusé pour : " + engine.automationDenied.sorted().joined(separator: ", "),
                    action: { WindowInspector.openAutomationSettings() }
                )
            } footer: {
                Text("Tout est traité localement sur ton Mac. Aura ne contacte que Discord (en local) et des API publiques pour les images (iTunes, Steam, YouTube).")
            }
        }
        .onAppear { engine.refreshPermissions() }
    }
}

struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    var deniedDetail: String?
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                if let deniedDetail { Text(deniedDetail).font(.caption).foregroundStyle(.orange) }
            }
            Spacer()
            Button(granted ? "Réglages" : "Autoriser", action: action)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - À propos

struct AboutPane: View {
    var body: some View {
        VStack(spacing: 14) {
            AuraLogo(size: 96)
            Text("Aura").font(.largeTitle.bold())
            Text("Ta Rich Presence Discord, automatique et soignée.")
                .foregroundStyle(.secondary)
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                .font(.caption).foregroundStyle(.tertiary)
            Button("Ouvrir le dossier de données") {
                NSWorkspace.shared.open(AuraPaths.support)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
