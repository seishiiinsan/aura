import Foundation
import Testing
@testable import Aura

@Suite("Rich presence payload & rules")
struct PresenceTests {
    @Test func clampsAndValidates() {
        var p = RichPresence(type: .listening)
        p.details = String(repeating: "a", count: 300)
        p.state = "x"
        p.largeImage = "https://example.com/a.png"
        p.buttons = [
            PresenceButton(label: "Écouter", url: "https://open.spotify.com/track/1"),
            PresenceButton(label: "Bad", url: "ftp://nope"),
            PresenceButton(label: "Third", url: "https://c.com"),
        ]
        let json = p.jsonObject
        #expect((json["details"] as? String)?.count == 128)
        #expect(((json["state"] as? String)?.count ?? 0) >= 2)
        #expect(json["type"] as? Int == 2)
        let buttons = json["buttons"] as? [[String: String]]
        #expect(buttons?.count == 1) // invalid URL dropped, only first 2 considered
        #expect((json["assets"] as? [String: Any])?["large_image"] as? String == "https://example.com/a.png")
    }

    @Test func similarityIgnoresJitter() {
        var a = RichPresence(type: .playing)
        a.details = "Coding"
        a.start = Date(timeIntervalSince1970: 1000)
        var b = a
        b.start = Date(timeIntervalSince1970: 1001.5)
        #expect(b.isSimilar(to: a))
        b.start = Date(timeIntervalSince1970: 1010)
        #expect(!b.isSimilar(to: a))
    }

    @Test func clientIDValidation() {
        #expect(PresenceEngine.isValidClientID("1552407073902297088"))
        #expect(!PresenceEngine.isValidClientID("123"))
        #expect(!PresenceEngine.isValidClientID("15524070739022970a8"))
    }

    @Test func ruleConditionsHours() {
        var c = RuleConditions()
        c.useHours = true
        c.fromMinute = 22 * 60
        c.toMinute = 2 * 60
        let cal = Calendar.current
        let day = cal.startOfDay(for: Date())
        #expect(c.matches(date: day.addingTimeInterval(23 * 3600), title: nil, externalDisplay: false))
        #expect(c.matches(date: day.addingTimeInterval(1 * 3600), title: nil, externalDisplay: false))
        #expect(!c.matches(date: day.addingTimeInterval(12 * 3600), title: nil, externalDisplay: false))
    }

    @Test func ruleConditionsTitleAndWeekday() {
        var c = RuleConditions()
        c.titleContains = "secret"
        #expect(c.matches(title: "My SECRET project", externalDisplay: false))
        #expect(!c.matches(title: "public", externalDisplay: false))
        c.titleContains = ""
        let today = Calendar.current.component(.weekday, from: Date())
        c.weekdays = [today == 1 ? 2 : 1]
        #expect(!c.matches(title: nil, externalDisplay: false))
    }

    @Test func settingsDecodeOlderFiles() throws {
        let json = #"{"clientID":"1552407073902297088","rules":[{"bundleID":"com.apple.dt.Xcode","appName":"Xcode"}]}"#
        let s = try JSONDecoder().decode(AuraSettings.self, from: Data(json.utf8))
        #expect(s.clientID == "1552407073902297088")
        #expect(s.rules.first?.mode == .customize)
        #expect(s.priority.count == SourceKind.allCases.count)
        #expect(!s.profiles.isEmpty)
    }

    @MainActor @Test func versionComparison() {
        #expect(Updater.isNewer("1.10.0", than: "1.9.2"))
        #expect(Updater.isNewer("v2.0", than: "1.99.99"))
        #expect(!Updater.isNewer("1.0.0", than: "1.0.0"))
        #expect(!Updater.isNewer("1.0", than: "1.0.1"))
    }

    @Test func profilesApply() {
        var s = AuraSettings()
        let discreet = PresenceProfile.presets.first { $0.name == "Discret" }!
        discreet.apply(to: &s)
        #expect(s.showWindowTitles == false)
        #expect(s.activeProfileID == discreet.id)
    }
}
