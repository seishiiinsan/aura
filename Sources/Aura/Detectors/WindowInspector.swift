import AppKit
import ApplicationServices
import Foundation

/// Reads the focused window's title / document through the Accessibility API.
enum WindowInspector {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt asking for Accessibility access.
    static func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    struct Focused: Equatable, Sendable {
        var title: String?
        var documentPath: String?
    }

    /// Title of the app's main window, even when it isn't frontmost.
    static func mainWindowTitle(pid: pid_t) -> String? {
        guard isTrusted else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &windowRef) == .success,
              let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID() else { return nil }
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(windowRef as! AXUIElement, kAXTitleAttribute as CFString, &titleRef)
        return (titleRef as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    static func focusedWindow(pid: pid_t) -> Focused? {
        guard isTrusted else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID() else { return nil }
        let window = windowRef as! AXUIElement

        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
        var docRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXDocumentAttribute as CFString, &docRef)

        var path: String?
        if let doc = docRef as? String, let url = URL(string: doc), url.isFileURL { path = url.path }
        let title = (titleRef as? String).flatMap { $0.isEmpty ? nil : $0 }
        return Focused(title: title, documentPath: path)
    }
}

/// Reads the active tab of supported browsers through AppleScript.
enum BrowserInspector {
    struct Tab: Equatable, Sendable {
        var url: String
        var title: String
    }

    private static let chromium: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.canary", "com.brave.Browser", "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi", "company.thebrowser.Browser", "company.thebrowser.dia",
        "com.operasoftware.Opera", "com.operasoftware.OperaGX", "org.chromium.Chromium",
    ]
    private static let safari: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]

    static func supports(_ bundleID: String) -> Bool {
        chromium.contains(bundleID) || safari.contains(bundleID)
    }

    /// Every tab of every window (used to find music playing in background tabs).
    static func allTabs(bundleID: String, appName: String) async -> [Tab] {
        let isSafari = safari.contains(bundleID)
        guard isSafari || chromium.contains(bundleID) else { return [] }
        let titleKey = isSafari ? "name" : "title"
        let script = """
        tell application id "\(bundleID)"
            set out to {}
            repeat with w in windows
                repeat with t in tabs of w
                    set end of out to (URL of t) & (ASCII character 10) & (\(titleKey) of t)
                end repeat
            end repeat
            return out
        end tell
        """
        guard let rows = await AppleScriptRunner.shared.run(script, app: appName) else { return [] }
        return rows.compactMap { row in
            let parts = row.components(separatedBy: "\n")
            guard parts.count >= 2, !parts[0].isEmpty else { return nil }
            return Tab(url: parts[0], title: parts.dropFirst().joined(separator: "\n"))
        }
    }

    /// What the page's media player exposes (needs "Allow JavaScript from Apple Events" in the browser).
    struct PageMedia: Equatable, Sendable {
        var title: String?
        var subtitle: String?
        var artwork: String?
        var paused: Bool?
        var currentTime: Double?
        var duration: Double?
    }

    private static let mediaJS = #"(function(){var m=navigator.mediaSession&&navigator.mediaSession.metadata;var v=document.querySelector('video');function q(s){var e=document.querySelector(s);return e?e.innerText:''}var art='';if(m&&m.artwork&&m.artwork.length){art=m.artwork[m.artwork.length-1].src}return JSON.stringify({t:m?m.title:'',a:m?(m.artist||m.album):'',art:art,nf:q('[data-uia="video-title"]'),pt:q('.atvwebplayersdk-title-text'),ps:q('.atvwebplayersdk-subtitle-text'),dt:q('.title-field'),ds:q('.subtitle-field'),paused:v?v.paused:null,cur:v?v.currentTime:null,dur:v?v.duration:null})})()"#

    static func pageMedia(bundleID: String, appName: String) async -> PageMedia? {
        let js = mediaJS.replacingOccurrences(of: "\"", with: "\\\"")
        let script: String
        if safari.contains(bundleID) {
            script = "tell application id \"\(bundleID)\" to do JavaScript \"\(js)\" in current tab of front window"
        } else if chromium.contains(bundleID) {
            script = "tell application id \"\(bundleID)\" to execute active tab of front window javascript \"\(js)\""
        } else {
            return nil
        }
        guard let raw = await AppleScriptRunner.shared.run(script, app: appName)?.first,
              let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func str(_ k: String) -> String? {
            (obj[k] as? String).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        var media = PageMedia(paused: obj["paused"] as? Bool, currentTime: obj["cur"] as? Double, duration: obj["dur"] as? Double)
        if let nf = str("nf") {
            // Netflix: "Show\nS1:E3\nEpisode"
            let lines = nf.components(separatedBy: "\n").filter { !$0.isEmpty }
            media.title = lines.first
            media.subtitle = lines.dropFirst().joined(separator: " · ").nilIfEmpty
        } else if let pt = str("pt") {
            media.title = pt; media.subtitle = str("ps")
        } else if let dt = str("dt") {
            media.title = dt; media.subtitle = str("ds")
        } else {
            media.title = str("t"); media.subtitle = str("a")
        }
        media.artwork = str("art").flatMap { $0.hasPrefix("https://") ? $0 : nil }
        if let d = media.duration, !d.isFinite { media.duration = nil }
        return media.title == nil ? nil : media
    }

    static func activeTab(bundleID: String, appName: String) async -> Tab? {
        let script: String
        if safari.contains(bundleID) {
            script = """
            tell application id "\(bundleID)"
                if (count of windows) is 0 then return {"", ""}
                return {URL of current tab of front window, name of current tab of front window}
            end tell
            """
        } else if chromium.contains(bundleID) {
            script = """
            tell application id "\(bundleID)"
                if (count of windows) is 0 then return {"", ""}
                return {URL of active tab of front window, title of active tab of front window}
            end tell
            """
        } else {
            return nil
        }
        guard let r = await AppleScriptRunner.shared.run(script, app: appName), r.count >= 2, !r[0].isEmpty else { return nil }
        return Tab(url: r[0], title: r[1])
    }
}

/// Seconds since the last keyboard / mouse event.
enum IdleMonitor {
    static var idleSeconds: TimeInterval {
        guard let anyEvent = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyEvent)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
