import AppKit
import AuraKit
import SwiftUI

/// Live dashboard: what Aura broadcasts right now, today's totals and every source.
struct HomePane: View {
    @Environment(PresenceEngine.self) private var engine
    @Environment(SettingsStore.self) private var store

    var body: some View {
        Form {
            Section {
                PresenceCard(
                    snapshot: engine.snapshot,
                    appName: engine.snapshot.flatMap { engine.appInfo[$0.clientID]?.name },
                    paused: store.settings.paused,
                    chrome: .none
                )
                if let error = engine.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                if store.settings.clientID.isEmpty {
                    LabeledContent("Aucune application Discord configurée") {
                        Button("Configurer…") { MainNavigation.shared.pane = .discord }
                            .nativeButtonStyle(prominent: true)
                    }
                }
            } header: {
                Text("En direct sur Discord")
            }

            Section {
                TodaySummary()
            } header: {
                HStack {
                    Text("Aujourd'hui")
                    Spacer()
                    Button("Toutes les statistiques") { InsightsLauncher.open() }
                        .buttonStyle(.link)
                        .font(.callout)
                }
            }

            Section {
                SourceRow(kind: .game, color: .green, detail: gameDetail)
                SourceRow(kind: .music, color: .pink, detail: musicDetail)
                SourceRow(kind: .video, color: .red, detail: engine.snapshot?.kind == .video ? engine.snapshot?.presence.details : nil)
                SourceRow(kind: .code, color: .indigo, detail: engine.snapshot?.kind == .code ? engine.snapshot?.presence.details : nil)
                SourceRow(kind: .app, color: .blue, detail: engine.snapshot?.kind == .app ? engine.snapshot?.sourceApp : nil)
            } header: {
                Text("Sources")
            } footer: {
                if let focus = engine.activeFocus {
                    Label("Concentration « \(focus) » active", systemImage: "moon.fill")
                }
            }
        }
    }

    private var gameDetail: String? {
        guard let game = engine.runningGames.first else { return nil }
        return game.platform.map { "\(game.name) · \($0)" } ?? game.name
    }

    private var musicDetail: String? {
        guard let np = engine.media.nowPlaying else { return nil }
        return "\(np.title) — \(np.artist)" + (np.isPlaying ? "" : " (en pause)")
    }
}

/// A source with its live state and on/off switch.
struct SourceRow: View {
    @Environment(PresenceEngine.self) private var engine
    @Environment(SettingsStore.self) private var store
    let kind: SourceKind
    let color: Color
    let detail: String?

    var body: some View {
        let enabled = store.settings.isEnabled(kind)
        let live = engine.snapshot?.kind == kind && !store.settings.paused
        IconRow(symbol: kind.symbol, color: enabled ? color : .gray, title: kind.title,
                subtitle: detail ?? (enabled ? "Rien de détecté" : "Désactivée")) {
            if live {
                Text("En direct")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.green.gradient, in: Capsule())
            }
            Toggle("", isOn: Binding(
                get: { enabled },
                set: { on in if on { store.settings.disabledSources.remove(kind) } else { store.settings.disabledSources.insert(kind) } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
    }
}

/// Today's totals from the history, refreshed every minute.
struct TodaySummary: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let interval = StatsPeriod.today.interval(now: context.date)
            let stats = Stats(sessions: HistoryStore.shared.sessions(from: interval.start, to: interval.end), interval: interval)
            let topApp = stats.top("app", limit: 1, label: { $0.name }).first
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    MiniStat(title: "Actif", value: Format.duration(stats.activeTime()), symbol: "bolt.fill", color: .purple)
                    Divider()
                    MiniStat(title: "Jeu", value: Format.duration(stats.total("game")), symbol: "gamecontroller.fill", color: .green)
                    Divider()
                    MiniStat(title: "Musique", value: Format.duration(stats.total("music")), symbol: "music.note", color: .pink)
                    Divider()
                    MiniStat(title: topApp?.label ?? "App n°1", value: Format.duration(topApp?.seconds ?? 0), symbol: "macwindow", color: .blue)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct MiniStat: View {
    let title: String
    let value: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(color).font(.callout)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
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
            alert.informativeText = "Installe Aura Insights depuis la dernière version sur GitHub, ou lance scripts/build-app.sh --install."
            alert.runModal()
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
