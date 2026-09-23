import AuraKit
import Foundation
import Observation
import SwiftUI

typealias ViewState<Value> = SwiftUI.State<Value>

/// Loads the history for the selected period and exposes the statistics.
@MainActor
@Observable
final class InsightsModel {
    var period: StatsPeriod = .week { didSet { reload() } }
    private(set) var stats = Stats(sessions: [], interval: DateInterval(start: .now, end: .now))
    /// Same-length period just before, to show trends.
    private(set) var previous = Stats(sessions: [], interval: DateInterval(start: .now, end: .now))
    private(set) var lastUpdate = Date()
    private(set) var firstDate: Date?
    private(set) var allTimeCount = 0

    @ObservationIgnored private let store = HistoryStore.shared
    @ObservationIgnored private var timer: Timer?

    init() {
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    func reload() {
        firstDate = store.firstSessionDate
        let interval = period.interval(firstDate: firstDate)
        stats = Stats(sessions: store.sessions(from: interval.start, to: interval.end), interval: interval)
        let prevInterval = DateInterval(start: interval.start.addingTimeInterval(-interval.duration), end: interval.start)
        previous = Stats(sessions: store.sessions(from: prevInterval.start, to: prevInterval.end), interval: prevInterval)
        lastUpdate = Date()
    }

    /// Sessions of a single day, for the timeline.
    func sessions(on day: Date) -> [HistorySession] {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return store.sessions(from: start, to: end)
    }

    var isSingleDay: Bool { period == .today || period == .yesterday }

    // MARK: Data management

    func exportJSON() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(store.sessions())
    }

    func exportCSV() -> Data {
        let iso = ISO8601DateFormatter()
        func esc(_ s: String?) -> String { "\"" + (s ?? "").replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var lines = ["kind,name,bundle_id,details,state,start,end,duration_s,meta"]
        for s in store.sessions() {
            let meta = s.meta.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
            lines.append([esc(s.kind), esc(s.name), esc(s.bundleID), esc(s.details), esc(s.state),
                          iso.string(from: s.start), iso.string(from: s.end), String(Int(s.duration)), esc(meta)].joined(separator: ","))
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    func deleteAll() {
        store.deleteAll()
        reload()
    }

    func delete(from: Date, to: Date) {
        store.delete(from: from, to: to)
        reload()
    }

    var databaseSize: Int64 { store.fileSize }
}

// MARK: - Presentation helpers

enum Kind {
    static let all = ["game", "music", "video", "app"]

    static func title(_ kind: String) -> String {
        switch kind {
        case "game": "Jeux"
        case "music": "Musique"
        case "video": "Vidéos"
        case "app": "Apps"
        case "idle": "Absent"
        default: kind
        }
    }

    static func color(_ kind: String) -> Color {
        switch kind {
        case "game": .green
        case "music": .pink
        case "video": .red
        case "app": .blue
        default: .gray
        }
    }

    static func symbol(_ kind: String) -> String {
        switch kind {
        case "game": "gamecontroller.fill"
        case "music": "music.note"
        case "video": "play.tv.fill"
        case "app": "macwindow"
        default: "moon.zzz.fill"
        }
    }

    static let categoryTitles: [String: String] = [
        "coding": "Code", "terminal": "Terminal", "design": "Design", "creative": "Montage & 3D", "audio": "MAO",
        "browser": "Web", "communication": "Messagerie", "office": "Bureautique", "notes": "Notes", "ai": "IA",
        "media": "Vidéo", "music": "Musique", "launcher": "Launchers", "files": "Fichiers", "system": "Système", "other": "Autre",
    ]
}

extension Double {
    var hoursValue: Double { self / 3600 }
}
