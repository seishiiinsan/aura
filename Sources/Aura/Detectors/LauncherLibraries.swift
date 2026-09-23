import Foundation

/// Recognises games installed by other launchers from their local manifests.
///
/// - Epic Games Launcher: `…/EpicGamesLauncher/Data/Manifests/*.item`
/// - Heroic (Epic & GOG): `…/heroic/legendaryConfig/legendary/installed.json`, `…/heroic/gog_store/installed.json`
/// - GOG Galaxy: `goggame-<id>.info` files shipped inside the game
/// - Battle.net: Blizzard's standard install folders
enum LauncherLibraries {
    struct Match: Equatable, Sendable {
        var name: String
        var platform: String
    }

    private struct Install { var path: String; var name: String; var platform: String }

    nonisolated(unsafe) private static var cache: (date: Date, installs: [Install])?
    private static let lock = NSLock()

    private static var support: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    }

    private static let blizzard: [String: String] = [
        "World of Warcraft": "World of Warcraft", "Hearthstone": "Hearthstone", "Diablo III": "Diablo III",
        "Diablo IV": "Diablo IV", "StarCraft II": "StarCraft II", "StarCraft": "StarCraft: Remastered",
        "Heroes of the Storm": "Heroes of the Storm", "Overwatch": "Overwatch 2",
    ]

    /// Returns the launcher-known game containing `path`, if any.
    static func match(path: String) -> Match? {
        let lower = path.lowercased()
        for install in installs() where !install.path.isEmpty && lower.hasPrefix(install.path.lowercased()) {
            return Match(name: install.name, platform: install.platform)
        }
        if let gog = gogInfo(bundlePath: path) { return gog }
        for (folder, name) in blizzard where path.contains("/\(folder)/") {
            return Match(name: name, platform: "Battle.net")
        }
        return nil
    }

    private static func installs() -> [Install] {
        lock.lock(); defer { lock.unlock() }
        if let cache, Date().timeIntervalSince(cache.date) < 60 { return cache.installs }
        var out: [Install] = []
        out += epic()
        out += heroicLegendary()
        out += heroicGOG()
        cache = (Date(), out)
        return out
    }

    private static func json(_ url: URL) -> Any? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func epic() -> [Install] {
        let dir = support.appendingPathComponent("Epic/EpicGamesLauncher/Data/Manifests")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "item" }.compactMap { file in
            guard let obj = json(file) as? [String: Any],
                  let name = obj["DisplayName"] as? String, let path = obj["InstallLocation"] as? String else { return nil }
            return Install(path: path, name: name, platform: "Epic Games")
        }
    }

    private static func heroicLegendary() -> [Install] {
        let file = support.appendingPathComponent("heroic/legendaryConfig/legendary/installed.json")
        guard let obj = json(file) as? [String: [String: Any]] else { return [] }
        return obj.values.compactMap { game in
            guard let title = game["title"] as? String, let path = game["install_path"] as? String else { return nil }
            return Install(path: path, name: title, platform: "Epic Games")
        }
    }

    private static func heroicGOG() -> [Install] {
        let file = support.appendingPathComponent("heroic/gog_store/installed.json")
        guard let obj = json(file) as? [String: Any], let list = obj["installed"] as? [[String: Any]] else { return [] }
        return list.compactMap { game in
            guard let path = game["install_path"] as? String else { return nil }
            let name = (game["title"] as? String) ?? (path as NSString).lastPathComponent
            return Install(path: path, name: name, platform: "GOG")
        }
    }

    /// GOG games carry a `goggame-<id>.info` JSON with their name.
    private static func gogInfo(bundlePath: String) -> Match? {
        let url = URL(fileURLWithPath: bundlePath)
        for dir in [url, url.appendingPathComponent("Contents/Resources")] {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            if let info = files.first(where: { $0.hasPrefix("goggame-") && $0.hasSuffix(".info") }),
               let obj = json(dir.appendingPathComponent(info)) as? [String: Any], let name = obj["name"] as? String {
                return Match(name: name, platform: "GOG")
            }
        }
        return nil
    }
}
