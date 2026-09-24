import Foundation

/// Finds the project open in a JetBrains IDE (WebStorm, IntelliJ, PyCharm…) without any permission,
/// from the IDE's `options/recentProjects.xml`, which it updates whenever a project window is activated.
enum JetBrainsInspector {
    struct Project: Equatable, Sendable {
        var path: String
        var name: String
        /// Window title stored by the IDE ("portfolio – next-env.d.ts"); may lag behind.
        var frameTitle: String?
    }

    /// `WebStorm`, `IntelliJIdea`, `PyCharm`… as used in the config folder names.
    private static func productPrefix(bundleID: String) -> String? {
        let map: [String: String] = [
            "com.jetbrains.WebStorm": "WebStorm", "com.jetbrains.intellij": "IntelliJIdea",
            "com.jetbrains.intellij.ce": "IdeaIC", "com.jetbrains.pycharm": "PyCharm",
            "com.jetbrains.pycharm.ce": "PyCharmCE", "com.jetbrains.CLion": "CLion", "com.jetbrains.goland": "GoLand",
            "com.jetbrains.PhpStorm": "PhpStorm", "com.jetbrains.rubymine": "RubyMine", "com.jetbrains.rider": "Rider",
            "com.jetbrains.datagrip": "DataGrip", "com.jetbrains.rustrover": "RustRover", "com.jetbrains.fleet": "Fleet",
            "com.google.android.studio": "AndroidStudio",
        ]
        return map[bundleID] ?? (bundleID.hasPrefix("com.jetbrains.") ? String(bundleID.dropFirst(14)) : nil)
    }

    /// The most recently activated open project of this IDE.
    static func activeProject(bundleID: String) -> Project? {
        guard let prefix = productPrefix(bundleID: bundleID) else { return nil }
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let roots = [home.appendingPathComponent("Library/Application Support/JetBrains"),
                     home.appendingPathComponent("Library/Application Support/Google")]
        var files: [URL] = []
        for root in roots {
            let dirs = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
            for dir in dirs where dir.lowercased().hasPrefix(prefix.lowercased()) {
                let file = root.appendingPathComponent(dir).appendingPathComponent("options/recentProjects.xml")
                if fm.fileExists(atPath: file.path) { files.append(file) }
            }
        }
        // Newest IDE version first (its file is the one being written to).
        files.sort { (modDate($0) ?? .distantPast) > (modDate($1) ?? .distantPast) }
        guard let file = files.first, let xml = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return parse(xml: xml, home: home.path)
    }

    private static func modDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Picks the open project with the latest `activationTimestamp`.
    static func parse(xml: String, home: String) -> Project? {
        var best: (Project, Int64)?
        let entries = xml.components(separatedBy: "<entry key=\"").dropFirst()
        for entry in entries {
            guard let keyEnd = entry.firstIndex(of: "\"") else { continue }
            let rawPath = String(entry[..<keyEnd])
            guard entry.contains("opened=\"true\"") else { continue }
            let stamp = value(of: "activationTimestamp", in: entry).flatMap { Int64($0) } ?? 0
            let path = rawPath.replacingOccurrences(of: "$USER_HOME$", with: home)
            let title = attribute("frameTitle", in: entry).map(unescape)
            let project = Project(path: path, name: (path as NSString).lastPathComponent, frameTitle: title)
            if best == nil || stamp > best!.1 { best = (project, stamp) }
        }
        return best?.0
    }

    private static func value(of option: String, in text: String) -> String? {
        guard let r = text.range(of: "name=\"\(option)\" value=\"") else { return nil }
        let rest = text[r.upperBound...]
        return rest.firstIndex(of: "\"").map { String(rest[..<$0]) }
    }

    private static func attribute(_ name: String, in text: String) -> String? {
        guard let r = text.range(of: "\(name)=\"") else { return nil }
        let rest = text[r.upperBound...]
        return rest.firstIndex(of: "\"").map { String(rest[..<$0]) }
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}
