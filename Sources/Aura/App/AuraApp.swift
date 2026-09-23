import AppKit
import SwiftUI

@main
struct AuraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        SelfTest.runIfRequested()
        SelfTest.renderCardIfRequested()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(delegate.engine)
                .environment(delegate.store)
        } label: {
            MenuBarIcon(engine: delegate.engine, store: delegate.store)
        }
        .menuBarExtraStyle(.window)

        Window("Aura", id: "main") {
            MainView()
                .environment(delegate.engine)
                .environment(delegate.store)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 980, height: 680)
        .defaultLaunchBehavior(delegate.needsOnboarding ? .presented : .suppressed)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Réglages…") {
                    MainNavigation.shared.pane = .general
                    WindowOpener.shared.open?("main")
                }
                .keyboardShortcut(",")
            }
            CommandMenu("Présence") {
                Button(delegate.store.settings.paused ? "Reprendre la diffusion" : "Mettre en pause") {
                    delegate.store.settings.paused.toggle()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Profil suivant") { delegate.store.cycleProfile() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Reconnecter à Discord") { delegate.engine.reconnect() }
                Divider()
                Button("Ouvrir Aura Insights") { InsightsLauncher.open() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
            }
        }
    }
}

struct MenuBarIcon: View {
    let engine: PresenceEngine
    let store: SettingsStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: symbol)
            .onAppear {
                // The menu bar label lives for the whole session: hand the window opener to AppKit code.
                WindowOpener.shared.open = { id in
                    openWindow(id: id)
                    NSApp.activate()
                }
            }
    }

    private var symbol: String {
        if store.settings.paused { return "moon.zzz" }
        guard case .connected = engine.status else { return "sparkle" }
        switch engine.snapshot?.kind {
        case .game: return "gamecontroller.fill"
        case .music: return "music.note"
        case .video: return "play.tv"
        default: return "sparkles"
        }
    }
}

@MainActor
final class WindowOpener {
    static let shared = WindowOpener()
    var open: ((String) -> Void)?
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SettingsStore()
    lazy var engine = PresenceEngine(store: store)

    var needsOnboarding: Bool { store.settings.clientID.isEmpty }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if !store.settings.hasLaunchedBefore, Bundle.main.bundleURL.pathExtension == "app" {
            // First run of the real bundle: start with the Mac, as expected from a background utility.
            if LaunchAtLogin.set(true) { store.settings.hasLaunchedBefore = true }
        }
        engine.start()
        setUpHotKeys()
    }

    private func setUpHotKeys() {
        HotKeys.shared.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .togglePause: store.settings.paused.toggle()
            case .nextProfile: store.cycleProfile()
            case .openMain: WindowOpener.shared.open?("main")
            case .cycleSource:
                // Rotates which source has top priority.
                var p = store.settings.priority
                if !p.isEmpty { p.append(p.removeFirst()) }
                store.settings.priority = p
            }
        }
        HotKeys.shared.setEnabled(store.settings.globalHotKeys)
        var lastEnabled = store.settings.globalHotKeys
        let previous = store.onChange
        store.onChange = { [weak self] in
            previous?()
            guard let self else { return }
            if store.settings.globalHotKeys != lastEnabled {
                lastEnabled = store.settings.globalHotKeys
                HotKeys.shared.setEnabled(lastEnabled)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
        // Give the IPC queue a moment to flush the clear-activity frame.
        Thread.sleep(forTimeInterval: 0.2)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            URLCommands.handle(url, store: store, engine: engine) { id in WindowOpener.shared.open?(id) }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WindowOpener.shared.open?("main") }
        return true
    }
}
