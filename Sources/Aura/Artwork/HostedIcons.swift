import Foundation

/// Real macOS app icons published in the repository (`assets/icons`), served by GitHub.
///
/// `scripts/export-icons.swift` exports them from installed apps; the index lists which exist.
actor HostedIcons {
    static let shared = HostedIcons()
    static let defaultBase = "https://raw.githubusercontent.com/seishiiinsan/aura/main/assets/icons/"

    private var index: Set<String> = []
    private var loadedAt: Date?
    private var loadedBase: String?

    func url(for bundleID: String?, base rawBase: String) async -> String? {
        guard let bundleID else { return nil }
        let base = rawBase.hasSuffix("/") ? rawBase : rawBase + "/"
        if loadedBase != base || loadedAt.map({ Date().timeIntervalSince($0) > 86_400 }) ?? true {
            loadedBase = base
            loadedAt = Date()
            if let url = URL(string: base + "index.json"),
               let list = await HTTP.decode([String].self, from: url) {
                index = Set(list)
            }
        }
        return index.contains(bundleID) ? base + bundleID + ".png" : nil
    }
}
