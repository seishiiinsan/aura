import Foundation

/// Discord activity types supported over RPC.
enum ActivityType: Int, Codable, CaseIterable, Sendable {
    case playing = 0
    case listening = 2
    case watching = 3
    case competing = 5

    var label: String {
        switch self {
        case .playing: "Joue à"
        case .listening: "Écoute"
        case .watching: "Regarde"
        case .competing: "En compétition sur"
        }
    }
}

/// Which field Discord shows next to the user's name in the member list.
enum StatusDisplayType: Int, Codable, Sendable {
    case name = 0
    case state = 1
    case details = 2
}

struct PresenceButton: Codable, Hashable, Sendable {
    var label: String
    var url: String
}

/// A fully resolved activity, ready to be sent to Discord.
struct RichPresence: Equatable, Sendable {
    var type: ActivityType = .playing
    var statusDisplay: StatusDisplayType?
    var details: String?
    var state: String?
    var start: Date?
    var end: Date?
    var largeImage: String?
    var largeText: String?
    var smallImage: String?
    var smallText: String?
    var buttons: [PresenceButton] = []

    /// Discord requires 2...128 characters for text fields.
    private static func clamp(_ s: String?, max: Int = 128) -> String? {
        guard var s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if s.count > max { s = String(s.prefix(max - 1)) + "…" }
        if s.count < 2 { s += " " + "\u{200B}" }
        return s
    }

    private static func validURL(_ s: String?) -> String? {
        guard let s, s.count <= 512, let url = URL(string: s), url.scheme == "https" || url.scheme == "http" else { return nil }
        return s
    }

    private static func imageKey(_ s: String?) -> String? {
        guard let s, !s.isEmpty, s.count <= 300 else { return nil }
        return s
    }

    var jsonObject: [String: Any] {
        var obj: [String: Any] = ["type": type.rawValue, "instance": false]
        if let statusDisplay { obj["status_display_type"] = statusDisplay.rawValue }
        if let d = Self.clamp(details) { obj["details"] = d }
        if let s = Self.clamp(state) { obj["state"] = s }

        var ts: [String: Any] = [:]
        if let start { ts["start"] = Int64(start.timeIntervalSince1970 * 1000) }
        if let end { ts["end"] = Int64(end.timeIntervalSince1970 * 1000) }
        if !ts.isEmpty { obj["timestamps"] = ts }

        var assets: [String: Any] = [:]
        if let l = Self.imageKey(largeImage) {
            assets["large_image"] = l
            if let t = Self.clamp(largeText) { assets["large_text"] = t }
        }
        if let s = Self.imageKey(smallImage) {
            assets["small_image"] = s
            if let t = Self.clamp(smallText) { assets["small_text"] = t }
        }
        if !assets.isEmpty { obj["assets"] = assets }

        let btns = buttons.prefix(2).compactMap { b -> [String: String]? in
            guard let url = Self.validURL(b.url), let label = Self.clamp(b.label, max: 32) else { return nil }
            return ["label": label, "url": url]
        }
        if !btns.isEmpty { obj["buttons"] = btns }
        return obj
    }

    /// Equality that ignores sub-second timestamp jitter, used to avoid spamming Discord.
    func isSimilar(to other: RichPresence?) -> Bool {
        guard let other else { return false }
        func close(_ a: Date?, _ b: Date?) -> Bool {
            switch (a, b) {
            case (nil, nil): true
            case let (a?, b?): abs(a.timeIntervalSince(b)) < 3
            default: false
            }
        }
        var a = self, b = other
        guard close(a.start, b.start), close(a.end, b.end) else { return false }
        a.start = nil; a.end = nil; b.start = nil; b.end = nil
        return a == b
    }
}
