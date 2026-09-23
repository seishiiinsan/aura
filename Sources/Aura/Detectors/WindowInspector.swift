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
