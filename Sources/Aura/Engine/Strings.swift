import Foundation

/// Text broadcast to Discord, in the language chosen by the user.
struct PresenceStrings: Sendable {
    let lang: PresenceLanguage

    private func t(_ fr: String, _ en: String) -> String { lang == .fr ? fr : en }

    func using(_ app: String) -> String { t("Utilise \(app)", "Using \(app)") }
    func codingIn(_ app: String) -> String { t("Code sur \(app)", "Coding in \(app)") }
    func editing(_ file: String) -> String { t("Édite \(file)", "Editing \(file)") }
    func project(_ p: String) -> String { t("Projet : \(p)", "Project: \(p)") }
    func workspace(_ app: String) -> String { t("Dans \(app)", "In \(app)") }
    func inTerminal() -> String { t("Dans le terminal", "In the terminal") }
    func designingIn(_ app: String) -> String { t("Design sur \(app)", "Designing in \(app)") }
    func editingVideo(_ app: String) -> String { t("Montage sur \(app)", "Editing in \(app)") }
    func producing(_ app: String) -> String { t("Produit de la musique sur \(app)", "Making music in \(app)") }
    func chattingOn(_ app: String) -> String { t("Discute sur \(app)", "Chatting on \(app)") }
    func writingIn(_ app: String) -> String { t("Écrit dans \(app)", "Writing in \(app)") }
    func notesIn(_ app: String) -> String { t("Prend des notes dans \(app)", "Taking notes in \(app)") }
    func askingAI(_ app: String) -> String { t("Discute avec \(app)", "Talking to \(app)") }
    func browsing(_ site: String) -> String { t("Navigue sur \(site)", "Browsing \(site)") }
    func browsingWeb() -> String { t("Navigue sur le web", "Browsing the web") }
    func browsingFiles() -> String { t("Explore ses fichiers", "Browsing files") }
    func watchingOn(_ service: String) -> String { t("Regarde \(service)", "Watching \(service)") }
    func watching() -> String { t("Regarde une vidéo", "Watching a video") }
    func liveOn(_ channel: String) -> String { t("Regarde \(channel) en live", "Watching \(channel) live") }
    func onTwitch() -> String { t("sur Twitch", "on Twitch") }
    func inLibrary(_ app: String) -> String { t("Dans la bibliothèque \(app)", "Browsing \(app) library") }
    func by(_ artist: String) -> String { t("par \(artist)", "by \(artist)") }
    func paused() -> String { t("En pause", "Paused") }
    func playing() -> String { t("En lecture", "Playing") }
    func inGame() -> String { t("En jeu", "In game") }
    func via(_ platform: String) -> String { t("via \(platform)", "via \(platform)") }
    func away() -> String { t("Absent", "Away") }
    func awaySince() -> String { t("Inactif depuis un moment", "Idle for a while") }
    func onMac() -> String { t("Sur son Mac", "On their Mac") }
    func repo(_ r: String) -> String { t("Dépôt \(r)", "Repo \(r)") }

    // Buttons (max 32 chars)
    func listenOnSpotify() -> String { t("Écouter sur Spotify", "Listen on Spotify") }
    func listenOnAppleMusic() -> String { t("Écouter sur Apple Music", "Listen on Apple Music") }
    func listenOn(_ service: String) -> String { t("Écouter sur \(service)", "Listen on \(service)") }
    func watchOnYouTube() -> String { t("Voir sur YouTube", "Watch on YouTube") }
    func watchOnTwitch() -> String { t("Regarder sur Twitch", "Watch on Twitch") }
    func viewOnGitHub() -> String { t("Voir sur GitHub", "View on GitHub") }
    func steamPage() -> String { t("Page Steam", "Steam page") }
}

/// Minimal `{placeholder}` renderer used by user-defined rules.
enum Template {
    static let variables = ["app", "title", "file", "project", "site", "track", "artist", "album", "game", "status"]

    static func render(_ template: String, _ values: [String: String]) -> String {
        var out = template
        for (key, value) in values { out = out.replacingOccurrences(of: "{\(key)}", with: value) }
        // Remove unresolved placeholders so they never leak to Discord.
        if let regex = try? NSRegularExpression(pattern: "\\{[a-z]+\\}") {
            out = regex.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "")
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}

/// Splits editor window titles like "main.swift — Aura" into file + project.
enum WindowTitleParser {
    private static let separators = [" — ", " – ", " - ", " | "]

    static func parts(_ title: String) -> [String] {
        for sep in separators where title.contains(sep) {
            return title.components(separatedBy: sep)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        return [title]
    }

    /// Returns (file, project) for code editors, best-effort.
    static func editor(title: String, appName: String, bundleID: String?) -> (file: String?, project: String?) {
        var p = parts(title).filter { $0.caseInsensitiveCompare(appName) != .orderedSame }
        p = p.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "●• ")) }
        guard !p.isEmpty else { return (nil, nil) }
        let looksLikeFile: (String) -> Bool = { s in
            let ext = (s as NSString).pathExtension
            return !ext.isEmpty && ext.count <= 10 && !s.contains(" ")
        }
        if bundleID == "com.apple.dt.Xcode" {
            // Xcode: "Project — File.swift"
            return (p.count > 1 ? p.last : nil, p.first)
        }
        if bundleID?.hasPrefix("com.jetbrains.") == true {
            // JetBrains: "project – File.kt"
            return (p.count > 1 ? p[1] : nil, p.first)
        }
        // VS Code family / Zed / Sublime: "file — project"
        if p.count >= 2 { return (p[0], p[1]) }
        return looksLikeFile(p[0]) ? (p[0], nil) : (nil, p[0])
    }
}
