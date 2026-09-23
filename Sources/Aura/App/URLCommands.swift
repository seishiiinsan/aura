import Foundation

/// `aura://` commands, usable from Shortcuts ("Open URL"), Focus automations, scripts or a browser.
///
/// - `aura://pause`, `aura://resume`, `aura://toggle`
/// - `aura://profile/<name>` — activate a profile
/// - `aura://source/<game|video|music|app>/<on|off>`
/// - `aura://custom?details=…&state=…&image=…&type=playing|listening|watching|competing&minutes=30`
/// - `aura://clear` — end a custom presence
/// - `aura://settings`, `aura://open`
@MainActor
enum URLCommands {
    static func handle(_ url: URL, store: SettingsStore, engine: PresenceEngine, openWindow: (String) -> Void) {
        guard url.scheme == "aura" else { return }
        let command = (url.host ?? "").lowercased()
        let path = url.pathComponents.filter { $0 != "/" }
        let query = Dictionary(
            (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { $1 }
        )

        switch command {
        case "pause": store.settings.paused = true
        case "resume": store.settings.paused = false
        case "toggle": store.settings.paused.toggle()
        case "profile":
            if let name = path.first?.removingPercentEncoding { store.activateProfile(named: name) }
        case "next-profile":
            store.cycleProfile()
        case "source":
            guard path.count >= 2, let kind = SourceKind(rawValue: path[0]) else { return }
            if path[1] == "off" { store.settings.disabledSources.insert(kind) } else { store.settings.disabledSources.remove(kind) }
        case "custom":
            var p = RichPresence(type: ActivityTypeOverride(rawValue: query["type"] ?? "")?.type ?? .playing)
            p.statusDisplay = .details
            p.details = query["details"]
            p.state = query["state"]
            p.largeImage = query["image"]
            p.largeText = query["text"]
            p.start = Date()
            if let label = query["button"], let link = query["url"] { p.buttons = [PresenceButton(label: label, url: link)] }
            let minutes = Double(query["minutes"] ?? "") ?? 60
            engine.setCustomPresence(p, until: Date().addingTimeInterval(minutes * 60))
        case "clear":
            engine.setCustomPresence(nil, until: nil)
        case "settings", "open":
            openWindow(command == "settings" ? "settings" : "main")
        default:
            break
        }
    }
}
