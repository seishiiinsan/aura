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

        Window("Réglages d'Aura", id: "settings") {
            SettingsView()
                .environment(delegate.engine)
                .environment(delegate.store)
        }
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(delegate.needsOnboarding ? .presented : .suppressed)
    }
}

struct MenuBarIcon: View {
    let engine: PresenceEngine
    let store: SettingsStore

    var body: some View {
        Image(systemName: symbol)
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
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
        // Give the IPC queue a moment to flush the clear-activity frame.
        Thread.sleep(forTimeInterval: 0.2)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true
    }
}
