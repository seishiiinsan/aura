import Foundation

/// Time windows offered by the statistics.
public enum StatsPeriod: String, CaseIterable, Identifiable, Sendable {
    case today, yesterday, week, month, quarter, year, all

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .today: "Aujourd'hui"
        case .yesterday: "Hier"
        case .week: "7 jours"
        case .month: "30 jours"
        case .quarter: "90 jours"
        case .year: "12 mois"
        case .all: "Depuis le début"
        }
    }

    public func interval(now: Date = Date(), calendar: Calendar = .current, firstDate: Date? = nil) -> DateInterval {
        let startOfToday = calendar.startOfDay(for: now)
        func daysAgo(_ n: Int) -> Date { calendar.date(byAdding: .day, value: -n, to: startOfToday) ?? startOfToday }
        switch self {
        case .today: return DateInterval(start: startOfToday, end: now)
        case .yesterday: return DateInterval(start: daysAgo(1), end: startOfToday)
        case .week: return DateInterval(start: daysAgo(6), end: now)
        case .month: return DateInterval(start: daysAgo(29), end: now)
        case .quarter: return DateInterval(start: daysAgo(89), end: now)
        case .year: return DateInterval(start: daysAgo(364), end: now)
        case .all: return DateInterval(start: min(firstDate.map { calendar.startOfDay(for: $0) } ?? startOfToday, now), end: now)
        }
    }
}

public struct RankedItem: Identifiable, Hashable, Sendable {
    public var id: String { label + "|" + (subtitle ?? "") }
    public var label: String
    public var subtitle: String?
    public var image: String?
    public var seconds: TimeInterval
    public var count: Int
}

public struct TimeBucket: Identifiable, Hashable, Sendable {
    public var id: String { "\(date.timeIntervalSince1970)|\(group)" }
    public var date: Date
    public var group: String
    public var seconds: TimeInterval
}

public struct HeatCell: Identifiable, Hashable, Sendable {
    public var id: String { "\(weekday)-\(hour)" }
    /// 1 = Monday … 7 = Sunday (ISO order, friendlier for charts).
    public var weekday: Int
    public var hour: Int
    public var seconds: TimeInterval
}

/// Aggregations over a set of history sessions, clipped to an interval.
public struct Stats: Sendable {
    public let sessions: [HistorySession]
    public let interval: DateInterval
    public let calendar: Calendar

    public init(sessions: [HistorySession], interval: DateInterval, calendar: Calendar = .current) {
        self.interval = interval
        self.calendar = calendar
        self.sessions = sessions.filter { $0.duration(in: interval) > 0 }
    }

    public func filtered(_ kind: String?) -> [HistorySession] {
        guard let kind else { return sessions.filter { $0.kind != "idle" } }
        return sessions.filter { $0.kind == kind }
    }

    // MARK: Totals

    public func total(_ kind: String? = nil) -> TimeInterval {
        filtered(kind).reduce(0) { $0 + $1.duration(in: interval) }
    }

    /// Wall-clock time with at least one activity (overlapping streams counted once).
    public func activeTime() -> TimeInterval {
        let ranges = filtered(nil)
            .map { (max($0.start, interval.start), min($0.end, interval.end)) }
            .filter { $0.0 < $0.1 }
            .sorted { $0.0 < $1.0 }
        var total: TimeInterval = 0
        var current: (Date, Date)?
        for r in ranges {
            if let c = current, r.0 <= c.1 {
                current = (c.0, max(c.1, r.1))
            } else {
                if let c = current { total += c.1.timeIntervalSince(c.0) }
                current = r
            }
        }
        if let c = current { total += c.1.timeIntervalSince(c.0) }
        return total
    }

    public func count(_ kind: String? = nil) -> Int { filtered(kind).count }

    public func distinct(_ kind: String?, _ key: (HistorySession) -> String?) -> Int {
        Set(filtered(kind).compactMap(key)).count
    }

    public func averageSession(_ kind: String? = nil) -> TimeInterval {
        let list = filtered(kind)
        return list.isEmpty ? 0 : total(kind) / Double(list.count)
    }

    public func longest(_ kind: String? = nil) -> HistorySession? {
        filtered(kind).max { $0.duration(in: interval) < $1.duration(in: interval) }
    }

    // MARK: Rankings

    public func top(_ kind: String?, limit: Int = 10, label: (HistorySession) -> String?,
                    subtitle: (HistorySession) -> String? = { _ in nil }) -> [RankedItem] {
        var map: [String: RankedItem] = [:]
        for s in filtered(kind) {
            guard let l = label(s), !l.isEmpty else { continue }
            let sub = subtitle(s)
            let key = l + "|" + (sub ?? "")
            var item = map[key] ?? RankedItem(label: l, subtitle: sub, image: s.image, seconds: 0, count: 0)
            item.seconds += s.duration(in: interval)
            item.count += 1
            if item.image == nil { item.image = s.image }
            map[key] = item
        }
        return Array(map.values.sorted { $0.seconds > $1.seconds }.prefix(limit))
    }

    /// Ranking by number of sessions (e.g. track plays) rather than time.
    public func topByCount(_ kind: String?, limit: Int = 10, label: (HistorySession) -> String?,
                           subtitle: (HistorySession) -> String? = { _ in nil }) -> [RankedItem] {
        Array(top(kind, limit: .max, label: label, subtitle: subtitle).sorted { $0.count > $1.count }.prefix(limit))
    }

    // MARK: Time series

    /// Splits sessions at hour boundaries and feeds each piece to `body`.
    private func forEachHourPiece(_ kind: String?, _ body: (HistorySession, Date, TimeInterval) -> Void) {
        for s in filtered(kind) {
            var cursor = max(s.start, interval.start)
            let end = min(s.end, interval.end)
            while cursor < end {
                let hourStart = calendar.dateInterval(of: .hour, for: cursor)?.start ?? cursor
                let next = min(end, calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? end)
                body(s, hourStart, next.timeIntervalSince(cursor))
                cursor = next
            }
        }
    }

    /// Time per day (or per hour for single days), grouped by `group`.
    public func series(_ kind: String? = nil, byHour: Bool = false, group: (HistorySession) -> String = { $0.kind }) -> [TimeBucket] {
        var map: [String: TimeBucket] = [:]
        forEachHourPiece(kind) { s, hour, seconds in
            let bucketDate = byHour ? hour : calendar.startOfDay(for: hour)
            let g = group(s)
            let key = "\(bucketDate.timeIntervalSince1970)|\(g)"
            map[key, default: TimeBucket(date: bucketDate, group: g, seconds: 0)].seconds += seconds
        }
        return map.values.sorted { $0.date < $1.date }
    }

    /// Weekday × hour heat map.
    public func heatmap(_ kind: String? = nil) -> [HeatCell] {
        var grid: [Int: TimeInterval] = [:]
        forEachHourPiece(kind) { _, hour, seconds in
            let wd = calendar.component(.weekday, from: hour) // 1 = Sunday
            let iso = wd == 1 ? 7 : wd - 1
            grid[iso * 100 + calendar.component(.hour, from: hour), default: 0] += seconds
        }
        var cells: [HeatCell] = []
        for d in 1...7 { for h in 0..<24 { cells.append(HeatCell(weekday: d, hour: h, seconds: grid[d * 100 + h] ?? 0)) } }
        return cells
    }

    /// Total per hour of day (0–23).
    public func hourProfile(_ kind: String? = nil) -> [TimeBucket] {
        var hours = [TimeInterval](repeating: 0, count: 24)
        forEachHourPiece(kind) { _, hour, seconds in hours[calendar.component(.hour, from: hour)] += seconds }
        let ref = calendar.startOfDay(for: Date())
        return hours.enumerated().map { TimeBucket(date: ref.addingTimeInterval(TimeInterval($0.offset * 3600)), group: kind ?? "all", seconds: $0.element) }
    }

    /// Total per weekday (1 = Monday … 7 = Sunday).
    public func weekdayProfile(_ kind: String? = nil) -> [Int: TimeInterval] {
        var days: [Int: TimeInterval] = [:]
        forEachHourPiece(kind) { _, hour, seconds in
            let wd = calendar.component(.weekday, from: hour)
            days[wd == 1 ? 7 : wd - 1, default: 0] += seconds
        }
        return days
    }

    // MARK: Habits

    /// Days with activity in the interval.
    public func activeDays() -> Set<Date> {
        var days = Set<Date>()
        forEachHourPiece(nil) { _, hour, seconds in if seconds > 60 { days.insert(calendar.startOfDay(for: hour)) } }
        return days
    }

    /// Current and best streak of consecutive active days.
    public func streaks() -> (current: Int, best: Int) {
        let days = activeDays().sorted()
        var best = 0, run = 0
        var previous: Date?
        for d in days {
            if let p = previous, calendar.date(byAdding: .day, value: 1, to: p) == d { run += 1 } else { run = 1 }
            best = max(best, run)
            previous = d
        }
        let today = calendar.startOfDay(for: interval.end)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let current = (previous == today || previous == yesterday) ? run : 0
        return (current, best)
    }

    public func busiestDay() -> (date: Date, seconds: TimeInterval)? {
        let perDay = Dictionary(grouping: series(nil), by: \.date).mapValues { $0.reduce(0) { $0 + $1.seconds } }
        return perDay.max { $0.value < $1.value }.map { ($0.key, $0.value) }
    }

    public func peakHour(_ kind: String? = nil) -> Int? {
        let profile = hourProfile(kind)
        guard let max = profile.max(by: { $0.seconds < $1.seconds }), max.seconds > 0 else { return nil }
        return calendar.component(.hour, from: max.date)
    }

    /// Share of activity between 22:00 and 05:00.
    public func nightOwlRatio() -> Double {
        let profile = hourProfile(nil)
        let total = profile.reduce(0) { $0 + $1.seconds }
        guard total > 0 else { return 0 }
        let night = profile.enumerated().filter { $0.offset >= 22 || $0.offset < 5 }.reduce(0) { $0 + $1.element.seconds }
        return night / total
    }

    /// Average time of the first activity of each day.
    public func averageFirstActivity() -> DateComponents? {
        averageTime(of: { $0.min() })
    }

    public func averageLastActivity() -> DateComponents? {
        averageTime(of: { $0.max() })
    }

    private func averageTime(of pick: ([Date]) -> Date?) -> DateComponents? {
        let byDay = Dictionary(grouping: filtered(nil), by: { calendar.startOfDay(for: $0.start) })
        let minutes = byDay.compactMap { day, list -> Double? in
            guard let d = pick(list.map(\.start) + list.map(\.end)) else { return nil }
            return d.timeIntervalSince(day) / 60
        }
        guard !minutes.isEmpty else { return nil }
        let avg = Int(minutes.reduce(0, +) / Double(minutes.count))
        return DateComponents(hour: min(23, avg / 60), minute: avg % 60)
    }
}

public enum Format {
    /// "3 h 12 min", "45 min", "30 s".
    public static func duration(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        if s >= 3600 {
            let h = s / 3600, m = (s % 3600) / 60
            return m == 0 ? "\(h) h" : "\(h) h \(m) min"
        }
        if s >= 60 { return "\(s / 60) min" }
        return "\(s) s"
    }

    /// Compact version for charts: "3,2 h".
    public static func hours(_ t: TimeInterval) -> String {
        t >= 3600 ? String(format: "%.1f h", t / 3600).replacingOccurrences(of: ".", with: ",") : "\(Int(t / 60)) min"
    }
}
