import AuraKit
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case home, general, discord, sources, display, profiles, rules, services, permissions, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Maintenant"
        case .general: "Général"
        case .discord: "Discord"
        case .sources: "Sources"
        case .display: "Affichage"
        case .profiles: "Profils"
        case .rules: "Règles par app"
        case .services: "Services"
        case .permissions: "Confidentialité"
        case .about: "À propos"
        }
    }

    var symbol: String {
        switch self {
        case .home: "sparkles"
        case .general: "gearshape.fill"
        case .discord: "bubble.left.and.bubble.right.fill"
        case .sources: "square.stack.3d.up.fill"
        case .display: "paintbrush.pointed.fill"
        case .profiles: "person.2.fill"
        case .rules: "slider.horizontal.3"
        case .services: "network"
        case .permissions: "hand.raised.fill"
        case .about: "info"
        }
    }

    var color: Color {
        switch self {
        case .home: .purple
        case .general: .gray
        case .discord: .indigo
        case .sources: .blue
        case .display: .pink
        case .profiles: .orange
        case .rules: .teal
        case .services: .green
        case .permissions: .blue
        case .about: .gray
        }
    }

    /// Words searched by the sidebar filter.
    var keywords: String {
        switch self {
        case .home: "maintenant accueil direct aujourd'hui"
        case .general: "démarrage ouverture session pause raccourcis historique langue inactivité absent"
        case .discord: "application id client connexion identité jeux"
        case .sources: "priorité jeux musique vidéos navigateur spotify youtube git fichiers"
        case .display: "affichage temps boutons icône langage animé gif"
        case .profiles: "profils concentration focus discret streaming travail"
        case .rules: "règles app personnaliser masquer conditions"
        case .services: "steam steamgriddb icônes clé api"
        case .permissions: "autorisations accessibilité automatisation confidentialité"
        case .about: "version mise à jour github"
        }
    }
}

/// Which pane the main window shows; shared so menus, URLs and hotkeys can deep-link.
@MainActor
@Observable
final class MainNavigation {
    static let shared = MainNavigation()
    var pane: SettingsPane? = .home
}

/// Aura's main window: a live dashboard plus every setting, System Settings–style.
struct MainView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(PresenceEngine.self) private var engine
    @Bindable private var nav = MainNavigation.shared
    @ViewState private var search = ""

    private var visiblePanes: [SettingsPane] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return SettingsPane.allCases }
        return SettingsPane.allCases.filter {
            $0.title.localizedCaseInsensitiveContains(q) || $0.keywords.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $nav.pane) {
                if visiblePanes.contains(.home) {
                    Section { row(.home) }
                }
                Section {
                    ForEach(visiblePanes.filter { $0 != .home && $0 != .about }) { row($0) }
                }
                if visiblePanes.contains(.about) {
                    Section { row(.about) }
                }
                Section {
                    Button {
                        InsightsLauncher.open()
                    } label: {
                        Label {
                            HStack {
                                Text("Aura Insights")
                                Spacer()
                                Image(systemName: "arrow.up.forward.app").foregroundStyle(.secondary)
                            }
                        } icon: {
                            SettingsIcon("chart.bar.xaxis", color: .purple)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $search, placement: .sidebar, prompt: "Rechercher")
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            Group {
                switch nav.pane ?? .home {
                case .home: HomePane()
                case .general: GeneralPane()
                case .discord: DiscordPane()
                case .sources: SourcesPane()
                case .display: DisplayPane()
                case .profiles: ProfilesPane()
                case .rules: RulesPane()
                case .services: ServicesPane()
                case .permissions: PermissionsPane()
                case .about: AboutPane()
                }
            }
            .formStyle(.grouped)
            .softScrollEdges()
            .navigationTitle((nav.pane ?? .home).title)
            .navigationSubtitle(ConnectionText.text(engine.status, hasClientID: !store.settings.clientID.isEmpty, paused: store.settings.paused))
            .toolbar { MainToolbar() }
        }
        .frame(minWidth: 860, minHeight: 580)
        .onAppear {
            if store.settings.clientID.isEmpty { nav.pane = .discord }
            DockPresence.windowDidOpen()
        }
        .onDisappear { DockPresence.windowDidClose() }
    }

    private func row(_ p: SettingsPane) -> some View {
        Label {
            Text(p.title)
        } icon: {
            SettingsIcon(p.symbol, color: p.color)
        }
        .tag(p)
    }
}

/// Toolbar shared by every pane: pause, profile, reconnect, Insights.
struct MainToolbar: ToolbarContent {
    @Environment(SettingsStore.self) private var store
    @Environment(PresenceEngine.self) private var engine

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                ForEach(store.settings.profiles) { profile in
                    Button {
                        store.activate(profile)
                    } label: {
                        Label(profile.name, systemImage: profile.id == store.settings.activeProfileID ? "checkmark" : profile.symbol)
                    }
                }
            } label: {
                Label(store.activeProfile?.name ?? "Profil", systemImage: store.activeProfile?.symbol ?? "person.crop.circle")
            }
            .help("Profil de présence")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                store.settings.paused.toggle()
            } label: {
                Label(store.settings.paused ? "Reprendre" : "Pause",
                      systemImage: store.settings.paused ? "play.fill" : "pause.fill")
                    .contentTransition(.symbolEffect(.replace))
            }
            .help(store.settings.paused ? "Reprendre la diffusion" : "Mettre la diffusion en pause")
        }
        if #available(macOS 26, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { InsightsLauncher.open() } label: { Label("Insights", systemImage: "chart.bar.xaxis") }
                .help("Ouvrir Aura Insights")
        }
    }
}

enum ConnectionText {
    static func text(_ status: DiscordIPC.Status, hasClientID: Bool, paused: Bool) -> String {
        if paused { return "Diffusion en pause" }
        guard hasClientID else { return "Application Discord non configurée" }
        switch status {
        case .connected(let user): return user.map { "Connecté à Discord · \($0)" } ?? "Connecté à Discord"
        case .connecting: return "Connexion à Discord…"
        case .disconnected: return "Déconnecté de Discord"
        case .failed(let reason): return reason
        }
    }

    static func color(_ status: DiscordIPC.Status, hasClientID: Bool) -> Color {
        guard hasClientID else { return .orange }
        switch status {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected, .failed: return .red
        }
    }
}

/// Shows Aura in the Dock (and app switcher) only while its window is open.
@MainActor
enum DockPresence {
    private static var openCount = 0

    static func windowDidOpen() {
        openCount += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    static func windowDidClose() {
        openCount = max(0, openCount - 1)
        if openCount == 0 { NSApp.setActivationPolicy(.accessory) }
    }
}

/// A form row with a System Settings icon, title and optional subtitle.
struct IconRow<Trailing: View>: View {
    let symbol: String
    let color: Color
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            SettingsIcon(symbol, color: color, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension IconRow where Trailing == EmptyView {
    init(symbol: String, color: Color, title: String, subtitle: String? = nil) {
        self.init(symbol: symbol, color: color, title: title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Général

struct GeneralPane: View {
    @Environment(SettingsStore.self) private var store
    @ViewState private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                IconRow(symbol: "power", color: .gray, title: "Ouvrir à la connexion",
                        subtitle: "Aura démarre en arrière-plan avec ton Mac.") {
                    Toggle("", isOn: $launchAtLogin).labelsHidden().toggleStyle(.switch)
                }
                .onChange(of: launchAtLogin) { _, new in
                    LaunchAtLogin.set(new)
                    launchAtLogin = LaunchAtLogin.isEnabled
                }
                if LaunchAtLogin.requiresApproval {
                    LabeledContent("macOS attend ton autorisation") {
                        Button("Ouvrir les Réglages…") { LaunchAtLogin.openSystemSettings() }
                    }
                }
                IconRow(symbol: "pause.fill", color: .orange, title: "Mettre la diffusion en pause",
                        subtitle: "Ta présence Discord est masquée ; l'historique continue.") {
                    Toggle("", isOn: $store.settings.paused).labelsHidden().toggleStyle(.switch)
                }
            }

            Section("Langue") {
                Picker("Textes envoyés sur Discord", selection: $store.settings.language) {
                    ForEach(PresenceLanguage.allCases) { Text($0.title).tag($0) }
                }
            }

            Section {
                Toggle("Détecter l'inactivité", isOn: $store.settings.idleEnabled)
                if store.settings.idleEnabled {
                    Stepper(value: $store.settings.idleMinutes, in: 1...120) {
                        LabeledContent("Délai", value: "\(store.settings.idleMinutes) min")
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

            Section {
                Toggle("Enregistrer l'historique des activités", isOn: $store.settings.historyEnabled)
                LabeledContent("Statistiques") {
                    Button("Ouvrir Aura Insights") { InsightsLauncher.open() }
                }
            } header: {
                Text("Historique")
            } footer: {
                Text("Jeux, musique, vidéos et apps sont enregistrés en parallèle dans une base locale. Rien ne quitte ton Mac.")
            }

            Section {
                Toggle("Raccourcis clavier globaux", isOn: $store.settings.globalHotKeys)
                if store.settings.globalHotKeys {
                    LabeledContent("Pause / reprise") { KeyCaps("⌃⌥⌘P") }
                    LabeledContent("Profil suivant") { KeyCaps("⌃⌥⌘N") }
                    LabeledContent("Source prioritaire suivante") { KeyCaps("⌃⌥⌘S") }
                    LabeledContent("Ouvrir Aura") { KeyCaps("⌃⌥⌘A") }
                }
            } header: {
                Text("Raccourcis clavier")
            }
        }
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }
}

struct KeyCaps: View {
    let keys: String
    init(_ keys: String) { self.keys = keys }
    var body: some View {
        Text(keys)
            .font(.system(.callout, design: .rounded).weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
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
                LabeledContent("État") {
                    HStack(spacing: 6) {
                        StatusDot(ConnectionText.color(engine.status, hasClientID: !store.settings.clientID.isEmpty))
                        Text(ConnectionText.text(engine.status, hasClientID: !store.settings.clientID.isEmpty, paused: false))
                            .foregroundStyle(.secondary)
                    }
                }
                ClientIDField(title: "Application ID", text: $store.settings.clientID, engine: engine)
                LabeledContent("") {
                    HStack {
                        Link("Portail développeur Discord", destination: URL(string: "https://discord.com/developers/applications")!)
                        Button("Reconnecter") { engine.reconnect() }
                    }
                }
            } header: {
                Text("Application principale")
            } footer: {
                Text("Discord affiche le **nom de l'application** après « Joue à ». Crée une application (New Application), donne-lui le nom voulu et une icône, puis colle son Application ID ici.")
            }

            Section {
                ClientIDField(title: "Jeux", text: $store.settings.gameClientID, engine: engine)
                ClientIDField(title: "Musique", text: $store.settings.musicClientID, engine: engine)
                ClientIDField(title: "Vidéos", text: $store.settings.videoClientID, engine: engine)
                ClientIDField(title: "Code", text: $store.settings.codingClientID, engine: engine)
            } header: {
                Text("Applications par catégorie")
            } footer: {
                Text("Optionnel. Laisse vide pour utiliser l'application principale.")
            }

            Section {
                Toggle("Identité officielle des jeux", isOn: $store.settings.useOfficialGameIdentity)
            } footer: {
                Text("Pour les ~25 000 jeux connus de Discord, ta présence affiche « Joue à <nom du jeu> » avec son icône officielle.")
            }
        }
    }
}

struct ClientIDField: View {
    let title: String
    @Binding var text: String
    let engine: PresenceEngine

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            TextField(title, text: $text, prompt: Text("Non défini"))
                .font(.body.monospacedDigit())
                .multilineTextAlignment(.trailing)
                .onChange(of: text) { _, new in
                    let digits = new.filter(\.isNumber)
                    if digits != new { text = digits }
                }
            let id = text.trimmingCharacters(in: .whitespaces)
            if !id.isEmpty {
                Group {
                    if let info = engine.appInfo[id] {
                        HStack(spacing: 5) {
                            RemoteImage(url: info.iconURL, symbol: "app.fill").frame(width: 14, height: 14)
                                .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                            Text("« \(info.name) »")
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    } else if id.count < 17 {
                        Label("17 à 20 chiffres", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    } else {
                        HStack(spacing: 4) { ProgressView().controlSize(.mini); Text("Vérification…") }
                            .task(id: id) { await engine.loadAppInfo(id) }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Sources

struct SourcesPane: View {
    @Environment(SettingsStore.self) private var store
    @Environment(PresenceEngine.self) private var engine

    private func color(_ kind: SourceKind) -> Color {
        switch kind {
        case .game: .green
        case .video: .red
        case .music: .pink
        case .code: .indigo
        case .app: .blue
        }
    }

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                ForEach(store.settings.priority) { kind in
                    IconRow(symbol: kind.symbol, color: color(kind), title: kind.title) {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                            .help("Glisse pour réordonner")
                        Toggle("", isOn: Binding(
                            get: { store.settings.isEnabled(kind) },
                            set: { on in
                                if on { store.settings.disabledSources.remove(kind) } else { store.settings.disabledSources.insert(kind) }
                            }
                        ))
                        .labelsHidden().toggleStyle(.switch)
                    }
                }
                .onMove { from, to in store.settings.priority.move(fromOffsets: from, toOffset: to) }
            } header: {
                Text("Priorité")
            } footer: {
                Text("Glisse les sources pour les réordonner : Aura affiche la première source active.")
            }

            Section {
                if engine.runningGames.isEmpty {
                    LabeledContent("Jeux en cours", value: "Aucun")
                } else {
                    ForEach(engine.runningGames, id: \.pid) { game in
                        LabeledContent(game.name) {
                            HStack(spacing: 6) {
                                if game.discordAppID != nil {
                                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.indigo).help("Reconnu par Discord")
                                }
                                Text(game.platform ?? "macOS")
                            }
                        }
                    }
                }
            } header: {
                Text("Jeux")
            } footer: {
                Text("Steam, Epic, GOG, Battle.net, CrossOver/Whisky, GeForce NOW, catégorie « Jeux » et catalogue Discord. Un jeu manque ? Crée une règle « Considérer comme un jeu ».")
            }

            Section("Musique") {
                Toggle("Autres lecteurs", isOn: $store.settings.musicOtherPlayers)
                    .help("Onglets YouTube Music, SoundCloud, Deezer, Spotify Web, TIDAL… et apps TIDAL, Deezer, Qobuz")
                Toggle("Afficher aussi la musique en pause", isOn: $store.settings.musicShowPaused)
                Toggle("Barre de progression", isOn: $store.settings.showMusicProgress)
            }

            Section {
                Toggle("Titre des pages web", isOn: $store.settings.showBrowserPageTitles)
                Toggle("Détails des films et séries", isOn: $store.settings.readStreamingDetails)
            } header: {
                Text("Vidéos & navigateurs")
            } footer: {
                if store.settings.readStreamingDetails {
                    Text("Active « Autoriser JavaScript depuis les Apple Events » dans ton navigateur (menu Développement de Safari, Affichage › Options pour les développeurs dans Chrome, Arc, Brave).")
                }
            }

            Section {
                Toggle("Noms de fichiers et de projets", isOn: $store.settings.showWindowTitles)
                Toggle("Branche git", isOn: $store.settings.showGitBranch)
                Toggle("Bouton « Voir sur GitHub »", isOn: $store.settings.showRepoButton)
                TextField("Dossiers de projets", text: Binding(
                    get: { store.settings.projectRoots.joined(separator: ", ") },
                    set: { store.settings.projectRoots = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                ))
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
            } header: {
                Text("Code")
            } footer: {
                Text("Éditeurs et IDE (Xcode, VS Code, Cursor, Zed, JetBrains…), terminaux et outils de dev forment la source Code, séparée des autres apps.")
            }

            Section("App au premier plan") {
                Toggle("Lire les titres de fenêtres", isOn: $store.settings.readWindowTitlesWithAccessibility)
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
            Section {
                IconRow(symbol: "timer", color: .green, title: "Temps écoulé") {
                    Toggle("", isOn: $store.settings.showElapsedTime).labelsHidden().toggleStyle(.switch)
                }
                IconRow(symbol: "circle.circle.fill", color: .blue, title: "Petite icône", subtitle: "Plateforme, lecteur ou navigateur") {
                    Toggle("", isOn: $store.settings.showSmallIcon).labelsHidden().toggleStyle(.switch)
                }
                IconRow(symbol: "curlybraces", color: .indigo, title: "Logo du langage", subtitle: "Swift, TypeScript, Python… quand tu codes") {
                    Toggle("", isOn: $store.settings.codingLanguageIcons).labelsHidden().toggleStyle(.switch)
                }
                IconRow(symbol: "photo.stack.fill", color: .pink, title: "Visuels animés", subtitle: "Jaquettes GIF / WebP quand elles existent") {
                    Toggle("", isOn: $store.settings.preferAnimatedArtwork).labelsHidden().toggleStyle(.switch)
                }
                IconRow(symbol: "rectangle.on.rectangle", color: .orange, title: "Boutons", subtitle: "Écouter sur Spotify, Voir sur YouTube…") {
                    Toggle("", isOn: $store.settings.showButtons).labelsHidden().toggleStyle(.switch)
                }
            } header: {
                Text("Éléments de la présence")
            } footer: {
                Text("Les boutons ne sont visibles que par les autres membres, pas sur ton propre profil.")
            }
        }
    }
}

// MARK: - Confidentialité

struct PermissionsPane: View {
    @Environment(PresenceEngine.self) private var engine

    var body: some View {
        Form {
            Section {
                PermissionRow(symbol: "accessibility", color: .blue, title: "Accessibilité",
                              detail: "Titre de la fenêtre active : fichier ouvert, apps TIDAL et Deezer.",
                              granted: engine.accessibilityGranted) {
                    WindowInspector.requestAccess()
                    WindowInspector.openAccessibilitySettings()
                }
                PermissionRow(symbol: "gearshape.2.fill", color: .gray, title: "Automatisation",
                              detail: engine.automationDenied.isEmpty
                                ? "Spotify, Musique et navigateurs. Demandée à la première utilisation."
                                : "Refusée pour : " + engine.automationDenied.sorted().joined(separator: ", "),
                              granted: engine.automationDenied.isEmpty) {
                    WindowInspector.openAutomationSettings()
                }
                PermissionRow(symbol: "internaldrive.fill", color: .indigo, title: "Accès complet au disque",
                              detail: "Optionnel : détecter automatiquement les modes Concentration.",
                              granted: FocusMonitor.canRead) {
                    FocusMonitor.openFullDiskAccessSettings()
                }
            } footer: {
                Text("Tout est traité localement. Aura contacte uniquement Discord (sur ton Mac) et des API publiques pour les images.")
            }
        }
        .onAppear { engine.refreshPermissions() }
    }
}

struct PermissionRow: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        IconRow(symbol: symbol, color: color, title: title, subtitle: detail) {
            if granted {
                Label("Autorisé", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
                    .font(.callout)
            } else {
                Button("Autoriser…", action: action)
            }
        }
    }
}

// MARK: - À propos

struct AboutPane: View {
    @Environment(SettingsStore.self) private var store
    @Bindable private var updater = Updater.shared

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)
                    Text("Aura").font(.title.bold())
                    Text("Version \(updater.currentVersion)").foregroundStyle(.secondary)
                    Text("Ta Rich Presence Discord, automatique et soignée.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section("Mises à jour") {
                Toggle("Rechercher automatiquement", isOn: $store.settings.autoCheckUpdates)
                LabeledContent {
                    updateStatus
                } label: {
                    Button("Rechercher maintenant") { Task { await updater.check() } }
                        .disabled(updater.phase == .checking || updater.phase == .downloading)
                }
            }

            Section {
                LabeledContent("Code source") {
                    Link("github.com/\(Updater.repository)", destination: URL(string: "https://github.com/\(Updater.repository)")!)
                }
                LabeledContent("Données") {
                    Button("Afficher dans le Finder") { NSWorkspace.shared.open(AuraPaths.support) }
                }
            }
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updater.phase {
        case .idle: Text("Jamais vérifié").foregroundStyle(.secondary)
        case .checking: HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Recherche…") }
        case .upToDate: Label("Aura est à jour", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .available(let release):
            HStack {
                Link("Version \(release.version)", destination: release.pageURL)
                Button("Installer") { Task { await updater.install(release) } }
                    .nativeButtonStyle(prominent: true)
            }
        case .downloading: HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Téléchargement…") }
        case .installing: HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Installation…") }
        case .failed(let message): Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}
