import SwiftUI

struct MenuBarView: View {
    @Environment(PresenceEngine.self) private var engine
    @Environment(SettingsStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                AuraLogo(size: 22)
                Text("Aura").font(.headline)
                Spacer()
                StatusPill(status: engine.status, hasClientID: !store.settings.clientID.isEmpty)
            }

            PresenceCard(
                snapshot: engine.snapshot,
                appName: engine.snapshot.flatMap { engine.appInfo[$0.clientID]?.name },
                paused: store.settings.paused
            )

            if let error = engine.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }

            if store.settings.clientID.isEmpty {
                Button {
                    openSettings()
                } label: {
                    Label("Configurer ton application Discord", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            sourcesRow

            profileMenu

            Divider()

            HStack {
                Toggle(isOn: Binding(
                    get: { !store.settings.paused },
                    set: { store.settings.paused = !$0 }
                )) {
                    Text(store.settings.paused ? "En pause" : "Diffusion active")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                Spacer()
                Button {
                    openSettings()
                } label: {
                    Image(systemName: "macwindow")
                }
                .buttonStyle(.borderless)
                .help("Ouvrir Aura")
                .keyboardShortcut(",")
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.borderless)
                .help("Quitter Aura")
                .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 340)
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
            Label("Profil : \(store.activeProfile?.name ?? "Personnalisé")", systemImage: store.activeProfile?.symbol ?? "slider.horizontal.3")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var sourcesRow: some View {
        HStack(spacing: 6) {
            ForEach(store.settings.priority) { kind in
                let enabled = store.settings.isEnabled(kind)
                let active = engine.snapshot?.kind == kind
                Button {
                    if enabled { store.settings.disabledSources.insert(kind) } else { store.settings.disabledSources.remove(kind) }
                } label: {
                    Image(systemName: kind.symbol)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .foregroundStyle(active ? Color.white : (enabled ? Color.primary : Color.secondary.opacity(0.5)))
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary.opacity(enabled ? 1 : 0.4)))
                        )
                }
                .buttonStyle(.plain)
                .help("\(kind.title) — \(enabled ? "activé" : "désactivé")")
            }
        }
    }

    private func openSettings() {
        MainNavigation.shared.pane = store.settings.clientID.isEmpty ? .discord : .home
        openWindow(id: "main")
        NSApp.activate()
    }
}

struct StatusPill: View {
    let status: DiscordIPC.Status
    let hasClientID: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary.opacity(0.6), in: Capsule())
    }

    private var color: Color {
        guard hasClientID else { return .orange }
        switch status {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected, .failed: return .red
        }
    }

    private var text: String {
        guard hasClientID else { return "Non configuré" }
        switch status {
        case .connected(let user): return user.map { "Connecté · \($0)" } ?? "Connecté"
        case .connecting: return "Connexion…"
        case .disconnected: return "Déconnecté"
        case .failed(let reason): return reason
        }
    }
}

/// The app mark: a glowing ring, also used to render the app icon.
struct AuraLogo: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(AngularGradient(colors: [.purple, .indigo, .cyan, .pink, .purple], center: .center))
            Circle()
                .fill(.black.opacity(0.85))
                .padding(size * 0.2)
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.32, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}
