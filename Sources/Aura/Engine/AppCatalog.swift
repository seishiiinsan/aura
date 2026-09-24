import Foundation

enum AppCategory: String, Sendable {
    case coding, terminal, design, creative, audio, browser, communication, office, notes
    case ai, media, music, launcher, files, system, other
}

struct KnownApp: Sendable {
    var category: AppCategory
    /// Website domain, used for a high-resolution favicon when no App Store artwork exists.
    var domain: String?
}

/// Built-in knowledge about popular macOS apps.
enum AppCatalog {
    private static let exact: [String: KnownApp] = [
        // Code editors & dev tools
        "com.apple.dt.Xcode": .init(category: .coding, domain: "developer.apple.com"),
        "com.microsoft.VSCode": .init(category: .coding, domain: "code.visualstudio.com"),
        "com.microsoft.VSCodeInsiders": .init(category: .coding, domain: "code.visualstudio.com"),
        "com.vscodium": .init(category: .coding, domain: "vscodium.com"),
        "com.todesktop.230313mzl4w4u92": .init(category: .coding, domain: "cursor.com"),
        "com.exafunction.windsurf": .init(category: .coding, domain: "windsurf.com"),
        "dev.zed.Zed": .init(category: .coding, domain: "zed.dev"),
        "com.sublimetext.4": .init(category: .coding, domain: "sublimetext.com"),
        "com.sublimetext.3": .init(category: .coding, domain: "sublimetext.com"),
        "com.panic.Nova": .init(category: .coding, domain: "nova.app"),
        "com.barebones.bbedit": .init(category: .coding, domain: "barebones.com"),
        "org.vim.MacVim": .init(category: .coding, domain: "vim.org"),
        "com.google.android.studio": .init(category: .coding, domain: "developer.android.com"),
        "com.github.GitHubClient": .init(category: .coding, domain: "desktop.github.com"),
        "com.fournova.Tower3": .init(category: .coding, domain: "git-tower.com"),
        "com.axosoft.gitkraken": .init(category: .coding, domain: "gitkraken.com"),
        "com.postmanlabs.mac": .init(category: .coding, domain: "postman.com"),
        "com.docker.docker": .init(category: .coding, domain: "docker.com"),
        "com.tinyapp.TablePlus": .init(category: .coding, domain: "tableplus.com"),
        "com.apple.Playgrounds": .init(category: .coding, domain: "developer.apple.com"),
        // Terminals
        "com.apple.Terminal": .init(category: .terminal, domain: nil),
        "com.googlecode.iterm2": .init(category: .terminal, domain: "iterm2.com"),
        "dev.warp.Warp-Stable": .init(category: .terminal, domain: "warp.dev"),
        "com.mitchellh.ghostty": .init(category: .terminal, domain: "ghostty.org"),
        "net.kovidgoyal.kitty": .init(category: .terminal, domain: "sw.kovidgoyal.net"),
        "io.alacritty": .init(category: .terminal, domain: "alacritty.org"),
        "co.zeit.hyper": .init(category: .terminal, domain: "hyper.is"),
        // Design
        "com.figma.Desktop": .init(category: .design, domain: "figma.com"),
        "com.bohemiancoding.sketch3": .init(category: .design, domain: "sketch.com"),
        "com.adobe.Photoshop": .init(category: .design, domain: "adobe.com"),
        "com.adobe.illustrator": .init(category: .design, domain: "adobe.com"),
        "com.adobe.InDesign": .init(category: .design, domain: "adobe.com"),
        "com.adobe.LightroomClassicCC7": .init(category: .design, domain: "adobe.com"),
        "com.seriflabs.affinitydesigner2": .init(category: .design, domain: "affinity.serif.com"),
        "com.seriflabs.affinityphoto2": .init(category: .design, domain: "affinity.serif.com"),
        "com.pixelmatorteam.pixelmator.x": .init(category: .design, domain: "pixelmator.com"),
        "com.linearity.vd": .init(category: .design, domain: "linearity.io"),
        "com.framer.electron": .init(category: .design, domain: "framer.com"),
        // Video / 3D
        "com.apple.FinalCut": .init(category: .creative, domain: nil),
        "com.apple.iMovieApp": .init(category: .creative, domain: nil),
        "com.apple.motionapp": .init(category: .creative, domain: nil),
        "com.blackmagic-design.DaVinciResolve": .init(category: .creative, domain: "blackmagicdesign.com"),
        "com.adobe.AfterEffects": .init(category: .creative, domain: "adobe.com"),
        "org.blenderfoundation.blender": .init(category: .creative, domain: "blender.org"),
        "com.maxon.cinema4d": .init(category: .creative, domain: "maxon.net"),
        "com.obsproject.obs-studio": .init(category: .creative, domain: "obsproject.com"),
        // Audio production
        "com.apple.logic10": .init(category: .audio, domain: nil),
        "com.apple.garageband10": .init(category: .audio, domain: nil),
        "com.ableton.live": .init(category: .audio, domain: "ableton.com"),
        "com.image-line.flstudio": .init(category: .audio, domain: "image-line.com"),
        // Browsers
        "com.apple.Safari": .init(category: .browser, domain: nil),
        "com.apple.SafariTechnologyPreview": .init(category: .browser, domain: nil),
        "com.google.Chrome": .init(category: .browser, domain: "google.com/chrome"),
        "com.google.Chrome.canary": .init(category: .browser, domain: "google.com/chrome"),
        "company.thebrowser.Browser": .init(category: .browser, domain: "arc.net"),
        "company.thebrowser.dia": .init(category: .browser, domain: "diabrowser.com"),
        "com.brave.Browser": .init(category: .browser, domain: "brave.com"),
        "com.microsoft.edgemac": .init(category: .browser, domain: "microsoft.com/edge"),
        "com.vivaldi.Vivaldi": .init(category: .browser, domain: "vivaldi.com"),
        "com.operasoftware.Opera": .init(category: .browser, domain: "opera.com"),
        "com.operasoftware.OperaGX": .init(category: .browser, domain: "opera.com/gx"),
        "org.mozilla.firefox": .init(category: .browser, domain: "firefox.com"),
        "app.zen-browser.zen": .init(category: .browser, domain: "zen-browser.app"),
        "org.chromium.Chromium": .init(category: .browser, domain: "chromium.org"),
        // Communication
        "com.hnc.Discord": .init(category: .communication, domain: "discord.com"),
        "com.tinyspeck.slackmacgap": .init(category: .communication, domain: "slack.com"),
        "com.apple.MobileSMS": .init(category: .communication, domain: nil),
        "net.whatsapp.WhatsApp": .init(category: .communication, domain: "whatsapp.com"),
        "ru.keepcoder.Telegram": .init(category: .communication, domain: "telegram.org"),
        "org.telegram.desktop": .init(category: .communication, domain: "telegram.org"),
        "com.microsoft.teams2": .init(category: .communication, domain: "microsoft.com/microsoft-teams"),
        "us.zoom.xos": .init(category: .communication, domain: "zoom.us"),
        "com.apple.FaceTime": .init(category: .communication, domain: nil),
        "com.apple.mail": .init(category: .communication, domain: nil),
        "com.readdle.smartemail-Mac": .init(category: .communication, domain: "sparkmailapp.com"),
        "org.whispersystems.signal-desktop": .init(category: .communication, domain: "signal.org"),
        // Office
        "com.apple.iWork.Pages": .init(category: .office, domain: nil),
        "com.apple.iWork.Numbers": .init(category: .office, domain: nil),
        "com.apple.iWork.Keynote": .init(category: .office, domain: nil),
        "com.microsoft.Word": .init(category: .office, domain: "microsoft.com"),
        "com.microsoft.Excel": .init(category: .office, domain: "microsoft.com"),
        "com.microsoft.Powerpoint": .init(category: .office, domain: "microsoft.com"),
        "com.linear": .init(category: .office, domain: "linear.app"),
        "com.apple.iCal": .init(category: .office, domain: nil),
        "com.apple.reminders": .init(category: .office, domain: nil),
        // Notes
        "notion.id": .init(category: .notes, domain: "notion.so"),
        "md.obsidian": .init(category: .notes, domain: "obsidian.md"),
        "com.apple.Notes": .init(category: .notes, domain: nil),
        "net.shinyfrog.bear": .init(category: .notes, domain: "bear.app"),
        "com.lukilabs.lukiapp": .init(category: .notes, domain: "craft.do"),
        "com.ulyssesapp.mac": .init(category: .notes, domain: "ulysses.app"),
        "com.agiletortoise.Drafts-OSX": .init(category: .notes, domain: "getdrafts.com"),
        // AI
        "com.openai.chat": .init(category: .ai, domain: "chatgpt.com"),
        "com.anthropic.claudefordesktop": .init(category: .ai, domain: "claude.ai"),
        // Media
        "com.apple.TV": .init(category: .media, domain: nil),
        "com.colliderli.iina": .init(category: .media, domain: "iina.io"),
        "org.videolan.vlc": .init(category: .media, domain: "videolan.org"),
        "com.apple.QuickTimePlayerX": .init(category: .media, domain: nil),
        "com.apple.Music": .init(category: .music, domain: "music.apple.com"),
        "com.spotify.client": .init(category: .music, domain: "spotify.com"),
        "com.apple.podcasts": .init(category: .music, domain: "podcasts.apple.com"),
        "com.deezer.deezer-desktop": .init(category: .music, domain: "deezer.com"),
        "com.tidal.desktop": .init(category: .music, domain: "tidal.com"),
        // Game launchers
        "com.valvesoftware.steam": .init(category: .launcher, domain: "store.steampowered.com"),
        "com.epicgames.EpicGamesLauncher": .init(category: .launcher, domain: "epicgames.com"),
        "net.battle.app": .init(category: .launcher, domain: "battle.net"),
        "com.heroicgameslauncher.hgl": .init(category: .launcher, domain: "heroicgameslauncher.com"),
        "com.isaacmarovitz.Whisky": .init(category: .launcher, domain: "getwhisky.app"),
        "com.codeweavers.CrossOver": .init(category: .launcher, domain: "codeweavers.com"),
        "com.mojang.minecraftlauncher": .init(category: .launcher, domain: "minecraft.net"),
        "com.gog.galaxy": .init(category: .launcher, domain: "gog.com"),
        "com.nvidia.gfnpc.mall": .init(category: .launcher, domain: "nvidia.com"),
        "com.nvidia.geforcenow": .init(category: .launcher, domain: "nvidia.com"),
        // Files & system
        "com.apple.finder": .init(category: .files, domain: nil),
        "com.apple.systempreferences": .init(category: .system, domain: nil),
        "com.apple.AppStore": .init(category: .system, domain: nil),
        "com.apple.ActivityMonitor": .init(category: .system, domain: nil),
    ]

    private static let prefixes: [(String, KnownApp)] = [
        ("com.jetbrains.", .init(category: .coding, domain: "jetbrains.com")),
        ("com.google.android.studio", .init(category: .coding, domain: "developer.android.com")),
        ("com.adobe.PremierePro", .init(category: .creative, domain: "adobe.com")),
        ("com.adobe.", .init(category: .design, domain: "adobe.com")),
        ("com.microsoft.VSCode", .init(category: .coding, domain: "code.visualstudio.com")),
    ]

    /// Apps that must never be shown (Aura itself, login windows, etc.).
    static let ignored: Set<String> = [
        "app.aura.Aura", "com.apple.loginwindow", "com.apple.ScreenSaver.Engine",
        "com.apple.dock", "com.apple.controlcenter", "com.apple.notificationcenterui",
        "com.apple.Spotlight", "com.apple.SecurityAgent", "com.apple.UserNotificationCenter",
    ]

    static func info(for bundleID: String?) -> KnownApp? {
        guard let bundleID else { return nil }
        if let known = exact[bundleID] { return known }
        return prefixes.first { bundleID.hasPrefix($0.0) }?.1
    }

    /// Categories belonging to the Code source (editors, IDEs, dev tools, terminals).
    static func isCode(_ category: AppCategory) -> Bool {
        category == .coding || category == .terminal
    }

    static func category(for bundleID: String?) -> AppCategory {
        info(for: bundleID)?.category ?? .other
    }

    static func faviconURL(domain: String) -> String {
        let host = domain.split(separator: "/").first.map(String.init) ?? domain
        return "https://www.google.com/s2/favicons?domain=\(host)&sz=256"
    }
}

// MARK: - Websites

enum SiteKind: Sendable {
    case youtube(videoID: String)
    case youtubeMusic
    case twitch(channel: String)
    case streaming(service: String) // Netflix, Prime, Disney+…
    case github(repo: String?)
    case generic
}

struct SiteInfo: Sendable {
    var kind: SiteKind
    var host: String
    var displayName: String
    var url: URL
}

enum SiteCatalog {
    private static let names: [String: String] = [
        "youtube.com": "YouTube", "music.youtube.com": "YouTube Music", "twitch.tv": "Twitch",
        "netflix.com": "Netflix", "primevideo.com": "Prime Video", "disneyplus.com": "Disney+",
        "crunchyroll.com": "Crunchyroll", "tv.apple.com": "Apple TV+", "max.com": "Max",
        "canalplus.com": "Canal+", "github.com": "GitHub", "gitlab.com": "GitLab",
        "stackoverflow.com": "Stack Overflow", "reddit.com": "Reddit", "x.com": "X",
        "twitter.com": "X", "instagram.com": "Instagram", "tiktok.com": "TikTok",
        "chatgpt.com": "ChatGPT", "claude.ai": "Claude", "figma.com": "Figma",
        "notion.so": "Notion", "docs.google.com": "Google Docs", "mail.google.com": "Gmail",
        "linkedin.com": "LinkedIn", "wikipedia.org": "Wikipedia", "developer.apple.com": "Apple Developer",
        "open.spotify.com": "Spotify", "soundcloud.com": "SoundCloud", "deezer.com": "Deezer",
        "amazon.com": "Amazon", "amazon.fr": "Amazon", "vercel.com": "Vercel", "linear.app": "Linear",
    ]

    private static let streaming: Set<String> = [
        "netflix.com", "primevideo.com", "disneyplus.com", "crunchyroll.com", "tv.apple.com", "max.com", "canalplus.com",
    ]

    static func host(of url: URL) -> String {
        var host = url.host?.lowercased() ?? ""
        if host.hasPrefix("www.") { host.removeFirst(4) }
        if host.hasPrefix("m.") { host.removeFirst(2) }
        return host
    }

    static func analyze(_ urlString: String) -> SiteInfo? {
        guard let url = URL(string: urlString), let scheme = url.scheme, scheme.hasPrefix("http") else { return nil }
        let host = host(of: url)
        guard !host.isEmpty else { return nil }
        let base = names.keys.first { host == $0 || host.hasSuffix("." + $0) }
        let name = base.flatMap { names[$0] } ?? host
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = url.pathComponents.filter { $0 != "/" }

        var kind: SiteKind = .generic
        if host == "music.youtube.com" {
            kind = .youtubeMusic
        } else if host == "youtube.com" || host == "youtu.be" {
            var id: String?
            if host == "youtu.be" { id = path.first }
            else if path.first == "watch" { id = comps?.queryItems?.first { $0.name == "v" }?.value }
            else if path.first == "shorts" || path.first == "live" { id = path.dropFirst().first }
            if let id, !id.isEmpty { kind = .youtube(videoID: id) }
        } else if host == "twitch.tv", let channel = path.first,
                  !["directory", "videos", "settings", "downloads", "search", "p"].contains(channel) {
            kind = .twitch(channel: channel)
        } else if let base, streaming.contains(base) {
            kind = .streaming(service: name)
        } else if host == "github.com" {
            kind = .github(repo: path.count >= 2 ? "\(path[0])/\(path[1])" : nil)
        }
        return SiteInfo(kind: kind, host: host, displayName: name, url: url)
    }
}
