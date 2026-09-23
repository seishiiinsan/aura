import AuraKit
import Foundation
import Testing

@Suite("History store, recorder and statistics")
struct HistoryTests {
    private func tempStore() -> HistoryStore {
        HistoryStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("aura-test-\(UUID().uuidString).sqlite"))
    }

    @Test func storeRoundTrip() {
        let store = tempStore()
        let now = Date()
        let id = store.insert(HistorySession(kind: "music", name: "Spotify", bundleID: "com.spotify.client", details: "Humain",
                                             state: "BEN plg", image: nil, meta: ["artist": "BEN plg"],
                                             start: now.addingTimeInterval(-120), end: now))
        #expect(id > 0)
        let loaded = store.sessions()
        #expect(loaded.count == 1)
        #expect(loaded[0].meta["artist"] == "BEN plg")
        #expect(abs(loaded[0].duration - 120) < 0.01)
    }

    @Test func recorderSplitsMergesAndDropsShortSessions() {
        let store = tempStore()
        let recorder = HistoryRecorder(store: store)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let xcode = ActivityObservation(kind: "app", name: "Xcode", details: "Édite a.swift")
        let track = ActivityObservation(kind: "music", name: "Spotify", details: "Humain")

        recorder.record(["app": xcode, "music": track], now: t0)
        recorder.record(["app": xcode, "music": track], now: t0.addingTimeInterval(60))
        // Switch app for 2 seconds (too short, dropped), then back to Xcode (merged).
        recorder.record(["app": ActivityObservation(kind: "app", name: "Finder"), "music": track], now: t0.addingTimeInterval(61))
        recorder.record(["app": xcode, "music": track], now: t0.addingTimeInterval(63))
        recorder.record(["app": xcode], now: t0.addingTimeInterval(120))
        recorder.closeAll(now: t0.addingTimeInterval(121))

        let sessions = store.sessions()
        #expect(sessions.filter { $0.name == "Finder" }.isEmpty)
        #expect(sessions.filter { $0.name == "Xcode" }.count == 1)
        #expect(sessions.filter { $0.kind == "music" }.count == 1)
    }

    @Test func statsActiveTimeCountsOverlapsOnce() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let sessions = [
            HistorySession(kind: "app", name: "Xcode", bundleID: nil, details: nil, state: nil, image: nil, meta: [:], start: t0, end: t0.addingTimeInterval(3600)),
            HistorySession(kind: "music", name: "Spotify", bundleID: nil, details: "A", state: nil, image: nil, meta: ["artist": "X"], start: t0.addingTimeInterval(1800), end: t0.addingTimeInterval(5400)),
        ]
        let stats = Stats(sessions: sessions, interval: DateInterval(start: t0, end: t0.addingTimeInterval(86_400)))
        #expect(stats.activeTime() == 5400)
        #expect(stats.total() == 7200)
        #expect(stats.total("music") == 3600)
        #expect(stats.top("music", label: { $0.meta["artist"] }).first?.label == "X")
    }

    @Test func statsClipToInterval() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let s = HistorySession(kind: "game", name: "Nine Sols", bundleID: nil, details: nil, state: nil, image: nil, meta: [:],
                               start: t0.addingTimeInterval(-600), end: t0.addingTimeInterval(600))
        let stats = Stats(sessions: [s], interval: DateInterval(start: t0, end: t0.addingTimeInterval(3600)))
        #expect(stats.total("game") == 600)
    }

    @Test func streaks() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days = [0, 1, 2, 5, 6].map { cal.date(byAdding: .day, value: -$0, to: today)!.addingTimeInterval(10 * 3600) }
        let sessions = days.map {
            HistorySession(kind: "app", name: "X", bundleID: nil, details: nil, state: nil, image: nil, meta: [:], start: $0, end: $0.addingTimeInterval(600))
        }
        let stats = Stats(sessions: sessions, interval: DateInterval(start: cal.date(byAdding: .day, value: -10, to: today)!, end: Date()))
        #expect(stats.streaks().best == 3)
    }

    @Test func formatting() {
        #expect(Format.duration(45) == "45 s")
        #expect(Format.duration(125) == "2 min")
        #expect(Format.duration(3600 * 3 + 60 * 12) == "3 h 12 min")
    }
}
