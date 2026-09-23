import Foundation

/// What is happening right now on one stream (games, music, videos, focused app, idle).
public struct ActivityObservation: Equatable, Sendable {
    public var kind: String
    public var name: String
    public var bundleID: String?
    public var details: String?
    public var state: String?
    public var image: String?
    public var meta: [String: String]

    public init(kind: String, name: String, bundleID: String? = nil, details: String? = nil, state: String? = nil,
                image: String? = nil, meta: [String: String] = [:]) {
        self.kind = kind; self.name = name; self.bundleID = bundleID; self.details = details
        self.state = state; self.image = image; self.meta = meta
    }

    /// Identity of a session: a change of key starts a new session.
    var key: String { "\(kind)|\(name)|\(details ?? "")" }
}

/// Turns a stream of observations into sessions in the history store.
///
/// Several streams run in parallel (you can code while listening to music), each
/// with at most one open session. Short gaps (< 60 s) on the same activity are merged.
public final class HistoryRecorder: @unchecked Sendable {
    private struct Open {
        var id: Int64
        var key: String
        var start: Date
        var lastWrite: Date
        var lastSeen: Date
        var state: String?
        var image: String?
    }

    private let store: HistoryStore
    private var open: [String: Open] = [:]
    private var recentlyClosed: [String: Open] = [:]
    private let lock = NSLock()

    /// Sessions shorter than this are discarded.
    public var minimumDuration: TimeInterval = 5
    /// Writes of an ongoing session are throttled to this interval.
    public var writeInterval: TimeInterval = 30
    public var mergeGap: TimeInterval = 60

    public init(store: HistoryStore = .shared) {
        self.store = store
    }

    /// Reports the current observation of each stream. Streams absent from `observations` are closed.
    public func record(_ observations: [String: ActivityObservation], now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        for (stream, current) in open where observations[stream]?.key != current.key {
            close(stream: stream, at: now)
        }
        for (stream, obs) in observations {
            if var current = open[stream] {
                current.lastSeen = now
                let changed = obs.state != current.state || obs.image != current.image
                if changed || now.timeIntervalSince(current.lastWrite) >= writeInterval {
                    store.update(id: current.id, end: now, state: changed ? obs.state : nil, image: changed ? obs.image : nil)
                    current.lastWrite = now
                    current.state = obs.state
                    current.image = obs.image
                }
                open[stream] = current
            } else if let recent = recentlyClosed[stream], recent.key == obs.key, now.timeIntervalSince(recent.lastSeen) < mergeGap {
                // Same activity resumed quickly: continue the previous session.
                var resumed = recent
                resumed.lastSeen = now
                resumed.lastWrite = now
                store.update(id: resumed.id, end: now)
                open[stream] = resumed
                recentlyClosed[stream] = nil
            } else {
                let session = HistorySession(kind: obs.kind, name: obs.name, bundleID: obs.bundleID, details: obs.details,
                                             state: obs.state, image: obs.image, meta: obs.meta, start: now, end: now)
                let id = store.insert(session)
                guard id != 0 else { continue }
                open[stream] = Open(id: id, key: obs.key, start: now, lastWrite: now, lastSeen: now, state: obs.state, image: obs.image)
            }
        }
    }

    /// Closes every open session (pause, sleep, quit).
    public func closeAll(now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        for stream in open.keys { close(stream: stream, at: now) }
    }

    private func close(stream: String, at now: Date) {
        guard let current = open.removeValue(forKey: stream) else { return }
        let end = min(now, current.lastSeen.addingTimeInterval(10))
        if end.timeIntervalSince(current.start) < minimumDuration {
            store.delete(id: current.id)
            return
        }
        store.update(id: current.id, end: end)
        var closed = current
        closed.lastSeen = end
        recentlyClosed[stream] = closed
    }
}
