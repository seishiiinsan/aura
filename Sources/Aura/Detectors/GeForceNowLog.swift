import Foundation

/// Reads GeForce NOW's local session log to learn which game is being streamed.
///
/// The client logs `onStreamStart … drsAppName:<Game>` when a session begins and
/// `onStreamStop` when it ends, which works without any macOS permission.
enum GeForceNowLog {
    struct Session: Equatable, Sendable {
        var game: String
        var start: Date?
    }

    private static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NVIDIA/GeForceNOW/CxNative_GeForceNOW.log")
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        return f
    }()

    /// The current streaming session, or nil when no game is running.
    static func currentSession() -> Session? {
        guard let handle = try? FileHandle(forReadingFrom: logURL) else { return nil }
        defer { try? handle.close() }
        // Only the tail matters; the file can grow to a few hundred KB.
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 512_000 ? size - 512_000 : 0)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }
        return session(fromLog: text)
    }

    /// Parses the log text; the last start without a later stop is the running session.
    static func session(fromLog text: String) -> Session? {
        var session: Session?
        for line in text.split(separator: "\n") {
            if line.contains("onStreamStart"), let range = line.range(of: "drsAppName:") {
                let rest = line[range.upperBound...]
                let name = rest.components(separatedBy: " drsProfileName:").first?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                guard !name.isEmpty else { continue }
                session = Session(game: name, start: formatter.date(from: String(line.prefix(23))))
            } else if line.contains("onStreamStop") || line.contains("NotifyGameEnd") {
                session = nil
            }
        }
        return session
    }
}
