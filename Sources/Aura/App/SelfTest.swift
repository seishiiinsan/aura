import Foundation

/// Command-line diagnostics, e.g. `Aura.app/Contents/MacOS/Aura --selftest <clientID>`.
/// Performs a Discord handshake only: nothing is displayed on the profile.
enum SelfTest {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--selftest") else { return }
        let clientID = args.count > i + 1 ? args[i + 1] : "1402418491272986635"
        let ipc = DiscordIPC()
        let done = DispatchSemaphore(value: 0)
        ipc.onStatusChange = { status in
            print("IPC status:", status)
            switch status {
            case .connected, .failed: done.signal()
            default: break
            }
        }
        ipc.connect(clientID: clientID)
        // Callbacks are delivered on the main queue, so pump the run loop.
        let deadline = Date().addingTimeInterval(5)
        while done.wait(timeout: .now()) == .timedOut, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        ipc.disconnect()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        exit(0)
    }
}

import SwiftUI

extension SelfTest {
    /// `Aura --render-card <out.png>`: renders the presence card with sample data (design check).
    @MainActor
    static func renderCardIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-card"), args.count > i + 1 else { return }
        var p = RichPresence(type: .listening)
        p.details = "Humain"
        p.state = "BEN plg"
        p.largeText = "Réalité Rap Musique, Vol. 2"
        p.start = Date().addingTimeInterval(-97)
        p.end = Date().addingTimeInterval(64)
        p.smallImage = "x"
        p.buttons = [PresenceButton(label: "Écouter sur Spotify", url: "https://open.spotify.com")]
        let snap = PresenceSnapshot(kind: .music, sourceApp: "Spotify", clientID: "", presence: p)
        let view = VStack(spacing: 12) {
            PresenceCard(snapshot: snap, appName: "Spotify")
            PresenceCard(snapshot: nil, appName: nil, paused: true)
        }
        .padding(14)
        .frame(width: 340)
        .background(Color(nsColor: .windowBackgroundColor))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let tiff = renderer.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: args[i + 1]))
        }
        exit(0)
    }
}
