import Foundation

/// Finds the git repository of the project open in an editor and reads its branch.
enum GitInspector {
    struct Info: Equatable, Sendable {
        var branch: String
        /// "owner/repo" when the origin remote is on GitHub.
        var githubRepo: String?
    }

    static let defaultRoots = ["~/Developer", "~/Projects", "~/Code", "~/dev", "~/src", "~/WebstormProjects",
                               "~/IdeaProjects", "~/PycharmProjects", "~/Documents/GitHub", "~/GitHub", "~/Documents"]

    /// Walks up from a file to the closest directory containing `.git`.
    static func repository(containing path: String) -> URL? {
        var url = URL(fileURLWithPath: path)
        for _ in 0..<12 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) { return url }
            if url.path == "/" { break }
        }
        return nil
    }

    /// Looks for a folder named like the project in the usual code directories.
    static func repository(named project: String, roots: [String]) -> URL? {
        let fm = FileManager.default
        for root in roots {
            let base = URL(fileURLWithPath: (root as NSString).expandingTildeInPath)
            guard let children = try? fm.contentsOfDirectory(atPath: base.path) else { continue }
            if let match = children.first(where: { $0.caseInsensitiveCompare(project) == .orderedSame }) {
                let dir = base.appendingPathComponent(match)
                if fm.fileExists(atPath: dir.appendingPathComponent(".git").path) { return dir }
            }
        }
        return nil
    }

    static func info(repo: URL) -> Info? {
        var gitDir = repo.appendingPathComponent(".git")
        // Worktrees and submodules use a ".git" file pointing elsewhere.
        if let text = try? String(contentsOf: gitDir, encoding: .utf8), text.hasPrefix("gitdir:") {
            let path = text.dropFirst(7).trimmingCharacters(in: .whitespacesAndNewlines)
            gitDir = URL(fileURLWithPath: path, relativeTo: repo).standardizedFileURL
        }
        guard let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8) else { return nil }
        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
        let branch = trimmed.hasPrefix("ref: refs/heads/") ? String(trimmed.dropFirst(16)) : String(trimmed.prefix(7))
        return Info(branch: branch, githubRepo: githubRepo(gitDir: gitDir))
    }

    private static func githubRepo(gitDir: URL) -> String? {
        guard let config = try? String(contentsOf: gitDir.appendingPathComponent("config"), encoding: .utf8),
              let section = config.range(of: "[remote \"origin\"]") else { return nil }
        let rest = config[section.upperBound...]
        guard let urlLine = rest.split(separator: "\n").first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("url") }),
              let value = urlLine.split(separator: "=", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces),
              value.contains("github.com") else { return nil }
        var repo = value.replacingOccurrences(of: "git@github.com:", with: "")
            .replacingOccurrences(of: "https://github.com/", with: "")
        if repo.hasSuffix(".git") { repo.removeLast(4) }
        return repo.split(separator: "/").count == 2 ? repo : nil
    }
}
