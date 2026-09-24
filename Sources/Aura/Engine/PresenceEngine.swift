import AppKit
import AuraKit
import Foundation
import Observation
import OSLog

/// What Aura is currently broadcasting (or would broadcast), for the UI.
struct PresenceSnapshot: Equatable {
    var kind: SourceKind?
    var sourceApp: String
    var sourceBundleID: String?
    var clientID: String
    var presence: RichPresence
    var isIdle = false
    /// Structured facts about the activity (file, project, artist, platform…), stored in the history.
    var meta: [String: String] = [:]
}

/// Public metadata of a Discord application (name shown after "Playing").
struct DiscordAppInfo: Equatable, Sendable {
    var id: String
    var name: String
    var iconURL: String?
}

/// Orchestrates detectors → presence → Discord.
@MainActor
@Observable
final class PresenceEngine {
    let store: SettingsStore
    let media = MediaMonitor()

    private(set) var status: DiscordIPC.Status = .disconnected
    private(set) var snapshot: PresenceSnapshot?
    private(set) var lastError: String?
    private(set) var appInfo: [String: DiscordAppInfo] = [:]
    private(set) var accessibilityGranted = WindowInspector.isTrusted
    private(set) var automationDenied: Set<String> = []
    private(set) var runningGames: [DetectedGame] = []
    private(set) var lastSentAt: Date?
    private(set) var steamStatus: SteamStatus?
    /// Score read from the game's HUD on screen (CS2 on GeForce NOW).
    private(set) var liveScore: LiveScore?
    @ObservationIgnored private var liveScoreGame: String?
    /// Whether the on-screen left/right order is the reverse of "your team first" (learned from Steam).
    @ObservationIgnored private var scoreSwapped: Bool?
    private(set) var activeFocus: String?
    @ObservationIgnored private var focusChecked = false
    /// Temporary presence set from a Shortcut / URL / rule preview; wins over every source.
    private(set) var customPresence: (presence: RichPresence, until: Date)?

    @ObservationIgnored private let ipc = DiscordIPC()
    @ObservationIgnored private let games = GameDetector()
    @ObservationIgnored private let log = Logger(subsystem: "app.aura", category: "engine")
    @ObservationIgnored private var tickTimer: Timer?
    @ObservationIgnored private var recomputeTask: Task<Void, Never>?
    @ObservationIgnored private var sendTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    // Context gathered by polling
    @ObservationIgnored private var frontApp: NSRunningApplication?
    @ObservationIgnored private var focused: WindowInspector.Focused?
    @ObservationIgnored private var browserTab: BrowserInspector.Tab?
    @ObservationIgnored private var pageMedia: BrowserInspector.PageMedia?
    @ObservationIgnored private var focusSessions: [String: (start: Date, lastSeen: Date)] = [:]
    @ObservationIgnored private var videoSessions: [String: Date] = [:]
    @ObservationIgnored private var wasIdle = false
    @ObservationIgnored private var tickCount = 0
    /// Start of the last GeForce NOW session seen, to detect new ones.
    @ObservationIgnored private var lastCloudSessionStart: Date?

    // Discord output state
    @ObservationIgnored private var desired: (clientID: String, presence: RichPresence?)?
    @ObservationIgnored private var sent: (clientID: String, presence: RichPresence?)?
    @ObservationIgnored private var lastConnectAttempt = Date.distantPast

    init(store: SettingsStore) {
        self.store = store
    }

    // MARK: - Lifecycle

    func start() {
        ipc.onStatusChange = { [weak self] status in
            MainActor.assumeIsolated { self?.handle(status) }
        }
        ipc.onError = { [weak self] message in
            MainActor.assumeIsolated { self?.lastError = message }
        }
        store.onChange = { [weak self] in self?.settingsChanged() }
        media.includeOtherPlayers = store.settings.musicOtherPlayers
        configureArtwork()
        media.onChange = { [weak self] in self?.scheduleRecompute() }
        media.start()

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.frontmostChanged(app) }
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated {
                    if let app { self?.games.invalidate(pid: app.processIdentifier) }
                    Task { await self?.rescanGames() }
                }
            }
        }
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeHistory() }
        }
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconnect() }
        }

        tickTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }

        frontApp = NSWorkspace.shared.frontmostApplication
        Task {
            await DetectableGames.shared.load()
            await rescanGames()
        }
        connectIfNeeded(force: true)
        tick()
    }

    func reconnect() {
        sent = nil
        ipc.disconnect()
        connectIfNeeded(force: true)
    }

    func refreshPermissions() {
        accessibilityGranted = WindowInspector.isTrusted
        automationDenied = AppleScriptRunner.shared.deniedApps
    }

    // MARK: - Inputs

    private func frontmostChanged(_ app: NSRunningApplication?) {
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        frontApp = app
        focused = nil
        browserTab = nil
        pageMedia = nil
        touchFocusSession(for: app)
        Task { await pollContext() }
        scheduleRecompute()
    }

    private func touchFocusSession(for app: NSRunningApplication) {
        let key = app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
        let now = Date()
        // Coming back within 2 minutes keeps the timer going.
        if let s = focusSessions[key], now.timeIntervalSince(s.lastSeen) < 120 {
            focusSessions[key] = (s.start, now)
        } else {
            focusSessions[key] = (now, now)
        }
    }

    private func tick() {
        tickCount += 1
        // Wine games don't post NSWorkspace launch notifications: rescan every 15 s.
        if tickCount % 5 == 0 { Task { await rescanGames() } }
        // Steam is polled every 15 s during a game (live mode / map / score), 30 s otherwise.
        let gaming = snapshot?.kind == .game || !runningGames.isEmpty
        if tickCount % (gaming ? 5 : 10) == 1 { Task { await refreshSteam() } }
        Task { await refreshLiveScore() }
        if tickCount % 2 == 0 { checkFocus() }
        // GeForce NOW (and other launchers) publish their own, image-less Discord activity;
        // Discord shows the most recent one, so Aura re-asserts its presence regularly while they run.
        if tickCount % 40 == 0, snapshot?.kind == .game, runningGames.contains(where: \.isCloud) { reassertPresence() }
        if tickCount % 1200 == 3, store.settings.autoCheckUpdates { Updater.shared.checkIfDue() }
        refreshPermissions()
        if let app = frontApp { touchFocusSession(for: app) }
        let idle = isIdle
        if idle != wasIdle { wasIdle = idle; scheduleRecompute() }
        connectIfNeeded(force: false)
        Task {
            await pollContext()
            scheduleRecompute()
        }
    }

    private var isIdle: Bool {
        let s = store.settings
        return s.idleEnabled && IdleMonitor.idleSeconds > TimeInterval(max(1, s.idleMinutes) * 60)
    }

    /// Refreshes the focused window title and browser tab of the frontmost app.
    private func pollContext() async {
        guard let app = frontApp, let bundleID = app.bundleIdentifier else { return }
        let settings = store.settings
        if settings.readWindowTitlesWithAccessibility {
            focused = WindowInspector.focusedWindow(pid: app.processIdentifier)
        } else {
            focused = nil
        }
        if BrowserInspector.supports(bundleID), settings.isEnabled(.video) || settings.isEnabled(.app) {
            browserTab = await BrowserInspector.activeTab(bundleID: bundleID, appName: app.localizedName ?? bundleID)
            if settings.readStreamingDetails, let tab = browserTab, let site = SiteCatalog.analyze(tab.url),
               case .streaming = site.kind {
                pageMedia = await BrowserInspector.pageMedia(bundleID: bundleID, appName: app.localizedName ?? bundleID)
            } else {
                pageMedia = nil
            }
        } else if bundleID == "org.mozilla.firefox" || bundleID == "app.zen-browser.zen" {
            browserTab = nil // No AppleScript support; window title only.
        }
    }

    private func rescanGames() async {
        var found: [DetectedGame] = []
        let settings = store.settings
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let rule = settings.rule(for: app.bundleIdentifier)
            if rule?.mode == .hide { continue }
            if let game = await games.detect(app, forced: rule?.mode == .game) { found.append(game) }
        }
        for game in await games.scanWineGames() where !found.contains(where: { $0.discordAppID == game.discordAppID }) {
            found.append(game)
        }
        found.sort { ($0.launchDate ?? .distantPast) > ($1.launchDate ?? .distantPast) }
        if found != runningGames {
            runningGames = found
            scheduleRecompute()
        }
    }

    /// Pushes artwork-related settings and keys to the artwork service.
    func configureArtwork() {
        let host = store.settings.iconHost
        let animated = store.settings.preferAnimatedArtwork
        let gridKey = Keychain.get(SecretKey.steamGridDB)
        Task { await ArtworkService.shared.setIconHost(host) }
        Task { await ArtworkService.shared.configureSteamGridDB(key: gridKey, animated: animated) }
    }

    /// Switches profile when the macOS Focus changes (needs Full Disk Access).
    private func checkFocus() {
        let s = store.settings
        guard !s.focusProfiles.isEmpty || !s.noFocusProfile.isEmpty else { return }
        let focus = FocusMonitor.activeFocusName()
        guard focus != activeFocus || !focusChecked else { return }
        focusChecked = true
        activeFocus = focus
        if let focus, let profile = s.focusProfiles[focus] {
            store.activateProfile(named: profile)
        } else if focus == nil, !s.noFocusProfile.isEmpty {
            store.activateProfile(named: s.noFocusProfile)
        }
    }

    /// Reads the score from the HUD every tick while a supported game streams on GeForce NOW.
    func refreshLiveScore() async {
        guard store.settings.liveScoreFromScreen, ScreenScoreReader.hasPermission,
              let snap = snapshot, snap.kind == .game,
              let bundleID = snap.sourceBundleID, GameDetector.cloudPlatforms[bundleID] != nil,
              ScreenScoreReader.supports(game: snap.sourceApp) else {
            if liveScore != nil { liveScore = nil; scoreSwapped = nil; await ScreenScoreReader.shared.reset() }
            return
        }
        if liveScoreGame != snap.sourceApp {
            liveScoreGame = snap.sourceApp
            scoreSwapped = nil
            await ScreenScoreReader.shared.reset()
        }
        let score = await ScreenScoreReader.shared.read(bundleID: bundleID)
        if score?.left != liveScore?.left || score?.right != liveScore?.right {
            liveScore = score
            scoreRecompute()
        } else {
            liveScore = score
        }
    }

    private func scoreRecompute() { scheduleRecompute() }

    /// Score with your team first: the HUD's left/right order is matched against Steam's score once.
    private func orientedLiveScore(steam: (Int, Int)?) -> (Int, Int)? {
        guard let live = liveScore, Date().timeIntervalSince(live.readAt) < 90 else { return nil }
        if scoreSwapped == nil, let (x, y) = steam, x != y {
            if live.left == x || live.right == y { scoreSwapped = false }
            else if live.left == y || live.right == x { scoreSwapped = true }
        }
        return scoreSwapped == true ? (live.right, live.left) : (live.left, live.right)
    }

    func refreshSteam() async {
        await SteamWebPresence.shared.setLanguage(store.settings.language.rawValue)
        let account = store.settings.steamAccount
        guard !account.isEmpty, let key = Keychain.get(SecretKey.steamAPI), !key.isEmpty else {
            if steamStatus != nil { steamStatus = nil; scheduleRecompute() }
            return
        }
        let status = await SteamWebPresence.shared.status(account: account, apiKey: key)
        if status != steamStatus {
            steamStatus = status
            scheduleRecompute()
        }
    }

    private func settingsChanged() {
        media.includeOtherPlayers = store.settings.musicOtherPlayers
        configureArtwork()
        // Rules may turn apps into games or hide them.
        games.invalidateAll()
        Task { await rescanGames() }
        connectIfNeeded(force: true)
        scheduleRecompute()
    }

    // MARK: - Recompute

    func scheduleRecompute() {
        recomputeTask?.cancel()
        recomputeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            await self.recompute()
        }
    }

    private func recompute() async {
        generation += 1
        let gen = generation
        let settings = store.settings
        let result = await buildSnapshot(settings)
        guard gen == generation else { return } // a newer computation superseded this one
        if result != snapshot, ProcessInfo.processInfo.environment["AURA_DEBUG"] != nil {
            let json = result.flatMap { try? JSONSerialization.data(withJSONObject: $0.presence.jsonObject, options: [.sortedKeys]) }
            print("[\(result?.kind?.rawValue ?? "none")] \(result?.sourceApp ?? "-") →", json.flatMap { String(data: $0, encoding: .utf8) } ?? "nil")
            fflush(stdout)
        }
        snapshot = result
        if settings.paused {
            push(clientID: sent?.clientID ?? settings.clientID, presence: nil)
        } else if let result {
            push(clientID: result.clientID, presence: result.isIdle && settings.idleBehavior == .clear ? nil : result.presence)
        } else {
            push(clientID: sent?.clientID ?? settings.clientID, presence: nil)
        }
        for id in Set([result?.clientID, settings.clientID].compactMap { $0 }) where !id.isEmpty {
            await loadAppInfo(id)
        }
    }

    /// Sends a rule to Discord for a few seconds, on top of the app's current (or a generic) presence.
    func preview(_ rule: AppRule, seconds: TimeInterval = 10) {
        let t = PresenceStrings(lang: store.settings.language)
        var p: RichPresence
        if let snap = snapshot, snap.sourceBundleID == rule.bundleID {
            p = snap.presence
        } else {
            p = RichPresence(type: .playing)
            p.statusDisplay = .details
            p.details = t.using(rule.appName)
            p.largeText = rule.appName
            p.start = Date()
        }
        var client = clientID("", store.settings)
        var preview = rule
        preview.mode = .customize
        apply(preview, to: &p, clientID: &client, vars: ["app": rule.appName, "title": rule.appName])
        setCustomPresence(p, until: Date().addingTimeInterval(seconds))
        previewEndsAt = Date().addingTimeInterval(seconds)
        Task {
            try? await Task.sleep(for: .seconds(seconds + 0.2))
            self.previewEndsAt = nil
            self.scheduleRecompute()
        }
    }

    private(set) var previewEndsAt: Date?

    // MARK: - History

    @ObservationIgnored private let recorder = HistoryRecorder()

    private func recordHistory(_ drafts: [SourceKind: PresenceSnapshot], strings: PresenceStrings) {
        var observations: [String: ActivityObservation] = [:]
        for (kind, d) in drafts {
            if kind == .music, d.meta["paused"] == "1" { continue } // paused music isn't listening time
            if kind == .game, d.meta["launcher"] == "1" { continue }
            if kind == .app, isIdle { continue }
            observations[kind.rawValue] = ActivityObservation(
                kind: kind.rawValue, name: d.sourceApp, bundleID: d.sourceBundleID,
                details: d.presence.details, state: d.presence.state, image: d.presence.largeImage, meta: d.meta
            )
        }
        if isIdle {
            observations["idle"] = ActivityObservation(kind: "idle", name: strings.away())
        }
        let recorder = recorder
        Task.detached(priority: .utility) { recorder.record(observations) }
    }

    func closeHistory() {
        recorder.closeAll()
    }

    func setCustomPresence(_ presence: RichPresence?, until: Date?) {
        if let presence, let until { customPresence = (presence, until) } else { customPresence = nil }
        scheduleRecompute()
    }

    private func buildSnapshot(_ s: AuraSettings) async -> PresenceSnapshot? {
        let strings = PresenceStrings(lang: s.language)
        if let custom = customPresence {
            if custom.until > Date() {
                return PresenceSnapshot(kind: nil, sourceApp: "Aura", sourceBundleID: nil, clientID: clientID("", s), presence: custom.presence)
            }
            customPresence = nil
        }
        // Every source is evaluated so the history records parallel activities (coding while listening…).
        var drafts: [SourceKind: PresenceSnapshot] = [:]
        for kind in SourceKind.allCases where s.isEnabled(kind) || s.historyEnabled {
            let draft: PresenceSnapshot?
            switch kind {
            case .game: draft = await gameDraft(s, strings)
            case .video: draft = await videoDraft(s, strings)
            case .music: draft = await musicDraft(s, strings)
            case .app: draft = await appDraft(s, strings)
            }
            drafts[kind] = draft
        }
        if s.historyEnabled { recordHistory(drafts, strings: strings) }
        for kind in s.priority where s.isEnabled(kind) {
            if var draft = drafts[kind] {
                // Apps & websites give way to the idle state; games, music and videos don't.
                if (kind == .app) && isIdle { draft = idleDraft(s, strings) }
                return draft
            }
        }
        return isIdle ? idleDraft(s, strings) : nil
    }

    /// Discord application IDs are 17–20 digit snowflakes; anything else is ignored.
    nonisolated static func isValidClientID(_ id: String) -> Bool {
        (17...20).contains(id.count) && id.allSatisfy(\.isNumber)
    }

    private func clientID(_ override: String, _ s: AuraSettings) -> String {
        let trimmed = override.trimmingCharacters(in: .whitespaces)
        if Self.isValidClientID(trimmed) { return trimmed }
        let main = s.clientID.trimmingCharacters(in: .whitespaces)
        return Self.isValidClientID(main) ? main : ""
    }

    // MARK: Game

    private func gameDraft(_ s: AuraSettings, _ t: PresenceStrings) async -> PresenceSnapshot? {
        let frontPID = frontApp?.processIdentifier
        var game: DetectedGame
        if let native = runningGames.first(where: { $0.pid == frontPID }) ?? runningGames.first(where: { !$0.isCloud }) ?? runningGames.first {
            game = native
        } else if let steam = steamStatus {
            // Playing on another device (Steam Deck, PC, Steam Link…).
            game = DetectedGame(name: steam.gameName, pid: -1, launchDate: videoStart("steam:" + steam.appID),
                                steamAppID: steam.appID, platform: "Steam")
        } else if let tab = browserTab, let app = frontApp,
                  let cloud = GameDetector.browserCloudGame(url: tab.url, title: tab.title) {
            game = DetectedGame(name: cloud.name, bundleID: app.bundleIdentifier, pid: app.processIdentifier,
                                launchDate: videoStart("cloud:" + cloud.name), platform: cloud.platform, isCloud: true)
        } else {
            return nil
        }
        let rule = s.rule(for: game.bundleID)
        if rule?.mode == .hide { return nil }

        var cloudStart: Date?
        if game.isCloud, game.name == game.platform {
            if game.platform == "GeForce NOW", let session = GeForceNowLog.currentSession() {
                // Most reliable: GeForce NOW's own session log (no permission needed).
                game.name = session.game
                cloudStart = session.start
                if session.start != lastCloudSessionStart {
                    lastCloudSessionStart = session.start
                    competingPresenceStarted()
                }
            } else if let title = WindowInspector.focusedWindow(pid: game.pid)?.title,
                      let name = GameDetector.cloudGameName(fromTitle: title, platform: game.platform ?? "") {
                // Fallback: the streaming window's title (needs Accessibility).
                game.name = name
            }
        }
        if game.isCloud, game.name != game.platform, game.discordAppID == nil,
           let entry = await DetectableGames.shared.match(name: game.name) {
            game.name = entry.name
            game.discordAppID = entry.id
            game.discordIconURL = entry.iconURL
        }
        let inLauncher = game.isCloud && game.name == game.platform
        // Steam status of this game — matched by app id, or by name for cloud games (GeForce NOW
        // runs Steam with your account on its servers, so Steam knows the mode, map and score).
        let steam = steamStatus.flatMap { status -> SteamStatus? in
            if let id = game.steamAppID { return status.appID == id ? status : nil }
            return DetectableGames.normalize(status.gameName) == DetectableGames.normalize(game.name) ? status : nil
        }
        if game.steamAppID == nil, let steam { game.steamAppID = steam.appID }
        let steamRich = steam?.richPresence
        let match = steam?.match
        // "Compétitif · Mirage" and "7 – 4 · via GeForce NOW" when a score is known.
        let matchLine = match.map { m in [m.mode, m.map].compactMap { $0 }.joined(separator: " · ") }
        // The on-screen score is live; Steam's lags behind and is only the fallback.
        let bestScore = ScreenScoreReader.supports(game: game.name) ? (orientedLiveScore(steam: match?.score) ?? match?.score) : match?.score
        let scoreLine = bestScore.map { sc in [t.score(sc.0, sc.1), game.platform.map(t.via)].compactMap { $0 }.joined(separator: " · ") }

        let official = s.useOfficialGameIdentity ? game.discordAppID : nil
        var p = RichPresence(type: .playing)
        if official != nil {
            p.statusDisplay = .name
            p.details = matchLine ?? steamRich ?? t.inGame()
            p.state = scoreLine ?? game.platform.map(t.via)
        } else if inLauncher {
            p.statusDisplay = .details
            p.details = game.name
            p.state = t.inLibrary(game.name)
        } else {
            p.statusDisplay = .details
            p.details = matchLine.map { "\(game.name) · \($0)" } ?? game.name
            p.state = scoreLine ?? steamRich ?? game.platform.map(t.via) ?? t.inGame()
        }
        p.largeImage = await ArtworkService.shared.gameCover(game)
        p.largeText = game.name
        if s.showSmallIcon, let platform = game.platform, !inLauncher {
            let domain: String? = switch platform {
            case "Steam": "store.steampowered.com"
            case "GeForce NOW": "nvidia.com"
            case "Xbox Cloud Gaming": "xbox.com"
            case "Epic Games": "epicgames.com"
            case "GOG": "gog.com"
            case "Battle.net": "battle.net"
            case "CrossOver": "codeweavers.com"
            case "Whisky": "getwhisky.app"
            default: AppCatalog.info(for: game.bundleID)?.domain
            }
            p.smallImage = domain.map { AppCatalog.faviconURL(domain: $0) }
            p.smallText = platform
        }
        if s.showElapsedTime {
            p.start = cloudStart ?? (game.isCloud && !inLauncher ? videoStart("cloud:" + game.name) : game.launchDate)
        }
        if s.showButtons, let id = game.steamAppID {
            p.buttons = [PresenceButton(label: t.steamPage(), url: "https://store.steampowered.com/app/\(id)")]
        }
        var client = clientID(s.gameClientID, s)
        if let official { client = official }
        var gameVars = ["app": game.platform ?? game.name, "game": game.name, "status": steamRich ?? ""]
        if let match {
            gameVars["mode"] = match.mode
            gameVars["map"] = match.map ?? ""
            gameVars["score"] = bestScore.map { t.score($0.0, $0.1) } ?? ""
        }
        apply(rule, to: &p, clientID: &client, vars: gameVars)
        var meta = gameVars
        meta["platform"] = game.platform ?? "macOS"
        if let id = game.steamAppID { meta["steamAppID"] = id }
        if inLauncher { meta["launcher"] = "1" }
        return PresenceSnapshot(kind: .game, sourceApp: game.name, sourceBundleID: game.bundleID, clientID: client, presence: p, meta: meta)
    }

    // MARK: Music

    private func musicDraft(_ s: AuraSettings, _ t: PresenceStrings) async -> PresenceSnapshot? {
        guard var np = media.nowPlaying, np.isPlaying || s.musicShowPaused else { return nil }
        let rule = s.rule(for: np.player.bundleID)
        if rule?.mode == .hide { return nil }

        if np.player != .spotify, np.artworkURL == nil {
            let art = await ArtworkService.shared.appleMusic(title: np.title, artist: np.artist, album: np.album)
            np.artworkURL = art.artwork
            np.trackURL = np.trackURL ?? art.url
            media.attachArtwork(art.artwork, trackURL: art.url, for: np.trackKey)
        }

        var p = RichPresence(type: .listening)
        p.statusDisplay = .details
        p.details = np.title
        p.state = np.artist.isEmpty ? nil : np.artist
        if let art = np.artworkURL {
            p.largeImage = art
        } else {
            p.largeImage = await ArtworkService.shared.appIcon(bundleID: np.player.bundleID, name: np.player.name)
        }
        p.largeText = np.album.isEmpty ? np.title : np.album
        if s.showSmallIcon {
            p.smallImage = AppCatalog.faviconURL(domain: np.player.domain)
            p.smallText = np.isPlaying ? np.player.name : "\(np.player.name) — \(t.paused())"
        }
        if np.isPlaying, s.showMusicProgress {
            p.start = np.startDate
            p.end = np.endDate
        }
        if s.showButtons, let url = np.trackURL {
            let label = switch np.player {
            case .spotify: t.listenOnSpotify()
            case .appleMusic: t.listenOnAppleMusic()
            default: t.listenOn(np.player.name)
            }
            p.buttons = [PresenceButton(label: label, url: url)]
        }
        var client = clientID(s.musicClientID, s)
        let musicVars = ["app": np.player.name, "track": np.title, "artist": np.artist, "album": np.album, "title": np.title]
        apply(rule, to: &p, clientID: &client, vars: musicVars)
        var meta = musicVars
        meta["player"] = np.player.name
        if !np.isPlaying { meta["paused"] = "1" }
        if np.duration > 0 { meta["duration"] = String(Int(np.duration)) }
        return PresenceSnapshot(kind: .music, sourceApp: np.player.name, sourceBundleID: np.player.bundleID, clientID: client, presence: p, meta: meta)
    }

    // MARK: Video

    private static let mediaPlayers: Set<String> = [
        "com.colliderli.iina", "org.videolan.vlc", "com.apple.QuickTimePlayerX", "com.apple.TV",
    ]

    private func videoDraft(_ s: AuraSettings, _ t: PresenceStrings) async -> PresenceSnapshot? {
        guard let app = frontApp, let bundleID = app.bundleIdentifier else { return nil }
        let rule = s.rule(for: bundleID, title: focused?.title ?? browserTab?.title)
        if rule?.mode == .hide { return nil }
        let appName = app.localizedName ?? bundleID
        var p = RichPresence(type: .watching)
        p.statusDisplay = .details
        var client = clientID(s.videoClientID, s)
        var vars = ["app": appName]

        if Self.mediaPlayers.contains(bundleID) {
            guard let title = focused?.title ?? focused?.documentPath.map({ ($0 as NSString).lastPathComponent }) else { return nil }
            let clean = (title as NSString).deletingPathExtension
            p.details = s.showWindowTitles ? clean : t.watching()
            p.state = appName
            p.largeImage = await ArtworkService.shared.appIcon(bundleID: bundleID, name: appName)
            p.largeText = appName
            vars["title"] = clean
            if s.showElapsedTime { p.start = videoStart(bundleID + title) }
        } else if let tab = browserTab, let site = SiteCatalog.analyze(tab.url) {
            vars["site"] = site.displayName
            vars["title"] = tab.title
            switch site.kind {
            case .youtube(let id):
                let info = await ArtworkService.shared.youtube(videoID: id)
                let tabTitle = tab.title.replacingOccurrences(of: " - YouTube", with: "")
                p.details = info.title ?? tabTitle
                p.state = info.author.map { t.by($0) } ?? "YouTube"
                p.largeImage = info.thumbnail
                p.largeText = info.title ?? "YouTube"
                if s.showSmallIcon {
                    p.smallImage = AppCatalog.faviconURL(domain: "youtube.com")
                    p.smallText = "YouTube"
                }
                if s.showButtons { p.buttons = [PresenceButton(label: t.watchOnYouTube(), url: "https://www.youtube.com/watch?v=\(id)")] }
                if s.showElapsedTime { p.start = videoStart("yt:" + id) }
                vars["title"] = p.details
            case .youtubeMusic:
                p.type = .listening
                let raw = tab.title.replacingOccurrences(of: " - YouTube Music", with: "")
                let parts = raw.components(separatedBy: " • ")
                guard raw != "YouTube Music" else { return nil }
                p.details = parts.first
                p.state = parts.count > 1 ? parts[1] : "YouTube Music"
                p.largeImage = AppCatalog.faviconURL(domain: "music.youtube.com")
                p.largeText = "YouTube Music"
                if s.showElapsedTime { p.start = videoStart("ytm:" + raw) }
                client = clientID(s.musicClientID, s)
            case .twitch(let channel):
                p.details = t.liveOn(channel)
                let title = tab.title.replacingOccurrences(of: " - Twitch", with: "")
                p.state = title.caseInsensitiveCompare(channel) == .orderedSame ? t.onTwitch() : title
                let avatar = await ArtworkService.shared.twitchAvatar(channel: channel)
                p.largeImage = avatar ?? AppCatalog.faviconURL(domain: "twitch.tv")
                p.largeText = channel
                if s.showSmallIcon {
                    p.smallImage = AppCatalog.faviconURL(domain: "twitch.tv")
                    p.smallText = "Twitch"
                }
                if s.showButtons { p.buttons = [PresenceButton(label: t.watchOnTwitch(), url: "https://www.twitch.tv/\(channel)")] }
                if s.showElapsedTime { p.start = videoStart("tw:" + channel) }
            case .streaming(let service):
                if let media = pageMedia, let title = media.title {
                    // Title, episode, poster and progress read from the player.
                    p.details = title
                    p.state = media.subtitle ?? t.watchingOn(service)
                    p.largeImage = media.artwork ?? AppCatalog.faviconURL(domain: site.host)
                    p.largeText = media.subtitle.map { "\(title) · \($0)" } ?? title
                    if s.showSmallIcon {
                        p.smallImage = AppCatalog.faviconURL(domain: site.host)
                        p.smallText = media.paused == true ? "\(service) — \(t.paused())" : service
                    }
                    if media.paused != true, let cur = media.currentTime, let dur = media.duration, dur > 0 {
                        let start = Date().addingTimeInterval(-cur)
                        p.start = start
                        p.end = start.addingTimeInterval(dur)
                    } else if s.showElapsedTime {
                        p.start = videoStart("st:" + service)
                    }
                    vars["title"] = title
                } else {
                    p.details = t.watchingOn(service)
                    if s.showBrowserPageTitles {
                        let title = tab.title.components(separatedBy: " | ").first ?? tab.title
                        if title.caseInsensitiveCompare(service) != .orderedSame { p.state = title }
                    }
                    p.largeImage = AppCatalog.faviconURL(domain: site.host)
                    p.largeText = service
                    if s.showElapsedTime { p.start = videoStart("st:" + service) }
                }
            case .github, .generic:
                return nil
            }
        } else {
            return nil
        }
        apply(rule, to: &p, clientID: &client, vars: vars)
        var meta = vars
        if let state = p.state { meta["channel"] = state }
        return PresenceSnapshot(kind: .video, sourceApp: vars["site"] ?? appName, sourceBundleID: bundleID, clientID: client, presence: p, meta: meta)
    }

    private func videoStart(_ key: String) -> Date {
        if let d = videoSessions[key] { return d }
        let now = Date()
        videoSessions[key] = now
        if videoSessions.count > 50 { videoSessions = [key: now] }
        return now
    }

    // MARK: Focused app

    private func appDraft(_ s: AuraSettings, _ t: PresenceStrings) async -> PresenceSnapshot? {
        guard let app = frontApp else { return nil }
        let bundleID = app.bundleIdentifier
        if let bundleID, AppCatalog.ignored.contains(bundleID) { return nil }
        let rule = s.rule(for: bundleID, title: focused?.title ?? browserTab?.title)
        if rule?.mode == .hide { return nil }
        let name = app.localizedName ?? bundleID ?? "App"
        let category = AppCatalog.category(for: bundleID)
        let title = s.showWindowTitles ? focused?.title : nil
        var vars = ["app": name, "title": title ?? ""]

        var p = RichPresence(type: .playing)
        p.statusDisplay = .details
        p.largeText = name
        var client = clientID("", s)

        switch category {
        case .coding:
            client = clientID(s.codingClientID, s)
            var file: String?, project: String?
            if let path = focused?.documentPath { file = (path as NSString).lastPathComponent }
            if let title = focused?.title {
                let parsed = WindowTitleParser.editor(title: title, appName: name, bundleID: bundleID)
                file = file ?? parsed.file
                project = parsed.project
            }
            if !s.showWindowTitles { file = nil; project = nil }
            p.details = file.map(t.editing) ?? t.codingIn(name)
            p.state = project.map(t.project) ?? (file != nil ? t.workspace(name) : nil)
            vars["file"] = file ?? ""
            vars["project"] = project ?? ""
            if s.showGitBranch || s.showRepoButton {
                let repo = focused?.documentPath.flatMap(GitInspector.repository(containing:))
                    ?? project.flatMap { GitInspector.repository(named: $0, roots: s.projectRoots) }
                if let repo, let git = GitInspector.info(repo: repo) {
                    vars["branch"] = git.branch
                    if project == nil { project = repo.lastPathComponent }
                    if s.showGitBranch {
                        p.state = "\(project.map(t.project) ?? t.workspace(name)) · \(git.branch)"
                    }
                    if s.showRepoButton, s.showButtons, let gh = git.githubRepo {
                        p.buttons = [PresenceButton(label: t.viewOnGitHub(), url: "https://github.com/\(gh)")]
                    }
                }
            }
            if s.codingLanguageIcons, let file, let language = Languages.language(forFile: file) {
                // vscord style: language as the big picture, editor as the badge.
                p.largeImage = language.iconURL
                p.largeText = language.name
                p.smallImage = await ArtworkService.shared.appIcon(bundleID: bundleID, name: name)
                p.smallText = name
                vars["language"] = language.name
            }
        case .terminal:
            p.details = t.inTerminal()
            p.state = name
        case .design:
            p.details = t.designingIn(name)
            p.state = title.flatMap { WindowTitleParser.parts($0).first }
        case .creative:
            p.details = t.editingVideo(name)
            p.state = title.flatMap { WindowTitleParser.parts($0).first }
        case .audio:
            p.details = t.producing(name)
            p.state = title.flatMap { WindowTitleParser.parts($0).first }
        case .communication:
            p.details = t.chattingOn(name)
        case .office:
            p.details = t.writingIn(name)
            p.state = title.flatMap { WindowTitleParser.parts($0).first }
        case .notes:
            p.details = t.notesIn(name)
        case .ai:
            p.details = t.askingAI(name)
        case .files:
            p.details = t.browsingFiles()
            p.state = title
        case .launcher:
            p.details = t.inLibrary(name)
        case .browser:
            if let tab = browserTab, let site = SiteCatalog.analyze(tab.url) {
                p.details = t.browsing(site.displayName)
                vars["site"] = site.displayName
                vars["title"] = tab.title
                if case .github(let repo?) = site.kind {
                    p.state = t.repo(repo)
                    if s.showButtons { p.buttons = [PresenceButton(label: t.viewOnGitHub(), url: "https://github.com/\(repo)")] }
                } else if s.showBrowserPageTitles {
                    p.state = tab.title
                }
                p.largeImage = AppCatalog.faviconURL(domain: site.host)
                p.largeText = site.displayName
                if s.showSmallIcon {
                    p.smallImage = await ArtworkService.shared.appIcon(bundleID: bundleID, name: name)
                    p.smallText = name
                }
            } else {
                p.details = t.browsingWeb()
                p.state = name
            }
        case .media:
            p.details = t.using(name)
        case .music, .system, .other:
            p.details = t.using(name)
        }

        if p.largeImage == nil {
            p.largeImage = await ArtworkService.shared.appIcon(bundleID: bundleID, name: name)
        }
        if s.showElapsedTime {
            p.start = focusSessions[bundleID ?? "pid:\(app.processIdentifier)"]?.start
        }
        apply(rule, to: &p, clientID: &client, vars: vars)
        vars["category"] = category.rawValue
        return PresenceSnapshot(kind: .app, sourceApp: name, sourceBundleID: bundleID, clientID: client, presence: p, meta: vars)
    }

    private func idleDraft(_ s: AuraSettings, _ t: PresenceStrings) -> PresenceSnapshot {
        var p = RichPresence(type: .playing)
        p.statusDisplay = .details
        p.details = t.away()
        p.state = t.onMac()
        if s.showElapsedTime { p.start = Date().addingTimeInterval(-IdleMonitor.idleSeconds) }
        return PresenceSnapshot(kind: nil, sourceApp: t.away(), sourceBundleID: nil, clientID: clientID("", s), presence: p, isIdle: true)
    }

    /// Applies a user rule on top of the automatic presence.
    private func apply(_ rule: AppRule?, to p: inout RichPresence, clientID: inout String, vars: [String: String]) {
        guard let rule, rule.mode != .hide else { return }
        var values = vars
        values["details"] = p.details ?? ""
        values["state"] = p.state ?? ""
        if !rule.details.isEmpty { p.details = Template.render(rule.details, values) }
        if !rule.state.isEmpty { p.state = Template.render(rule.state, values) }
        if !rule.largeImageURL.isEmpty { p.largeImage = rule.largeImageURL }
        if !rule.largeText.isEmpty { p.largeText = Template.render(rule.largeText, values) }
        if let type = rule.activityType.type { p.type = type }
        if !rule.buttonLabel.isEmpty, !rule.buttonURL.isEmpty {
            p.buttons = [PresenceButton(label: Template.render(rule.buttonLabel, values), url: rule.buttonURL)] + p.buttons
        }
        let custom = rule.clientID.trimmingCharacters(in: .whitespaces)
        if Self.isValidClientID(custom) { clientID = custom }
    }

    // MARK: - Discord output

    private func handle(_ status: DiscordIPC.Status) {
        self.status = status
        switch status {
        case .connected:
            lastError = nil
            sent = (ipc.clientID ?? "", nil)
            flush()
        case .disconnected, .failed:
            sent = nil
        case .connecting:
            break
        }
    }

    private func connectIfNeeded(force: Bool) {
        let settings = store.settings
        let target = desired?.clientID ?? settings.clientID
        guard Self.isValidClientID(target) else {
            if case .connected = status { ipc.disconnect() }
            return
        }
        let isConnectedToTarget: Bool = {
            if case .connected = status { return ipc.clientID == target }
            return false
        }()
        if isConnectedToTarget { return }
        if case .connecting = status, !force { return }
        // Back off between attempts when Discord isn't running.
        guard force || Date().timeIntervalSince(lastConnectAttempt) > 10 else { return }
        lastConnectAttempt = Date()
        ipc.connect(clientID: target)
    }

    private func push(clientID: String, presence: RichPresence?) {
        guard Self.isValidClientID(clientID) else { return }
        desired = (clientID, presence)
        if ipc.clientID != clientID || { if case .connected = status { return false }; return true }() {
            if ipc.clientID != clientID {
                // Switching identity: clear the old activity, then reconnect.
                if case .connected = status { ipc.setActivity(nil) }
                sent = nil
                lastConnectAttempt = .distantPast
                ipc.connect(clientID: clientID)
            }
            return
        }
        flush()
    }

    /// A launcher just published its own activity: send ours again right after it, so Discord shows Aura's.
    private func competingPresenceStarted() {
        for delay in [6.0, 20.0, 45.0] {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                self?.reassertPresence()
            }
        }
    }

    /// Re-sends the current activity even if unchanged, making it Discord's most recent one.
    func reassertPresence() {
        guard let desired, desired.presence != nil, case .connected = status, ipc.clientID == desired.clientID else { return }
        sent = (desired.clientID, nil)
        flush()
    }

    /// Sends the desired presence, at most once every 2 seconds (Discord allows 5 / 20 s).
    private func flush() {
        guard let desired, case .connected = status, ipc.clientID == desired.clientID else { return }
        if let sent, sent.clientID == desired.clientID {
            switch (sent.presence, desired.presence) {
            case (nil, nil): return
            case let (a?, b?) where b.isSimilar(to: a): return
            default: break
            }
        }
        let wait = lastSentAt.map { max(0, 2 - Date().timeIntervalSince($0)) } ?? 0
        sendTask?.cancel()
        sendTask = Task { [weak self] in
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled, let self, let desired = self.desired, desired.clientID == self.ipc.clientID else { return }
            self.ipc.setActivity(desired.presence)
            self.sent = desired
            self.lastSentAt = Date()
        }
    }

    // MARK: - Discord application metadata

    func loadAppInfo(_ id: String) async {
        guard appInfo[id] == nil, id.allSatisfy(\.isNumber), id.count >= 15 else { return }
        guard let url = URL(string: "https://discord.com/api/v9/applications/\(id)/rpc"),
              let json = await HTTP.json(url) as? [String: Any], let name = json["name"] as? String else { return }
        let icon = (json["icon"] as? String).map { "https://cdn.discordapp.com/app-icons/\(id)/\($0).png?size=256" }
        appInfo[id] = DiscordAppInfo(id: id, name: name, iconURL: icon)
    }

    func stop() {
        recorder.closeAll()
        ipc.setActivity(nil)
        ipc.disconnect()
    }
}
