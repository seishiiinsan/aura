import AuraKit
import SwiftUI

/// The menu bar panel, laid out like a Control Center module.
struct MenuBarView: View {
    @Environment(PresenceEngine.self) private var engine
    @Environment(SettingsStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            PresenceCard(
                snapshot: engine.snapshot,
                appName: engine.snapshot.flatMap { engine.appInfo[$0.clientID]?.name },
                paused: store.settings.paused,
                chrome: .glass
            )

            if let error = engine.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }

            if store.settings.clientID.isEmpty {
                Button {
                    open(.discord)
                } label: {
                    Label("Configurer ton application Discord", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .nativeButtonStyle(prominent: true)
                .controlSize(.large)
            }

            sources

            Divider().padding(.horizontal, 4)

            VStack(spacing: 2) {
                profileMenu
                MenuRow(title: "Ouvrir Aura", symbol: "macwindow", shortcut: "⌃⌥⌘A") { open(.home) }
                MenuRow(title: "Aura Insights", symbol: "chart.bar.xaxis") { InsightsLauncher.open() }
                MenuRow(title: "Réglages…", symbol: "gearshape", shortcut: "⌘,") { open(.general) }
            }

            Divider().padding(.horizontal, 4)

            MenuRow(title: "Quitter Aura", symbol: "power", shortcut: "⌘Q") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Aura").font(.headline)
                HStack(spacing: 5) {
                    StatusDot(store.settings.paused ? .orange : ConnectionText.color(engine.status, hasClientID: !store.settings.clientID.isEmpty))
                    Text(ConnectionText.text(engine.status, hasClientID: !store.settings.clientID.isEmpty, paused: store.settings.paused))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(get: { !store.settings.paused }, set: { store.settings.paused = !$0 }))
                .labelsHidden()
                .toggleStyle(.switch)
                .help(store.settings.paused ? "Reprendre la diffusion" : "Mettre la diffusion en pause")
        }
    }

    private var sources: some View {
        NativeGlassGroup(spacing: 14) {
            HStack(spacing: 0) {
                ForEach(store.settings.priority) { kind in
                    let enabled = store.settings.isEnabled(kind)
                    VStack(spacing: 5) {
                        RoundToggleButton(symbol: kind.symbol, isOn: enabled, tint: color(kind)) {
                            if enabled { store.settings.disabledSources.insert(kind) } else { store.settings.disabledSources.remove(kind) }
                        }
                        .overlay(alignment: .topTrailing) {
                            if engine.snapshot?.kind == kind && !store.settings.paused {
                                Circle().fill(.green).frame(width: 9, height: 9)
                                    .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                            }
                        }
                        Text(shortTitle(kind)).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .help("\(kind.title) — \(enabled ? "activée" : "désactivée")")
                }
            }
        }
    }

    private var profileMenu: some View {
        Menu {
            ForEach(store.settings.profiles) { profile in
                Button {
                    store.activate(profile)
                } label: {
                    Label(profile.name, systemImage: profile.id == store.settings.activeProfileID ? "checkmark" : profile.symbol)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: store.activeProfile?.symbol ?? "person.crop.circle").frame(width: 18)
                Text("Profil")
                Spacer()
                Text(store.activeProfile?.name ?? "Personnalisé").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.visible)
    }

    private func color(_ kind: SourceKind) -> Color {
        switch kind {
        case .game: .green
        case .video: .red
        case .music: .pink
        case .code: .indigo
        case .app: .blue
        }
    }

    private func shortTitle(_ kind: SourceKind) -> String {
        switch kind {
        case .game: "Jeux"
        case .video: "Vidéos"
        case .music: "Musique"
        case .code: "Code"
        case .app: "Apps"
        }
    }

    private func open(_ pane: SettingsPane) {
        MainNavigation.shared.pane = store.settings.clientID.isEmpty ? .discord : pane
        openWindow(id: "main")
        NSApp.activate()
    }
}

/// A menu-like row with hover highlight, as in native menu bar extras.
struct MenuRow: View {
    let title: String
    let symbol: String
    var shortcut: String? = nil
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).frame(width: 18)
                Text(title)
                Spacer()
                if let shortcut { Text(shortcut).foregroundStyle(hovering ? Color.white.opacity(0.8) : Color.secondary).font(.callout) }
            }
            .foregroundStyle(hovering ? Color.white : Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                if hovering { RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.accentColor) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// The app mark, used where the real app icon isn't available.
struct AuraLogo: View {
    var size: CGFloat

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: size, height: size)
    }
}
