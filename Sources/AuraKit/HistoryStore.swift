import Foundation
import SQLite3

/// One continuous activity: a track, a game session, a file edited in an app, a video…
public struct HistorySession: Identifiable, Hashable, Sendable, Codable {
    public var id: Int64
    /// "game", "music", "video", "app" or "idle".
    public var kind: String
    /// App, game or player name.
    public var name: String
    public var bundleID: String?
    public var details: String?
    public var state: String?
    public var image: String?
    /// Extra metadata: file, project, language, branch, artist, album, track, site, platform, category…
    public var meta: [String: String]
    public var start: Date
    public var end: Date

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    public init(id: Int64 = 0, kind: String, name: String, bundleID: String?, details: String?, state: String?,
                image: String?, meta: [String: String], start: Date, end: Date) {
        self.id = id; self.kind = kind; self.name = name; self.bundleID = bundleID; self.details = details
        self.state = state; self.image = image; self.meta = meta; self.start = start; self.end = end
    }

    /// Duration of the part of the session inside `interval`.
    public func duration(in interval: DateInterval) -> TimeInterval {
        let s = max(start, interval.start), e = min(end, interval.end)
        return max(0, e.timeIntervalSince(s))
    }
}

/// SQLite-backed activity history shared by Aura (writer) and Aura Insights (reader).
public final class HistoryStore: @unchecked Sendable {
    public static let shared = HistoryStore()

    public static var databaseURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aura", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("history.sqlite")
    }

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "app.aura.history")
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(url: URL = HistoryStore.databaseURL) {
        queue.sync {
            guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { return }
            sqlite3_busy_timeout(db, 3000)
            exec("PRAGMA journal_mode=WAL")
            exec("""
            CREATE TABLE IF NOT EXISTS sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                kind TEXT NOT NULL, name TEXT NOT NULL, bundle_id TEXT,
                details TEXT, state TEXT, image TEXT, meta TEXT,
                start REAL NOT NULL, end REAL NOT NULL
            )
            """)
            exec("CREATE INDEX IF NOT EXISTS sessions_start ON sessions(start)")
            exec("CREATE INDEX IF NOT EXISTS sessions_kind ON sessions(kind, name)")
        }
    }

    deinit { sqlite3_close(db) }

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    private func bind(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value { sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(stmt, index) }
    }

    private static func encode(_ meta: [String: String]) -> String? {
        guard !meta.isEmpty, let data = try? JSONSerialization.data(withJSONObject: meta, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: Writing

    /// Inserts a session and returns its id.
    @discardableResult
    public func insert(_ s: HistorySession) -> Int64 {
        queue.sync {
            var stmt: OpaquePointer?
            let sql = "INSERT INTO sessions(kind,name,bundle_id,details,state,image,meta,start,end) VALUES (?,?,?,?,?,?,?,?,?)"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(stmt) }
            bind(stmt, 1, s.kind); bind(stmt, 2, s.name); bind(stmt, 3, s.bundleID); bind(stmt, 4, s.details)
            bind(stmt, 5, s.state); bind(stmt, 6, s.image); bind(stmt, 7, Self.encode(s.meta))
            sqlite3_bind_double(stmt, 8, s.start.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 9, s.end.timeIntervalSince1970)
            guard sqlite3_step(stmt) == SQLITE_DONE else { return 0 }
            return sqlite3_last_insert_rowid(db)
        }
    }

    /// Extends a session (and refreshes its texts, which can change during a session).
    public func update(id: Int64, end: Date, state: String? = nil, image: String? = nil) {
        queue.sync {
            var stmt: OpaquePointer?
            let sql = "UPDATE sessions SET end = ?, state = COALESCE(?, state), image = COALESCE(?, image) WHERE id = ?"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_double(stmt, 1, end.timeIntervalSince1970)
            bind(stmt, 2, state); bind(stmt, 3, image)
            sqlite3_bind_int64(stmt, 4, id)
            sqlite3_step(stmt)
        }
    }

    public func delete(id: Int64) {
        queue.sync { _ = exec("DELETE FROM sessions WHERE id = \(id)") }
    }

    public func delete(from: Date, to: Date) {
        queue.sync {
            _ = exec("DELETE FROM sessions WHERE start >= \(from.timeIntervalSince1970) AND start < \(to.timeIntervalSince1970)")
        }
    }

    public func deleteAll() {
        queue.sync {
            exec("DELETE FROM sessions")
            exec("VACUUM")
        }
    }

    // MARK: Reading

    /// Sessions overlapping [from, to), oldest first.
    public func sessions(from: Date = .distantPast, to: Date = .distantFuture, kind: String? = nil) -> [HistorySession] {
        queue.sync {
            var stmt: OpaquePointer?
            var sql = "SELECT id,kind,name,bundle_id,details,state,image,meta,start,end FROM sessions WHERE end > ? AND start < ?"
            if kind != nil { sql += " AND kind = ?" }
            sql += " ORDER BY start"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_double(stmt, 1, from.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 2, min(to.timeIntervalSince1970, 1e12))
            if let kind { bind(stmt, 3, kind) }
            var out: [HistorySession] = []
            func text(_ i: Int32) -> String? {
                sqlite3_column_text(stmt, i).map { String(cString: $0) }
            }
            while sqlite3_step(stmt) == SQLITE_ROW {
                var meta: [String: String] = [:]
                if let raw = text(7), let data = raw.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] { meta = obj }
                out.append(HistorySession(
                    id: sqlite3_column_int64(stmt, 0), kind: text(1) ?? "", name: text(2) ?? "", bundleID: text(3),
                    details: text(4), state: text(5), image: text(6), meta: meta,
                    start: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 8)),
                    end: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 9))
                ))
            }
            return out
        }
    }

    public var firstSessionDate: Date? {
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT MIN(start) FROM sessions", -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW, sqlite3_column_type(stmt, 0) != SQLITE_NULL else { return nil }
            return Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0))
        }
    }

    public var fileSize: Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: Self.databaseURL.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
