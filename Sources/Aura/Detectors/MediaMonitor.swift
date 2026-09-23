import AppKit
import Foundation
import Observation

struct NowPlaying: Equatable, Sendable {
    enum Player: String, Sendable {
        case spotify = "com.spotify.client"
        case appleMusic = "com.apple.Music"

        var name: String { self == .spotify ? "Spotify" : "Apple Music" }
    }

    var player: Player
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var position: TimeInterval
    var isPlaying: Bool
    var artworkURL: String?
    var trackURL: String?
    /// When `position` was sampled; used to extrapolate the progress bar.
    var sampledAt: Date = .now

    var trackKey: String { "\(player.rawValue)|\(title)|\(artist)|\(album)" }

    var startDate: Date { sampledAt.addingTimeInterval(-position) }
    var endDate: Date? { duration > 0 ? startDate.addingTimeInterval(duration) : nil }
}

/// Tracks what Spotify and Apple Music are playing.
///
/// Both players broadcast distributed notifications on every change; AppleScript
/// is then used for accurate position, duration and (for Spotify) artwork.
@MainActor
@Observable
final class MediaMonitor {
    private(set) var nowPlaying: NowPlaying?
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private var states: [NowPlaying.Player: NowPlaying] = [:]
    @ObservationIgnored private var lastPlayingPlayer: NowPlaying.Player?
    @ObservationIgnored private var timer: Timer?

    private static let spotifyScript = """
    tell application id "com.spotify.client"
        try
            set s to player state as string
            if s is "stopped" then return {"", "", "", "0", "", "", "0", "stopped"}
            set t to current track
            return {name of t, artist of t, album of t, (duration of t) as string, id of t, artwork url of t, (player position) as string, s}
        on error
            return {"", "", "", "0", "", "", "0", "stopped"}
        end try
    end tell
    """

    private static let musicScript = """
    tell application id "com.apple.Music"
        try
            set s to player state as string
            if s is "stopped" then return {"", "", "", "0", "", "", "0", "stopped"}
            set t to current track
            return {name of t, artist of t, album of t, (duration of t) as string, "", "", (player position) as string, s}
        on error
            return {"", "", "", "0", "", "", "0", "stopped"}
        end try
    end tell
    """

    func start() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: .init("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] note in
            let info = note.userInfo ?? [:]
            MainActor.assumeIsolated { self?.handleNotification(.spotify, info) }
        }
        center.addObserver(forName: .init("com.apple.Music.playerInfo"), object: nil, queue: .main) { [weak self] note in
            let info = note.userInfo ?? [:]
            MainActor.assumeIsolated { self?.handleNotification(.appleMusic, info) }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let self, let bundleID, let player = NowPlaying.Player(rawValue: bundleID) else { return }
                self.states[player] = nil
                self.publish()
            }
        }
        // Periodic refresh catches seeks and players started before Aura.
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAll() }
        }
        refreshAll()
    }

    private func isRunning(_ player: NowPlaying.Player) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.rawValue).isEmpty
    }

    func refreshAll() {
        for player in [NowPlaying.Player.spotify, .appleMusic] {
            if isRunning(player) { refresh(player) } else if states[player] != nil { states[player] = nil; publish() }
        }
    }

    private func handleNotification(_ player: NowPlaying.Player, _ info: [AnyHashable: Any]) {
        // Use the payload immediately so the UI reacts instantly, then refine with AppleScript.
        let state = (info["Player State"] as? String)?.lowercased() ?? ""
        if state == "stopped" {
            states[player] = nil
        } else if let name = info["Name"] as? String {
            var np = states[player] ?? NowPlaying(player: player, title: name, artist: "", album: "", duration: 0, position: 0, isPlaying: false)
            let changed = np.title != name
            np.title = name
            np.artist = info["Artist"] as? String ?? np.artist
            np.album = info["Album"] as? String ?? np.album
            np.isPlaying = state == "playing"
            if let total = (info["Total Time"] as? NSNumber) ?? (info["Duration"] as? NSNumber) {
                np.duration = total.doubleValue / 1000
            }
            if let pos = info["Playback Position"] as? NSNumber {
                np.position = pos.doubleValue
                np.sampledAt = .now
            } else if changed {
                np.position = 0
                np.sampledAt = .now
            }
            if changed { np.artworkURL = nil; np.trackURL = nil }
            if player == .spotify, let id = info["Track ID"] as? String {
                np.trackURL = Self.spotifyWebURL(id)
            }
            if let store = info["Store URL"] as? String, store.hasPrefix("http") { np.trackURL = store }
            states[player] = np
        }
        if states[player]?.isPlaying == true { lastPlayingPlayer = player }
        publish()
        refresh(player)
    }

    private func refresh(_ player: NowPlaying.Player) {
        guard isRunning(player) else { return }
        let script = player == .spotify ? Self.spotifyScript : Self.musicScript
        Task {
            guard let r = await AppleScriptRunner.shared.run(script, app: player.name), r.count >= 8 else { return }
            self.apply(player, r)
        }
    }

    private static func number(_ s: String) -> Double {
        Double(s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private static func spotifyWebURL(_ id: String) -> String? {
        // "spotify:track:4uLU6hMCjMI75M1A2tKUQC" → https://open.spotify.com/track/…
        let parts = id.split(separator: ":")
        guard parts.count == 3, parts[0] == "spotify" else { return nil }
        return "https://open.spotify.com/\(parts[1])/\(parts[2])"
    }

    private func apply(_ player: NowPlaying.Player, _ r: [String]) {
        let state = r[7].lowercased()
        guard state != "stopped", !r[0].isEmpty else {
            if states[player] != nil { states[player] = nil; publish() }
            return
        }
        var duration = Self.number(r[3])
        if player == .spotify { duration /= 1000 } // Spotify reports milliseconds
        var np = NowPlaying(
            player: player, title: r[0], artist: r[1], album: r[2], duration: duration,
            position: Self.number(r[6]), isPlaying: state == "playing"
        )
        let previous = states[player]
        if player == .spotify {
            np.artworkURL = r[5].isEmpty ? nil : r[5]
            np.trackURL = Self.spotifyWebURL(r[4])
        } else if let previous, previous.trackKey == np.trackKey {
            np.artworkURL = previous.artworkURL
            np.trackURL = previous.trackURL
        }
        // Keep sampling stable to avoid needless Discord updates.
        if let previous, previous.trackKey == np.trackKey, previous.isPlaying == np.isPlaying,
           abs(previous.startDate.timeIntervalSince(np.startDate)) < 2 {
            np.sampledAt = previous.sampledAt
            np.position = previous.position
        }
        if np.isPlaying { lastPlayingPlayer = player }
        states[player] = np
        publish()
    }

    /// Lets the engine attach resolved artwork (Apple Music) without triggering a loop.
    func attachArtwork(_ artwork: String?, trackURL: String?, for key: String) {
        for (player, var np) in states where np.trackKey == key {
            if np.artworkURL == nil { np.artworkURL = artwork }
            if np.trackURL == nil { np.trackURL = trackURL }
            states[player] = np
        }
        publish()
    }

    private func publish() {
        // Prefer whichever player is actively playing, then the most recent one.
        let playing = states.values.filter(\.isPlaying)
        let chosen: NowPlaying?
        if let last = lastPlayingPlayer, let np = states[last], np.isPlaying {
            chosen = np
        } else if let first = playing.first {
            chosen = first
        } else if let last = lastPlayingPlayer, let np = states[last] {
            chosen = np
        } else {
            chosen = states.values.first
        }
        guard chosen != nowPlaying else { return }
        nowPlaying = chosen
        onChange?()
    }
}
