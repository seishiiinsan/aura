import AppKit
import Foundation
import Observation
import OSLog

/// Checks GitHub Releases for a newer Aura and installs it in place.
///
/// Releases carry `Aura.zip` (Aura.app + Aura Insights.app), built by the release workflow.
@MainActor
@Observable
final class Updater {
    static let shared = Updater()
    static let repository = "seishiiinsan/aura"

    struct Release: Equatable {
        var version: String
        var notes: String
        var zipURL: URL
        var pageURL: URL
    }

    enum Phase: Equatable {
        case idle, checking, upToDate, available(Release), downloading, installing, failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var lastCheck: Date?
    @ObservationIgnored private let log = Logger(subsystem: "app.aura", category: "updater")

    var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    /// Compares dotted versions numerically ("1.10.0" > "1.9.2").
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    func checkIfDue() {
        if let lastCheck, Date().timeIntervalSince(lastCheck) < 86_400 { return }
        Task { await check() }
    }

    func check() async {
        phase = .checking
        lastCheck = Date()
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest"),
              let json = await HTTP.json(url, fresh: true) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else {
            phase = .failed("Impossible de joindre GitHub")
            return
        }
        let assets = json["assets"] as? [[String: Any]] ?? []
        guard let zip = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true })?["browser_download_url"] as? String,
              let zipURL = URL(string: zip) else {
            phase = .upToDate
            return
        }
        let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        if Self.isNewer(version, than: currentVersion) {
            phase = .available(Release(version: version, notes: json["body"] as? String ?? "", zipURL: zipURL, pageURL: page))
        } else {
            phase = .upToDate
        }
    }

    /// Downloads the release, swaps the apps once Aura has quit, and relaunches.
    func install(_ release: Release) async {
        phase = .downloading
        do {
            let (tmp, response) = try await HTTP.session.download(from: release.zipURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("aura-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let zip = work.appendingPathComponent("Aura.zip")
            try FileManager.default.moveItem(at: tmp, to: zip)
            try run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])

            let newAura = work.appendingPathComponent("Aura.app")
            guard FileManager.default.fileExists(atPath: newAura.path) else { throw CocoaError(.fileNoSuchFile) }
            phase = .installing

            let target = Bundle.main.bundleURL.deletingLastPathComponent()
            let script = """
            while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.3; done
            rm -rf "\(target.path)/Aura.app" && ditto "\(newAura.path)" "\(target.path)/Aura.app"
            if [ -d "\(work.path)/Aura Insights.app" ]; then
              pkill -x AuraInsights; rm -rf "\(target.path)/Aura Insights.app"
              ditto "\(work.path)/Aura Insights.app" "\(target.path)/Aura Insights.app"
            fi
            xattr -dr com.apple.quarantine "\(target.path)/Aura.app" "\(target.path)/Aura Insights.app" 2>/dev/null
            open "\(target.path)/Aura.app"
            rm -rf "\(work.path)"
            """
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", script]
            try process.run()
            NSApp.terminate(nil)
        } catch {
            log.error("Update failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed("Échec de la mise à jour : \(error.localizedDescription)")
        }
    }

    private func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }
    }
}
