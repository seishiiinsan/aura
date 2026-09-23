import Foundation

/// What Steam reports for the user's account: works for any device (Mac, Steam Deck, PC…).
struct SteamStatus: Equatable, Sendable {
    var gameName: String
    var appID: String
    /// Rich presence text shown on the Steam profile ("Competitive – Mirage", "Chapter 3"…).
    var richPresence: String?
}

actor SteamWebPresence {
    static let shared = SteamWebPresence()
    private var resolvedIDs: [String: String] = [:]

    /// `account` is a SteamID64 or a custom profile name ("vanity URL").
    func status(account: String, apiKey: String) async -> SteamStatus? {
        guard let id = await steamID64(account, apiKey: apiKey),
              let url = HTTP.url("https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/", ["key": apiKey, "steamids": id]),
              let json = await HTTP.json(url) as? [String: Any],
              let players = (json["response"] as? [String: Any])?["players"] as? [[String: Any]],
              let player = players.first,
              let name = player["gameextrainfo"] as? String,
              let appID = player["gameid"] as? String else { return nil }
        return SteamStatus(gameName: name, appID: appID, richPresence: await richPresence(steamID64: id))
    }

    private func steamID64(_ account: String, apiKey: String) async -> String? {
        let trimmed = account.trimmingCharacters(in: .whitespaces)
        if trimmed.count == 17, trimmed.allSatisfy(\.isNumber) { return trimmed }
        if let cached = resolvedIDs[trimmed] { return cached }
        guard !trimmed.isEmpty,
              let url = HTTP.url("https://api.steampowered.com/ISteamUser/ResolveVanityURL/v1/", ["key": apiKey, "vanityurl": trimmed]),
              let json = await HTTP.json(url) as? [String: Any],
              let id = (json["response"] as? [String: Any])?["steamid"] as? String else { return nil }
        resolvedIDs[trimmed] = id
        return id
    }

    /// The Steam community mini-profile exposes the rich presence string.
    private func richPresence(steamID64: String) async -> String? {
        guard let id64 = UInt64(steamID64) else { return nil }
        let accountID = id64 - 76_561_197_960_265_728
        guard let url = URL(string: "https://steamcommunity.com/miniprofile/\(accountID)"),
              var req = Optional(URLRequest(url: url)) else { return nil }
        req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, _) = try? await HTTP.session.data(for: req),
              let html = String(data: data, encoding: .utf8),
              let start = html.range(of: "<span class=\"rich_presence\">"),
              let end = html.range(of: "</span>", range: start.upperBound..<html.endIndex) else { return nil }
        let text = String(html[start.upperBound..<end.lowerBound])
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
