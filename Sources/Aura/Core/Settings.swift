import CoreGraphics
import Foundation
import Observation
import OSLog

/// The kinds of activity Aura can broadcast, ordered by user priority.
enum SourceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case game, video, music, app

    var id: String { rawValue }

    var title: String {
        switch self {
        case .game: "Jeux"
        case .video: "Vidéos & streams"
        case .music: "Musique"
        case .app: "App au premier plan"
        }
    }

    var symbol: String {
        switch self {
        case .game: "gamecontroller.fill"
        case .video: "play.tv.fill"
        case .music: "music.note"
        case .app: "macwindow"
        }
    }
}

enum PresenceLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case fr, en
    var id: String { rawValue }
    var title: String { self == .fr ? "Français" : "English" }
}

enum IdleBehavior: String, Codable, CaseIterable, Identifiable, Sendable {
    case clear, away
    var id: String { rawValue }
    var title: String { self == .clear ? "Masquer la présence" : "Afficher « Absent »" }
}

enum RuleMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case customize, hide, game
    var id: String { rawValue }
    var title: String {
        switch self {
        case .customize: "Personnaliser"
        case .hide: "Masquer (privé)"
        case .game: "Considérer comme un jeu"
        }
    }
}

enum ActivityTypeOverride: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto, playing, listening, watching, competing
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: "Automatique"
        case .playing: "Joue à"
        case .listening: "Écoute"
        case .watching: "Regarde"
        case .competing: "En compétition"
        }
    }
    var type: ActivityType? {
        switch self {
        case .auto: nil
        case .playing: .playing
        case .listening: .listening
        case .watching: .watching
        case .competing: .competing
        }
    }
}

/// When a rule applies. Empty conditions always match.
struct RuleConditions: Codable, Hashable, Sendable {
    var useHours = false
    /// Minutes since midnight; a range crossing midnight (22:00 → 02:00) is supported.
    var fromMinute = 9 * 60
    var toMinute = 18 * 60
    /// Calendar weekdays (1 = Sunday … 7 = Saturday); empty = every day.
    var weekdays: Set<Int> = []
    /// Case-insensitive text the focused window title must contain.
    var titleContains = ""
    var requiresExternalDisplay = false

    var isEmpty: Bool { !useHours && weekdays.isEmpty && titleContains.isEmpty && !requiresExternalDisplay }

    func matches(date: Date = Date(), title: String?, externalDisplay: Bool) -> Bool {
        let cal = Calendar.current
        if !weekdays.isEmpty, !weekdays.contains(cal.component(.weekday, from: date)) { return false }
        if useHours {
            let c = cal.dateComponents([.hour, .minute], from: date)
            let now = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            let inRange = fromMinute <= toMinute ? (now >= fromMinute && now < toMinute) : (now >= fromMinute || now < toMinute)
            if !inRange { return false }
        }
        if !titleContains.isEmpty, !(title ?? "").localizedCaseInsensitiveContains(titleContains) { return false }
        if requiresExternalDisplay, !externalDisplay { return false }
        return true
    }
}

/// A per-application override created by the user.
struct AppRule: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var bundleID: String
    var appName: String
    var mode: RuleMode = .customize
    var details: String = ""
    var state: String = ""
    var largeImageURL: String = ""
    var largeText: String = ""
    var clientID: String = ""
    var activityType: ActivityTypeOverride = .auto
    var buttonLabel: String = ""
    var buttonURL: String = ""
    var conditions = RuleConditions()

    init(bundleID: String, appName: String) {
        self.bundleID = bundleID
        self.appName = appName
    }

    // Tolerant decoding so rules saved by older versions keep loading.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try c.decode(String.self, forKey: .bundleID)
        appName = try c.decode(String.self, forKey: .appName)
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        id = v(.id, UUID())
        mode = v(.mode, .customize)
        details = v(.details, "")
        state = v(.state, "")
        largeImageURL = v(.largeImageURL, "")
        largeText = v(.largeText, "")
        clientID = v(.clientID, "")
        activityType = v(.activityType, .auto)
        buttonLabel = v(.buttonLabel, "")
        buttonURL = v(.buttonURL, "")
        conditions = v(.conditions, RuleConditions())
    }
}

struct AuraSettings: Codable, Equatable, Sendable {
    // Discord applications
    var clientID: String = ""
    var gameClientID: String = ""
    var musicClientID: String = ""
    var videoClientID: String = ""
    var codingClientID: String = ""
    var useOfficialGameIdentity = true
    var steamAccount = ""
    var preferAnimatedArtwork = false

    // Sources
    var priority: [SourceKind] = [.game, .video, .music, .app]
    var disabledSources: Set<SourceKind> = []
    var musicShowPaused = false
    var musicOtherPlayers = true

    // Content
    var language: PresenceLanguage = .fr
    var showWindowTitles = true
    var showBrowserPageTitles = false
    var readStreamingDetails = false
    var showElapsedTime = true
    var showMusicProgress = true
    var showButtons = true
    var showSmallIcon = true
    var codingLanguageIcons = true
    var iconHost = HostedIcons.defaultBase
    var showGitBranch = true
    var showRepoButton = false
    var projectRoots: [String] = GitInspector.defaultRoots
    var readWindowTitlesWithAccessibility = false

    // Idle
    var idleEnabled = true
    var idleMinutes = 5
    var idleBehavior: IdleBehavior = .away

    // Misc
    var paused = false
    var globalHotKeys = true
    var historyEnabled = true
    var autoCheckUpdates = true
    var hasLaunchedBefore = false
    var rules: [AppRule] = []
    var profiles: [PresenceProfile] = PresenceProfile.presets
    /// Focus name → profile name to activate while that Focus is on.
    var focusProfiles: [String: String] = [:]
    /// Profile restored when no Focus is active ("" = leave as is).
    var noFocusProfile = ""
    var activeProfileID: UUID? = PresenceProfile.presets.first?.id

    init() {}

    // Tolerant decoding: any key missing from an older settings file falls back to its default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AuraSettings()
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        clientID = v(.clientID, d.clientID)
        gameClientID = v(.gameClientID, d.gameClientID)
        musicClientID = v(.musicClientID, d.musicClientID)
        videoClientID = v(.videoClientID, d.videoClientID)
        codingClientID = v(.codingClientID, d.codingClientID)
        useOfficialGameIdentity = v(.useOfficialGameIdentity, d.useOfficialGameIdentity)
        steamAccount = v(.steamAccount, d.steamAccount)
        preferAnimatedArtwork = v(.preferAnimatedArtwork, d.preferAnimatedArtwork)
        priority = v(.priority, d.priority)
        for kind in SourceKind.allCases where !priority.contains(kind) { priority.append(kind) }
        disabledSources = v(.disabledSources, d.disabledSources)
        musicShowPaused = v(.musicShowPaused, d.musicShowPaused)
        musicOtherPlayers = v(.musicOtherPlayers, d.musicOtherPlayers)
        language = v(.language, d.language)
        showWindowTitles = v(.showWindowTitles, d.showWindowTitles)
        showBrowserPageTitles = v(.showBrowserPageTitles, d.showBrowserPageTitles)
        readStreamingDetails = v(.readStreamingDetails, d.readStreamingDetails)
        showElapsedTime = v(.showElapsedTime, d.showElapsedTime)
        showMusicProgress = v(.showMusicProgress, d.showMusicProgress)
        showButtons = v(.showButtons, d.showButtons)
        showSmallIcon = v(.showSmallIcon, d.showSmallIcon)
        codingLanguageIcons = v(.codingLanguageIcons, d.codingLanguageIcons)
        iconHost = v(.iconHost, d.iconHost)
        showGitBranch = v(.showGitBranch, d.showGitBranch)
        showRepoButton = v(.showRepoButton, d.showRepoButton)
        projectRoots = v(.projectRoots, d.projectRoots)
        readWindowTitlesWithAccessibility = v(.readWindowTitlesWithAccessibility, d.readWindowTitlesWithAccessibility)
        idleEnabled = v(.idleEnabled, d.idleEnabled)
        idleMinutes = v(.idleMinutes, d.idleMinutes)
        idleBehavior = v(.idleBehavior, d.idleBehavior)
        paused = v(.paused, d.paused)
        globalHotKeys = v(.globalHotKeys, d.globalHotKeys)
        historyEnabled = v(.historyEnabled, d.historyEnabled)
        autoCheckUpdates = v(.autoCheckUpdates, d.autoCheckUpdates)
        hasLaunchedBefore = v(.hasLaunchedBefore, d.hasLaunchedBefore)
        rules = v(.rules, d.rules)
        profiles = v(.profiles, d.profiles)
        focusProfiles = v(.focusProfiles, d.focusProfiles)
        noFocusProfile = v(.noFocusProfile, d.noFocusProfile)
        activeProfileID = v(.activeProfileID, d.activeProfileID)
    }

    /// First rule of the app whose conditions match (rules are evaluated in list order).
    func rule(for bundleID: String?, title: String? = nil, date: Date = Date()) -> AppRule? {
        guard let bundleID else { return nil }
        let external = RuleContext.hasExternalDisplay
        return rules.first { $0.bundleID == bundleID && $0.conditions.matches(date: date, title: title, externalDisplay: external) }
    }

    func isEnabled(_ kind: SourceKind) -> Bool { !disabledSources.contains(kind) }
}

enum AuraPaths {
    static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Aura", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

/// Observable wrapper persisting `AuraSettings` to Application Support as JSON.
@MainActor
@Observable
final class SettingsStore {
    var settings: AuraSettings {
        didSet {
            guard settings != oldValue else { return }
            scheduleSave()
            onChange?()
        }
    }

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "app.aura", category: "settings")

    private static var fileURL: URL { AuraPaths.support.appendingPathComponent("settings.json") }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode(AuraSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AuraSettings()
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = settings
        saveTask = Task { [log] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(snapshot).write(to: Self.fileURL, options: .atomic)
            } catch {
                log.error("Failed to save settings: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func upsert(_ rule: AppRule) {
        if let i = settings.rules.firstIndex(where: { $0.id == rule.id }) {
            settings.rules[i] = rule
        } else {
            settings.rules.append(rule)
        }
    }
}

enum RuleContext {
    /// True when a display other than the built-in one is connected.
    static var hasExternalDisplay: Bool {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)
        return displays.contains { CGDisplayIsBuiltin($0) == 0 }
    }
}
