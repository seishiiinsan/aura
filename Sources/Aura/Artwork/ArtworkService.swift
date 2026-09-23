import Foundation
import OSLog

/// Finds public, Discord-friendly image URLs for tracks, games, videos and apps.
///
/// Every lookup is memoised (including misses) so that network calls happen
/// at most once per item for the lifetime of the app.
actor ArtworkService {
    static let shared = ArtworkService()

    private let log = Logger(subsystem: "app.aura", category: "artwork")
    private var cache: [String: String?] = [:]
    private var inflight: [String: Task<String?, Never>] = [:]

    struct TrackArt: Sendable { var artwork: String?; var url: String? }
    struct VideoInfo: Sendable { var title: String?; var author: String?; var thumbnail: String? }

    private func memo(_ key: String, _ work: @escaping @Sendable () async -> String?) async -> String? {
        if let hit = cache[key] { return hit }
        if let task = inflight[key] { return await task.value }
        let task = Task { await work() }
        inflight[key] = task
        let value = await task.value
        inflight[key] = nil
        cache.updateValue(value, forKey: key)
        return value
    }

    // MARK: Music

    /// Apple Music artwork & link through the public iTunes Search API.
    func appleMusic(title: String, artist: String, album: String) async -> TrackArt {
        let key = "am|\(title)|\(artist)|\(album)"
        let packed = await memo(key) {
            let term = "\(title) \(artist)"
            guard let url = HTTP.url("https://itunes.apple.com/search", ["term": term, "entity": "song", "limit": "10"]),
                  let json = await HTTP.json(url) as? [String: Any],
                  let results = json["results"] as? [[String: Any]], !results.isEmpty else { return nil }
            let norm = { (s: String) in s.lowercased().folding(options: .diacriticInsensitive, locale: nil) }
            let best = results.first {
                norm($0["collectionName"] as? String ?? "") == norm(album) && norm($0["trackName"] as? String ?? "") == norm(title)
            } ?? results.first { norm($0["trackName"] as? String ?? "") == norm(title) } ?? results[0]
            let art = (best["artworkUrl100"] as? String)?.replacingOccurrences(of: "100x100bb", with: "600x600bb")
            let link = best["trackViewUrl"] as? String
            return [art ?? "", link ?? ""].joined(separator: "\n")
        }
        let parts = (packed ?? "").components(separatedBy: "\n")
        return TrackArt(artwork: parts.first.flatMap { $0.isEmpty ? nil : $0 },
                        url: parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil)
    }

    // MARK: Video

    func youtube(videoID: String) async -> VideoInfo {
        let packed = await memo("yt|\(videoID)") {
            let page = "https://www.youtube.com/watch?v=\(videoID)"
            guard let url = HTTP.url("https://www.youtube.com/oembed", ["url": page, "format": "json"]),
                  let json = await HTTP.json(url) as? [String: Any] else { return nil }
            return [json["title"] as? String ?? "", json["author_name"] as? String ?? ""].joined(separator: "\n")
        }
        let parts = (packed ?? "").components(separatedBy: "\n")
        return VideoInfo(
            title: parts.first.flatMap { $0.isEmpty ? nil : $0 },
            author: parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil,
            thumbnail: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg"
        )
    }

    func twitchAvatar(channel: String) async -> String? {
        // Decapi is a long-standing public helper returning the channel avatar URL as plain text.
        await memo("twitch|\(channel)") {
            guard let url = URL(string: "https://decapi.me/twitch/avatar/\(channel)"),
                  let (data, response) = try? await HTTP.session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  text.hasPrefix("https://") else { return nil }
            return text
        }
    }

    // MARK: Games

    func gameCover(_ game: DetectedGame) async -> String? {
        if let icon = game.discordIconURL { return icon }
        if let id = game.steamAppID { return await steamCover(appID: id) }
        let name = game.name
        return await memo("game|\(name)") { [self] in
            // Try the Steam store first (great artwork), then the Mac App Store.
            if let url = HTTP.url("https://store.steampowered.com/api/storesearch/", ["term": name, "cc": "US", "l": "en"]),
               let json = await HTTP.json(url) as? [String: Any],
               let items = json["items"] as? [[String: Any]],
               let item = items.first(where: { DetectableGames.normalize($0["name"] as? String ?? "") == DetectableGames.normalize(name) }),
               let id = item["id"] as? Int {
                return await self.steamCover(appID: String(id))
            }
            if let art = await self.appStoreArtwork(name: name, bundleID: game.bundleID) { return art }
            if let domain = AppCatalog.info(for: game.bundleID)?.domain { return AppCatalog.faviconURL(domain: domain) }
            return nil
        }
    }

    func steamCover(appID: String) async -> String? {
        await memo("steam|\(appID)") {
            // Portrait capsule crops best into Discord's square; fall back to the store header.
            let candidates = [
                "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/library_600x900_2x.jpg",
                "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/library_600x900.jpg",
            ]
            for candidate in candidates {
                guard let url = URL(string: candidate) else { continue }
                var req = URLRequest(url: url)
                req.httpMethod = "HEAD"
                if let (_, response) = try? await HTTP.session.data(for: req),
                   (response as? HTTPURLResponse)?.statusCode == 200 { return candidate }
            }
            if let url = HTTP.url("https://store.steampowered.com/api/appdetails", ["appids": appID, "filters": "basic"]),
               let json = await HTTP.json(url) as? [String: Any],
               let entry = json[appID] as? [String: Any], let data = entry["data"] as? [String: Any],
               let header = data["header_image"] as? String {
                return header
            }
            return "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/header.jpg"
        }
    }

    // MARK: Apps

    /// Best available icon for a macOS app: App Store artwork, then website icon.
    /// Base URL of the hosted icon set (see `HostedIcons`); empty disables it.
    private var iconHost = HostedIcons.defaultBase
    func setIconHost(_ base: String) { if base != iconHost { iconHost = base; cache = cache.filter { !$0.key.hasPrefix("app|") } } }

    func appIcon(bundleID: String?, name: String) async -> String? {
        if !iconHost.isEmpty, let hosted = await HostedIcons.shared.url(for: bundleID, base: iconHost) { return hosted }
        let key = "app|\(bundleID ?? name)"
        let domain = AppCatalog.info(for: bundleID)?.domain
        return await memo(key) { [self] in
            if let art = await self.appStoreArtwork(name: name, bundleID: bundleID) { return art }
            if let domain { return AppCatalog.faviconURL(domain: domain) }
            return nil
        }
    }

    private func appStoreArtwork(name: String, bundleID: String?) async -> String? {
        if let bundleID,
           let url = HTTP.url("https://itunes.apple.com/lookup", ["bundleId": bundleID, "entity": "macSoftware"]),
           let json = await HTTP.json(url) as? [String: Any],
           let result = (json["results"] as? [[String: Any]])?.first,
           let art = result["artworkUrl512"] as? String {
            return art
        }
        // Exact-name search as a fallback (Apple apps, Arcade games…).
        if let url = HTTP.url("https://itunes.apple.com/search", ["term": name, "entity": "macSoftware", "limit": "5"]),
           let json = await HTTP.json(url) as? [String: Any],
           let results = json["results"] as? [[String: Any]],
           let match = results.first(where: {
               ($0["trackName"] as? String)?.caseInsensitiveCompare(name) == .orderedSame
                   || ($0["bundleId"] as? String) == bundleID
           }),
           let art = match["artworkUrl512"] as? String {
            return art
        }
        return nil
    }

    func favicon(host: String) -> String { AppCatalog.faviconURL(domain: host) }

    func clear() {
        cache.removeAll()
    }
}
