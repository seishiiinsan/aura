import Foundation

/// A named set of presence options that can be switched in one click, by URL, hotkey or Focus.
struct PresenceProfile: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var symbol: String
    var priority: [SourceKind]
    var disabledSources: Set<SourceKind>
    var showWindowTitles: Bool
    var showBrowserPageTitles: Bool
    var showButtons: Bool
    var showElapsedTime: Bool
    var showGitBranch: Bool
    var paused: Bool

    static let presets: [PresenceProfile] = [
        PresenceProfile(name: "Normal", symbol: "sparkles", priority: [.game, .video, .music, .code, .app], disabledSources: [],
                        showWindowTitles: true, showBrowserPageTitles: false, showButtons: true, showElapsedTime: true,
                        showGitBranch: true, paused: false),
        PresenceProfile(name: "Discret", symbol: "eye.slash", priority: [.game, .music, .video, .code, .app], disabledSources: [],
                        showWindowTitles: false, showBrowserPageTitles: false, showButtons: false, showElapsedTime: false,
                        showGitBranch: false, paused: false),
        PresenceProfile(name: "Streaming", symbol: "dot.radiowaves.left.and.right", priority: [.game, .video, .music, .code, .app],
                        disabledSources: [.app], showWindowTitles: false, showBrowserPageTitles: false, showButtons: true,
                        showElapsedTime: true, showGitBranch: false, paused: false),
        PresenceProfile(name: "Travail", symbol: "briefcase", priority: [.code, .app, .music, .video, .game], disabledSources: [.game, .video],
                        showWindowTitles: true, showBrowserPageTitles: false, showButtons: false, showElapsedTime: true,
                        showGitBranch: true, paused: false),
        PresenceProfile(name: "Invisible", symbol: "moon.zzz", priority: [.game, .video, .music, .code, .app], disabledSources: [],
                        showWindowTitles: false, showBrowserPageTitles: false, showButtons: false, showElapsedTime: false,
                        showGitBranch: false, paused: true),
    ]

    /// Captures the current options into a new profile.
    init(name: String, symbol: String = "person.crop.circle", from s: AuraSettings) {
        self.init(name: name, symbol: symbol, priority: s.priority, disabledSources: s.disabledSources,
                  showWindowTitles: s.showWindowTitles, showBrowserPageTitles: s.showBrowserPageTitles,
                  showButtons: s.showButtons, showElapsedTime: s.showElapsedTime, showGitBranch: s.showGitBranch, paused: s.paused)
    }

    init(id: UUID = UUID(), name: String, symbol: String, priority: [SourceKind], disabledSources: Set<SourceKind>,
         showWindowTitles: Bool, showBrowserPageTitles: Bool, showButtons: Bool, showElapsedTime: Bool,
         showGitBranch: Bool, paused: Bool) {
        self.id = id; self.name = name; self.symbol = symbol; self.priority = priority
        self.disabledSources = disabledSources; self.showWindowTitles = showWindowTitles
        self.showBrowserPageTitles = showBrowserPageTitles; self.showButtons = showButtons
        self.showElapsedTime = showElapsedTime; self.showGitBranch = showGitBranch; self.paused = paused
    }

    func apply(to s: inout AuraSettings) {
        s.priority = SourceKind.normalized(priority)
        s.disabledSources = disabledSources
        s.showWindowTitles = showWindowTitles
        s.showBrowserPageTitles = showBrowserPageTitles
        s.showButtons = showButtons
        s.showElapsedTime = showElapsedTime
        s.showGitBranch = showGitBranch
        s.paused = paused
        s.activeProfileID = id
    }
}

extension SettingsStore {
    var activeProfile: PresenceProfile? {
        settings.profiles.first { $0.id == settings.activeProfileID }
    }

    func activate(_ profile: PresenceProfile) {
        var s = settings
        profile.apply(to: &s)
        settings = s
    }

    /// Activates a profile by (case-insensitive) name. Returns false when unknown.
    @discardableResult
    func activateProfile(named name: String) -> Bool {
        guard let p = settings.profiles.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return false }
        activate(p)
        return true
    }

    func cycleProfile() {
        let list = settings.profiles
        guard !list.isEmpty else { return }
        let i = list.firstIndex { $0.id == settings.activeProfileID } ?? -1
        activate(list[(i + 1) % list.count])
    }

    func saveCurrentAsProfile(named name: String) {
        var p = PresenceProfile(name: name, from: settings)
        if let i = settings.profiles.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            p.id = settings.profiles[i].id
            p.symbol = settings.profiles[i].symbol
            settings.profiles[i] = p
        } else {
            settings.profiles.append(p)
        }
        settings.activeProfileID = p.id
    }
}
