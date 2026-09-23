import AppKit
import Foundation

/// Reads the active macOS Focus mode.
///
/// macOS has no public API for this; the state lives in `~/Library/DoNotDisturb/DB`,
/// readable once Aura has Full Disk Access. Without it, Shortcuts automations
/// ("When <Focus> turns on → Open aura://profile/<name>") do the same job.
enum FocusMonitor {
    private static var dbDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB")
    }

    static var canRead: Bool {
        FileManager.default.isReadableFile(atPath: dbDir.appendingPathComponent("Assertions.json").path)
            && (try? Data(contentsOf: dbDir.appendingPathComponent("Assertions.json"))) != nil
    }

    /// Name of the active Focus ("Travail", "Ne pas déranger"…), or nil when none / unreadable.
    static func activeFocusName() -> String? {
        guard let assertions = json("Assertions.json") else { return nil }
        let active = strings(forKey: "assertionDetailsModeIdentifier", in: assertions)
        guard let modeID = active.first else { return nil }
        if let configs = json("ModeConfigurations.json"), let name = modeName(for: modeID, in: configs) { return name }
        return modeID.hasSuffix(".default") ? "Ne pas déranger" : modeID
    }

    /// Every Focus configured on this Mac (for the settings UI).
    static func allFocusNames() -> [String] {
        guard let configs = json("ModeConfigurations.json") else { return [] }
        var names: [String] = []
        collectModes(configs) { _, name in if !names.contains(name) { names.append(name) } }
        return names
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func json(_ file: String) -> Any? {
        guard let data = try? Data(contentsOf: dbDir.appendingPathComponent(file)) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func strings(forKey key: String, in obj: Any) -> [String] {
        var out: [String] = []
        if let dict = obj as? [String: Any] {
            for (k, v) in dict {
                if k == key, let s = v as? String { out.append(s) } else { out += strings(forKey: key, in: v) }
            }
        } else if let array = obj as? [Any] {
            for v in array { out += strings(forKey: key, in: v) }
        }
        return out
    }

    private static func collectModes(_ obj: Any, _ found: (String, String) -> Void) {
        if let dict = obj as? [String: Any] {
            if let id = dict["modeIdentifier"] as? String, let name = dict["name"] as? String { found(id, name) }
            for v in dict.values { collectModes(v, found) }
        } else if let array = obj as? [Any] {
            for v in array { collectModes(v, found) }
        }
    }

    private static func modeName(for id: String, in configs: Any) -> String? {
        var result: String?
        collectModes(configs) { modeID, name in if modeID == id { result = name } }
        return result
    }
}
