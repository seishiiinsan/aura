import AppKit
import Foundation
import OSLog

struct DetectedGame: Equatable, Sendable {
    var name: String
    var bundleID: String?
    var bundlePath: String?
    var pid: pid_t
    var launchDate: Date?
    var steamAppID: String?
    /// Official Discord application of this game, if Discord knows it.
    var discordAppID: String?
    var discordIconURL: String?
    var platform: String?
    /// Streaming client (GeForce NOW…) whose actual game is read from its window title.
    var isCloud = false
}

/// Discord's public catalogue of detectable games (≈25k entries).
actor DetectableGames {
    static let shared = DetectableGames()

    struct Entry: Decodable, Sendable {
        struct Executable: Decodable, Sendable { let name: String; let os: String }
        let id: String
        let name: String
        let icon_hash: String?
        let aliases: [String]?
        let executables: [Executable]?

        var iconURL: String? {
            icon_hash.map { "https://cdn.discordapp.com/app-icons/\(id)/\($0).png?size=512" }
        }
    }

    private let log = Logger(subsystem: "app.aura", category: "games")
    private var byName: [String: Entry] = [:]
    private var byDarwinExecutable: [String: Entry] = [:]
    private var byWindowsExecutable: [String: [(path: String, entry: Entry)]] = [:]

    /// Executable names too generic to identify a game on their own.
    private static let genericExecutables: Set<String> = [
        "launcher.exe", "game.exe", "start.exe", "setup.exe", "play.exe", "client.exe", "main.exe", "app.exe",
        "unitycrashhandler64.exe", "unitycrashhandler32.exe", "crashreporter.exe", "java.exe", "javaw.exe",
        "python.exe", "steam.exe", "explorer.exe", "winedevice.exe", "services.exe", "rundll32.exe",
    ]
    private var loadTask: Task<Void, Never>?
    private(set) var count = 0

    private static var cacheURL: URL { AuraPaths.support.appendingPathComponent("detectable.json") }
    private static let remote = URL(string: "https://discord.com/api/v9/applications/detectable")!

    func load() async {
        if let loadTask { return await loadTask.value }
        let task = Task { await self.performLoad() }
        loadTask = task
        await task.value
    }

    private func performLoad() async {
        let url = Self.cacheURL
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let age = (attrs?[.modificationDate] as? Date).map { Date().timeIntervalSince($0) } ?? .infinity
        if age > 7 * 86400 {
            if let (data, response) = try? await HTTP.session.data(from: Self.remote),
               (response as? HTTPURLResponse)?.statusCode == 200, data.count > 1000 {
                try? data.write(to: url, options: .atomic)
                log.info("Downloaded detectable games (\(data.count) bytes)")
            }
        }
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        index(entries)
    }

    private func index(_ entries: [Entry]) {
        for e in entries {
            let keys = [e.name] + (e.aliases ?? [])
            for key in keys {
                let k = Self.normalize(key)
                // Prefer entries that have an icon when names collide.
                if let existing = byName[k], existing.icon_hash != nil { continue }
                byName[k] = e
            }
            for exe in e.executables ?? [] {
                if exe.os == "darwin" {
                    byDarwinExecutable[exe.name.lowercased()] = e
                } else if exe.os == "win32" {
                    let path = exe.name.lowercased().replacingOccurrences(of: "\\", with: "/")
                    let base = (path as NSString).lastPathComponent
                    guard base.hasSuffix(".exe"), !Self.genericExecutables.contains(base) || path.contains("/") else { continue }
                    byWindowsExecutable[base, default: []].append((path, e))
                }
            }
        }
        count = entries.count
    }

    static func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "™", with: "")
            .replacingOccurrences(of: "®", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func match(bundlePath: String?, executableName: String?) -> Entry? {
        if let path = bundlePath?.lowercased() {
            let file = (path as NSString).lastPathComponent
            if let e = byDarwinExecutable[file] { return e }
            for (exe, e) in byDarwinExecutable where exe.contains("/") && path.hasSuffix(exe) { return e }
        }
        if let exe = executableName?.lowercased(), let e = byDarwinExecutable[">" + exe] { return e }
        return nil
    }

    func match(name: String) -> Entry? { byName[Self.normalize(name)] }

    /// Matches a Windows executable path (as seen in a Wine process' argv).
    func match(windowsPath raw: String) -> Entry? {
        let path = raw.lowercased().replacingOccurrences(of: "\\", with: "/")
        let base = (path as NSString).lastPathComponent
        guard let candidates = byWindowsExecutable[base] else { return nil }
        // Prefer entries whose relative path ("_retail_/wow.exe") matches the end of the full path.
        if let exact = candidates.first(where: { $0.path.contains("/") && path.hasSuffix($0.path) }) { return exact.entry }
        return candidates.first(where: { !$0.path.contains("/") })?.entry
    }
}

/// Decides whether a running application is a game and gathers metadata about it.
@MainActor
final class GameDetector {
    private var cache: [pid_t: DetectedGame?] = [:]
    private var steamManifests: [String: [String: (id: String, name: String)]] = [:]

    func invalidate(pid: pid_t) { cache[pid] = nil }
    func invalidateAll() { cache.removeAll() }

    func detect(_ app: NSRunningApplication, forced: Bool) async -> DetectedGame? {
        if !forced, let cached = cache[app.processIdentifier] { return cached }
        let result = await evaluate(app, forced: forced)
        cache.updateValue(result, forKey: app.processIdentifier)
        return result
    }

    private func evaluate(_ app: NSRunningApplication, forced: Bool) async -> DetectedGame? {
        let bundleID = app.bundleIdentifier
        let category = Self.cloudPlatforms[bundleID ?? ""] != nil ? .other : AppCatalog.category(for: bundleID)
        if category != .other && category != .launcher && !forced { return nil }
        if category == .launcher && !forced { return nil }
        if let bundleID, AppCatalog.ignored.contains(bundleID) { return nil }
        if let bundleID, let platform = Self.cloudPlatforms[bundleID] {
            return DetectedGame(name: platform, bundleID: bundleID, bundlePath: app.bundleURL?.path, pid: app.processIdentifier,
                                launchDate: app.launchDate, platform: platform, isCloud: true)
        }

        let path = app.bundleURL?.path
        let exeName = app.executableURL?.lastPathComponent
        let name = app.localizedName ?? exeName ?? "Jeu"
        var game = DetectedGame(name: name, bundleID: bundleID, bundlePath: path, pid: app.processIdentifier, launchDate: app.launchDate)
        var isGame = forced

        // 1. Steam library install
        if let path, let steam = steamInfo(for: path) {
            isGame = true
            game.steamAppID = steam.id
            game.name = steam.name
            game.platform = "Steam"
        }

        // 1b. Epic, Heroic, GOG and Battle.net libraries
        if !isGame, let path, let launcher = LauncherLibraries.match(path: path) {
            isGame = true
            game.name = launcher.name
            game.platform = launcher.platform
        }

        // 2. Declared category in Info.plist
        if !isGame, let url = app.bundleURL, let info = Bundle(url: url)?.infoDictionary,
           let cat = info["LSApplicationCategoryType"] as? String, cat.contains("games") {
            isGame = true
        }

        // 3. Minecraft Java & co. run as bare java processes.
        if !isGame, bundleID == nil, name.localizedCaseInsensitiveContains("minecraft") {
            isGame = true
            game.name = "Minecraft"
        }

        // 4. Discord's own list of detectable macOS executables.
        await DetectableGames.shared.load()
        var entry = await DetectableGames.shared.match(bundlePath: path, executableName: exeName)
        if entry != nil { isGame = true }

        guard isGame else { return nil }
        if entry == nil { entry = await DetectableGames.shared.match(name: game.name) }
        if let entry {
            game.discordAppID = entry.id
            game.discordIconURL = entry.iconURL
            if game.steamAppID == nil { game.name = entry.name }
        }
        return game
    }

    nonisolated static let cloudPlatforms: [String: String] = [
        "com.nvidia.gfnpc.mall": "GeForce NOW",
        "com.nvidia.geforcenow": "GeForce NOW",
        "com.blade.shadow-macos": "Shadow",
        "com.boosteroid.client": "Boosteroid",
    ]

    /// Extracts the game name from a streaming client's window title
    /// ("Cyberpunk 2077 on GeForce NOW", "GeForce NOW - Fortnite"…).
    nonisolated static func cloudGameName(fromTitle title: String, platform: String) -> String? {
        var t = title
        for noise in ["NVIDIA GeForce NOW", "GeForce NOW", platform, " on ", " sur ", "®", "™"] {
            t = t.replacingOccurrences(of: noise, with: " ", options: .caseInsensitive)
        }
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: " -–—|:•").union(.whitespaces))
        return t.count >= 2 ? t : nil
    }

    /// Detects cloud gaming sessions running in a browser tab.
    nonisolated static func browserCloudGame(url: String, title: String) -> (name: String, platform: String)? {
        guard let u = URL(string: url) else { return nil }
        let host = SiteCatalog.host(of: u)
        let path = u.pathComponents.filter { $0 != "/" }
        if host == "xbox.com", let i = path.firstIndex(of: "games"), path.contains("play"), path.count > i + 1 {
            let name = path[i + 1].split(separator: "-").map { $0.capitalized }.joined(separator: " ")
            return (name, "Xbox Cloud Gaming")
        }
        if host == "play.geforcenow.com", let name = cloudGameName(fromTitle: title, platform: "GeForce NOW") {
            return (name, "GeForce NOW")
        }
        return nil
    }

    /// Windows games running through Wine, CrossOver or Whisky.
    func scanWineGames() async -> [DetectedGame] {
        await DetectableGames.shared.load()
        let processes = await Task.detached(priority: .utility) { ProcessScanner.allProcesses() }.value
        var games: [DetectedGame] = []
        var seen = Set<String>()
        for proc in processes {
            let exe = proc.executablePath.lowercased()
            guard exe.contains("wine") || exe.contains("crossover") || exe.contains("whisky") || exe.contains("gptk") else { continue }
            guard let winPath = proc.arguments.first(where: { $0.lowercased().hasSuffix(".exe") }),
                  let entry = await DetectableGames.shared.match(windowsPath: winPath),
                  seen.insert(entry.id).inserted else { continue }
            let platform = exe.contains("crossover") ? "CrossOver" : exe.contains("whisky") ? "Whisky" : "Wine"
            games.append(DetectedGame(name: entry.name, bundleID: nil, bundlePath: winPath, pid: proc.pid,
                                      launchDate: proc.startDate, discordAppID: entry.id,
                                      discordIconURL: entry.iconURL, platform: platform))
        }
        return games
    }

    /// Resolves `…/steamapps/common/<installdir>/…` to the Steam app id and name.
    private func steamInfo(for path: String) -> (id: String, name: String)? {
        guard let range = path.range(of: "/steamapps/common/") else { return nil }
        let steamapps = String(path[..<range.lowerBound]) + "/steamapps"
        let installDir = path[range.upperBound...].split(separator: "/").first.map(String.init) ?? ""
        if steamManifests[steamapps] == nil { steamManifests[steamapps] = Self.readManifests(steamapps) }
        return steamManifests[steamapps]?[installDir.lowercased()]
    }

    private static func readManifests(_ dir: String) -> [String: (id: String, name: String)] {
        var out: [String: (id: String, name: String)] = [:]
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        for file in files where file.hasPrefix("appmanifest_") && file.hasSuffix(".acf") {
            guard let text = try? String(contentsOfFile: dir + "/" + file, encoding: .utf8) else { continue }
            func value(_ key: String) -> String? {
                let pattern = "\"\(key)\"\\s+\"([^\"]*)\""
                guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                      let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                      let r = Range(m.range(at: 1), in: text) else { return nil }
                return String(text[r])
            }
            if let id = value("appid"), let name = value("name"), let dir = value("installdir") {
                out[dir.lowercased()] = (id, name)
            }
        }
        return out
    }
}
