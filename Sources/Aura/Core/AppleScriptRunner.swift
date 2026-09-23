import AppKit
import Foundation

/// Runs AppleScript on a dedicated serial queue and returns the result as strings.
///
/// Scripts are compiled once and cached. Callers must make sure the target
/// application is running beforehand, otherwise `tell application` would launch it.
final class AppleScriptRunner: @unchecked Sendable {
    static let shared = AppleScriptRunner()

    private let queue = DispatchQueue(label: "app.aura.applescript", qos: .utility)
    private var cache: [String: NSAppleScript] = [:]

    /// Last error per target application, used to surface missing Automation permission.
    private var denied = Set<String>()
    var deniedApps: Set<String> { queue.sync { denied } }

    func run(_ source: String, app: String) async -> [String]? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let script: NSAppleScript
                if let cached = cache[source] {
                    script = cached
                } else {
                    guard let s = NSAppleScript(source: source) else {
                        continuation.resume(returning: nil); return
                    }
                    var err: NSDictionary?
                    s.compileAndReturnError(&err)
                    cache[source] = s
                    script = s
                }
                var error: NSDictionary?
                let descriptor = script.executeAndReturnError(&error)
                if let error {
                    // -1743: not authorized to send Apple events.
                    if (error[NSAppleScript.errorNumber] as? Int) == -1743 { denied.insert(app) }
                    continuation.resume(returning: nil)
                    return
                }
                denied.remove(app)
                continuation.resume(returning: Self.flatten(descriptor))
            }
        }
    }

    private static func flatten(_ d: NSAppleEventDescriptor) -> [String] {
        let count = d.numberOfItems
        if count == 0 { return [d.stringValue ?? ""] }
        return (1...count).map { d.atIndex($0)?.stringValue ?? "" }
    }
}
