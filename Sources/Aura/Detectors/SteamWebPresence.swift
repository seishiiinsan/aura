import Foundation

/// What Steam reports for the user's account: works for any device (Mac, Steam Deck, PC,
/// or a GeForce NOW cloud machine, which runs Steam with the same account).
struct SteamStatus: Equatable, Sendable {
    var gameName: String
    var appID: String
    /// Rich presence text shown on the Steam profile ("Competitive - Mirage [ 7 : 4 ]", "Chapter 3"…).
    var richPresence: String?

    var match: MatchStatus? { richPresence.flatMap(MatchStatus.parse) }
}

/// A competitive game's status parsed from Steam rich presence, e.g. CS2's
/// "Competitive - Mirage [ 7 : 4 ]" → mode "Competitive", map "Mirage", score 7–4.
struct MatchStatus: Equatable, Sendable {
    var mode: String
    var map: String?
    var score: (Int, Int)?

    static func == (a: MatchStatus, b: MatchStatus) -> Bool {
        a.mode == b.mode && a.map == b.map && a.score?.0 == b.score?.0 && a.score?.1 == b.score?.1
    }

    static func parse(_ raw: String) -> MatchStatus? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        var score: (Int, Int)?
        if let re = try? NSRegularExpression(pattern: #"[\[(]\s*(\d{1,3})\s*[:\-–]\s*(\d{1,3})\s*[\])]"#),
           let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r1 = Range(m.range(at: 1), in: text), let r2 = Range(m.range(at: 2), in: text),
           let all = Range(m.range, in: text) {
            score = (Int(text[r1]) ?? 0, Int(text[r2]) ?? 0)
            text.removeSubrange(all)
            text = text.trimmingCharacters(in: .whitespaces)
        }
        for sep in [" - ", " – ", " — ", ": ", " | "] where text.contains(sep) {
            let parts = text.components(separatedBy: sep).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if parts.count >= 2 {
                return MatchStatus(mode: parts[0], map: parts.dropFirst().joined(separator: " - "), score: score)
            }
        }
        return MatchStatus(mode: text, map: nil, score: score)
    }
}

actor SteamWebPresence {
    static let shared = SteamWebPresence()
    private var resolvedIDs: [String: String] = [:]

    /// `account` is a SteamID64 or a custom profile name ("vanity URL").
    /// Language used for rich presence texts (Steam localizes them per viewer).
    var language = "fr"
    func setLanguage(_ lang: String) { language = lang }

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
        req.setValue(language == "fr" ? "fr-FR,fr;q=0.9" : "en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        req.setValue("Steam_Language=\(language == "fr" ? "french" : "english")", forHTTPHeaderField: "Cookie")
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
