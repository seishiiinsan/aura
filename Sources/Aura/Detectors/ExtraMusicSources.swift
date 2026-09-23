import AppKit
import Foundation

/// Music playing outside Spotify / Apple Music: web players in any browser tab
/// (even in the background) and desktop apps that expose the track in their window title.
enum ExtraMusicSources {
    /// Music websites and the suffixes their tab titles carry.
    static let sites: [(host: String, name: String, domain: String)] = [
        ("music.youtube.com", "YouTube Music", "music.youtube.com"),
        ("soundcloud.com", "SoundCloud", "soundcloud.com"),
        ("deezer.com", "Deezer", "deezer.com"),
        ("open.spotify.com", "Spotify", "spotify.com"),
        ("listen.tidal.com", "TIDAL", "tidal.com"),
        ("music.apple.com", "Apple Music", "music.apple.com"),
        ("bandcamp.com", "Bandcamp", "bandcamp.com"),
        ("music.amazon.com", "Amazon Music", "music.amazon.com"),
        ("music.amazon.fr", "Amazon Music", "music.amazon.com"),
        ("radiofrance.fr", "Radio France", "radiofrance.fr"),
    ]

    /// Desktop players whose main window title is "Track - Artist" while playing.
    static let desktopApps: [String: String] = [
        "com.tidal.desktop": "TIDAL",
        "com.deezer.deezer-desktop": "Deezer",
        "com.amazon.music": "Amazon Music",
        "com.qobuz.QobuzDesktop": "Qobuz",
    ]

    private static let noise = [
        " - YouTube Music", " | Listen online for free on SoundCloud", " | SoundCloud", " - Deezer", " | Deezer",
        " | TIDAL", " - TIDAL", " – Apple Music", " - Apple Music", " on Apple Music", " | Bandcamp",
        " | Amazon Music", " - Amazon Music", " | Spotify", " - Spotify", " - Qobuz",
    ]

    struct Track: Equatable, Sendable {
        var title: String
        var artist: String
    }

    /// Extracts "track / artist" from a player's tab or window title. Returns nil when idle.
    static func parse(title raw: String, source: String) -> Track? {
        var t = raw.trimmingCharacters(in: .whitespaces)
        let playingMarkers = ["▶︎ ", "▶ ", "► "]
        let hasMarker = playingMarkers.contains { t.hasPrefix($0) }
        for m in playingMarkers where t.hasPrefix(m) { t.removeFirst(m.count) }
        for n in noise { t = t.replacingOccurrences(of: n, with: "") }
        if t.hasPrefix("Stream ") { t.removeFirst(7) }
        t = t.trimmingCharacters(in: .whitespaces)
        // SoundCloud only marks the tab while audio actually plays.
        if source == "SoundCloud", !hasMarker { return nil }
        guard !t.isEmpty, t.caseInsensitiveCompare(source) != .orderedSame,
              !t.localizedCaseInsensitiveContains("web player"),
              !t.localizedCaseInsensitiveContains("home"), !t.localizedCaseInsensitiveContains("accueil") else { return nil }

        for sep in [" • ", " · ", " — ", " – ", " - "] where t.contains(sep) {
            let parts = t.components(separatedBy: sep).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty { return Track(title: parts[0], artist: parts[1]) }
        }
        if let r = t.range(of: " by ", options: .backwards) {
            return Track(title: String(t[..<r.lowerBound]), artist: String(t[r.upperBound...]))
        }
        return nil
    }

    static func site(for url: String) -> (name: String, domain: String)? {
        guard let u = URL(string: url) else { return nil }
        let host = SiteCatalog.host(of: u)
        return sites.first { host == $0.host || host.hasSuffix("." + $0.host) }.map { ($0.name, $0.domain) }
    }

    /// Scans every tab of every running, scriptable browser.
    static func webTrack() async -> (NowPlaying, String)? {
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier, BrowserInspector.supports(id) else { continue }
            for tab in await BrowserInspector.allTabs(bundleID: id, appName: app.localizedName ?? id) {
                guard let site = site(for: tab.url), let track = parse(title: tab.title, source: site.name) else { continue }
                let np = NowPlaying(player: .web(site: site.name, domain: site.domain), title: track.title, artist: track.artist,
                                    album: "", duration: 0, position: 0, isPlaying: true, trackURL: tab.url)
                return (np, id)
            }
        }
        return nil
    }

    /// Reads the main window title of supported desktop players (needs Accessibility).
    static func desktopTrack() -> NowPlaying? {
        guard WindowInspector.isTrusted else { return nil }
        for (bundleID, name) in desktopApps {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
                  let title = WindowInspector.mainWindowTitle(pid: app.processIdentifier),
                  let track = parse(title: title, source: name) else { continue }
            return NowPlaying(player: .app(bundleID: bundleID, name: name), title: track.title, artist: track.artist,
                              album: "", duration: 0, position: 0, isPlaying: true)
        }
        return nil
    }
}
