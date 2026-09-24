import Foundation
import Testing
@testable import Aura

@Suite("Window titles, websites and players")
struct ParsingTests {
    @Test func vsCodeTitle() {
        let r = WindowTitleParser.editor(title: "main.swift — Aura", appName: "Code", bundleID: "com.microsoft.VSCode")
        #expect(r.file == "main.swift")
        #expect(r.project == "Aura")
    }

    @Test func xcodeTitle() {
        let r = WindowTitleParser.editor(title: "Aura — PresenceEngine.swift", appName: "Xcode", bundleID: "com.apple.dt.Xcode")
        #expect(r.file == "PresenceEngine.swift")
        #expect(r.project == "Aura")
    }

    @Test func jetBrainsTitle() {
        let r = WindowTitleParser.editor(title: "aura – Stats.swift", appName: "WebStorm", bundleID: "com.jetbrains.WebStorm")
        #expect(r.project == "aura")
        #expect(r.file == "Stats.swift")
    }

    @Test func youtubeURLs() {
        guard case .youtube(let id)? = SiteCatalog.analyze("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10")?.kind else {
            Issue.record("not detected"); return
        }
        #expect(id == "dQw4w9WgXcQ")
        guard case .youtube(let short)? = SiteCatalog.analyze("https://youtu.be/abc123")?.kind else { Issue.record("short"); return }
        #expect(short == "abc123")
    }

    @Test func twitchAndGitHub() {
        guard case .twitch(let channel)? = SiteCatalog.analyze("https://www.twitch.tv/zerator")?.kind else { Issue.record("twitch"); return }
        #expect(channel == "zerator")
        guard case .github(let repo)? = SiteCatalog.analyze("https://github.com/seishiiinsan/aura/pulls")?.kind else { Issue.record("gh"); return }
        #expect(repo == "seishiiinsan/aura")
        guard case .generic? = SiteCatalog.analyze("https://www.twitch.tv/directory")?.kind else { Issue.record("dir"); return }
    }

    @Test func streamingService() {
        guard case .streaming(let name)? = SiteCatalog.analyze("https://www.netflix.com/watch/81234")?.kind else { Issue.record("nf"); return }
        #expect(name == "Netflix")
    }

    @Test func webPlayerTitles() {
        #expect(ExtraMusicSources.parse(title: "▶ Humain by BEN plg", source: "SoundCloud") == .init(title: "Humain", artist: "BEN plg"))
        #expect(ExtraMusicSources.parse(title: "Humain by BEN plg", source: "SoundCloud") == nil) // not playing
        #expect(ExtraMusicSources.parse(title: "Get Lucky • Daft Punk", source: "Spotify") == .init(title: "Get Lucky", artist: "Daft Punk"))
        #expect(ExtraMusicSources.parse(title: "Spotify – Web Player", source: "Spotify") == nil)
        #expect(ExtraMusicSources.parse(title: "Deezer", source: "Deezer") == nil)
    }

    @Test func languages() {
        #expect(Languages.language(forFile: "App.swift")?.name == "Swift")
        #expect(Languages.language(forFile: "index.tsx")?.icon == "tsx")
        #expect(Languages.language(forFile: "Dockerfile")?.name == "Docker")
        #expect(Languages.language(forFile: "notes.xyz") == nil)
    }

    @Test func templates() {
        #expect(Template.render("{track} — {artist}", ["track": "Humain", "artist": "BEN plg"]) == "Humain — BEN plg")
        #expect(Template.render("Hello {unknown}", [:]) == "Hello")
    }

    @Test func cloudGaming() {
        #expect(GameDetector.cloudGameName(fromTitle: "Cyberpunk 2077 on GeForce NOW", platform: "GeForce NOW") == "Cyberpunk 2077")
        #expect(GameDetector.cloudGameName(fromTitle: "GeForce NOW", platform: "GeForce NOW") == nil)
        let xbox = GameDetector.browserCloudGame(url: "https://www.xbox.com/fr-FR/play/games/forza-horizon-5/9NKX70BBCDRN", title: "")
        #expect(xbox?.name == "Forza Horizon 5")
    }

    @Test func geforceNowLog() {
        let log = """
        2026-09-23T21:20:26.938[I]    GfnAppInfo.cpp:685  onStreamStart Inserted processInfo drsAppName:Nine Sols drsProfileName:Nine Sols shortName:x
        2026-09-23T21:40:00.000[I]    something else
        """
        let session = GeForceNowLog.session(fromLog: log)
        #expect(session?.game == "Nine Sols")
        #expect(session?.start != nil)
        #expect(GeForceNowLog.session(fromLog: log + "\n2026-09-23T22:00:00.000[I] onStreamStop processId:1") == nil)
    }

    @Test func jetBrainsRecentProjects() {
        let xml = """
        <application><component name="RecentProjectsManager"><option name="additionalInfo"><map>
        <entry key="$USER_HOME$/WebstormProjects/onbo">
            <value><RecentProjectMetaInfo frameTitle="onbo – .env" projectWorkspaceId="a">
              <option name="activationTimestamp" value="1790161954516" /></RecentProjectMetaInfo></value></entry>
        <entry key="$USER_HOME$/WebstormProjects/portfolio">
            <value><RecentProjectMetaInfo frameTitle="portfolio – next-env.d.ts" opened="true" projectWorkspaceId="b">
              <option name="activationTimestamp" value="1790282704602" /></RecentProjectMetaInfo></value></entry>
        <entry key="$USER_HOME$/WebstormProjects/aura">
            <value><RecentProjectMetaInfo frameTitle="aura" opened="true" projectWorkspaceId="c">
              <option name="activationTimestamp" value="1790200000000" /></RecentProjectMetaInfo></value></entry>
        </map></option></component></application>
        """
        // Two projects open: the file can't tell which window is in front.
        #expect(JetBrainsInspector.parse(xml: xml, home: "/Users/me") == nil)
        let single = xml.replacingOccurrences(of: #"frameTitle="aura" opened="true""#, with: #"frameTitle="aura""#)
        let p = JetBrainsInspector.parse(xml: single, home: "/Users/me")
        #expect(p?.name == "portfolio")
        #expect(p?.path == "/Users/me/WebstormProjects/portfolio")
        #expect(p?.frameTitle == "portfolio – next-env.d.ts")
        let parsed = WindowTitleParser.editor(title: p!.frameTitle!, appName: "WebStorm", bundleID: "com.jetbrains.WebStorm")
        #expect(parsed.file == "next-env.d.ts")
        #expect(Languages.language(forFile: "next-env.d.ts")?.name == "TypeScript")
    }
}
