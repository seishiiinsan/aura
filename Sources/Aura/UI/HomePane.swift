import AppKit
import SwiftUI

/// Live dashboard: what Aura broadcasts right now and what every source sees.
struct HomePane: View {
    @Environment(PresenceEngine.self) private var engine
    @Environment(SettingsStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                HStack(alignment: .top, spacing: 16) {
                    PresenceCard(
                        snapshot: engine.snapshot,
                        appName: engine.snapshot.flatMap { engine.appInfo[$0.clientID]?.name },
                        paused: store.settings.paused
                    )
                    .frame(maxWidth: 380)
                    VStack(alignment: .leading, spacing: 10) {
                        controls
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("Sources").font(.title3.bold())
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
                    SourceTile(kind: .game, detail: gameDetail)
                    SourceTile(kind: .music, detail: musicDetail)
                    SourceTile(kind: .video, detail: engine.snapshot?.kind == .video ? engine.snapshot?.presence.details : nil)
                    SourceTile(kind: .app, detail: engine.snapshot?.kind == .app ? engine.snapshot?.sourceApp : nil)
                }
            }
            .padding(24)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            AuraLogo(size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("Aura").font(.largeTitle.bold())
                Text("Ta Rich Presence Discord, en direct").foregroundStyle(.secondary)
            }
            Spacer()
            StatusPill(status: engine.status, hasClientID: !store.settings.clientID.isEmpty)
        }
    }

    @ViewBuilder
    private var controls: some View {
        Toggle(isOn: Binding(get: { !store.settings.paused }, set: { store.settings.paused = !$0 })) {
            Label("Diffusion active", systemImage: "dot.radiowaves.left.and.right")
        }
        .toggleStyle(.switch)
        Picker(selection: Binding(
            get: { store.settings.activeProfileID },
            set: { id in if let p = store.settings.profiles.first(where: { $0.id == id }) { store.activate(p) } }
        )) {
            ForEach(store.settings.profiles) { Label($0.name, systemImage: $0.symbol).tag(Optional($0.id)) }
        } label: {
            Label("Profil", systemImage: "person.2.crop.square.stack")
        }
        if let focus = engine.activeFocus {
            Label("Concentration : \(focus)", systemImage: "moon.fill").foregroundStyle(.indigo)
        }
        if let error = engine.lastError {
            Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
        }
        HStack {
            Button("Reconnecter") { engine.reconnect() }
            Button("Insights") { InsightsLauncher.open() }
        }
    }

    private var gameDetail: String? {
        guard let game = engine.runningGames.first else { return nil }
        return game.platform.map { "\(game.name) · \($0)" } ?? game.name
    }

    private var musicDetail: String? {
        guard let np = engine.media.nowPlaying else { return nil }
        return "\(np.title) — \(np.artist)" + (np.isPlaying ? "" : " (pause)")
    }
}

struct SourceTile: View {
    @Environment(PresenceEngine.self) private var engine
    @Environment(SettingsStore.self) private var store
    let kind: SourceKind
    let detail: String?

    var body: some View {
        let enabled = store.settings.isEnabled(kind)
        let live = engine.snapshot?.kind == kind
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: kind.symbol).font(.title2).foregroundStyle(live ? Color.white : Color.accentColor)
                Spacer()
                if live { Text("EN DIRECT").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2).background(.green, in: Capsule()) }
                Toggle("", isOn: Binding(
                    get: { enabled },
                    set: { on in if on { store.settings.disabledSources.remove(kind) } else { store.settings.disabledSources.insert(kind) } }
                ))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }
            Text(kind.title).font(.headline).foregroundStyle(live ? .white : .primary)
            Text(detail ?? (enabled ? "Rien de détecté" : "Désactivé"))
                .font(.callout).lineLimit(2)
                .foregroundStyle(live ? .white.opacity(0.85) : .secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(live ? AnyShapeStyle(LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                           : AnyShapeStyle(.background.secondary))
        )
        .opacity(enabled ? 1 : 0.6)
    }
}

/// Opens the companion Aura Insights app (installed next to Aura).
@MainActor
enum InsightsLauncher {
    static let bundleID = "app.aura.Insights"

    static func open() {
        let candidates = [
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Aura Insights.app"),
            URL(fileURLWithPath: "/Applications/Aura Insights.app"),
        ].compactMap { $0 }
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            let alert = NSAlert()
            alert.messageText = "Aura Insights n'est pas installé"
            alert.informativeText = "Lance scripts/build-app.sh --install pour installer Aura et Aura Insights."
            alert.runModal()
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
