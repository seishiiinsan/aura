import Foundation
import OSLog
import ServiceManagement

/// Thin wrapper around `SMAppService.mainApp` (macOS 13+).
enum LaunchAtLogin {
    private static let log = Logger(subsystem: "app.aura", category: "login")

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static var requiresApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            log.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
