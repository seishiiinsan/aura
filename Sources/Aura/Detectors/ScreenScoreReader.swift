import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit
import Vision

/// A score read from the game's HUD.
struct LiveScore: Equatable, Sendable {
    /// Left and right team scores as displayed on screen.
    var left: Int
    var right: Int
    /// Round clock when visible ("1:23").
    var clock: String?
    var readAt: Date
}

/// Reads the live score from a streamed game's HUD (CS2 on GeForce NOW) with
/// ScreenCaptureKit + Vision, entirely on-device.
///
/// Only a small strip at the top center of the game window is captured, where CS2
/// shows `[left score] [round clock] [right score]`.
actor ScreenScoreReader {
    static let shared = ScreenScoreReader()

    /// Games whose HUD layout is supported.
    static let supportedGames: Set<String> = ["counter strike 2"]

    private var pending: (Int, Int)?
    private var confirmed: LiveScore?

    nonisolated static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    nonisolated static func requestPermission() {
        if !CGRequestScreenCaptureAccess() {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    nonisolated static func supports(game: String) -> Bool {
        supportedGames.contains(DetectableGames.normalize(game))
    }

    func reset() {
        pending = nil
        confirmed = nil
    }

    /// Captures and reads the HUD. Returns the last confirmed score (a new value must be
    /// read twice in a row to be confirmed, which filters out OCR glitches).
    func read(bundleID: String) async -> LiveScore? {
        guard Self.hasPermission, let image = await captureHUD(bundleID: bundleID) else { return confirmed }
        if ProcessInfo.processInfo.environment["AURA_DEBUG"] != nil { Self.saveDebugImage(image) }
        let texts = Self.recognize(image)
        guard let reading = Self.parse(texts) else { return confirmed }

        if let pending, pending == (reading.left, reading.right) {
            confirmed = LiveScore(left: reading.left, right: reading.right, clock: reading.clock, readAt: Date())
        } else if let c = confirmed, c.left == reading.left, c.right == reading.right {
            confirmed?.clock = reading.clock
            confirmed?.readAt = Date()
        }
        pending = (reading.left, reading.right)
        return confirmed
    }

    // MARK: Capture

    private func captureHUD(bundleID: String) async -> CGImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return nil }
        let windows = content.windows.filter {
            $0.owningApplication?.bundleIdentifier == bundleID && $0.windowLayer == 0 && $0.frame.width > 480
        }
        guard let window = windows.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else { return nil }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let w = window.frame.width, h = window.frame.height
        // Top-center strip where CS2 draws the score bar.
        let region = CGRect(x: w * 0.30, y: 0, width: w * 0.40, height: h * 0.12)
        config.sourceRect = region
        let scale = CGFloat(filter.pointPixelScale)
        config.width = max(1, Int(region.width * scale))
        config.height = max(1, Int(region.height * scale))
        config.showsCursor = false
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    private static func saveDebugImage(_ image: CGImage) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aura-score-hud.png")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    // MARK: Recognition

    struct TextBox: Sendable {
        var text: String
        /// Normalized, origin at the top-left.
        var rect: CGRect
    }

    static func recognize(_ image: CGImage) -> [TextBox] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.08
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([request])
        return (request.results ?? []).compactMap { obs in
            guard let candidate = obs.topCandidates(1).first else { return nil }
            let b = obs.boundingBox
            return TextBox(text: candidate.string, rect: CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height))
        }
    }

    struct Reading: Equatable, Sendable {
        var left: Int
        var right: Int
        var clock: String?
    }

    /// Finds `score clock score` (or two scores around the center when the clock is hidden).
    static func parse(_ boxes: [TextBox]) -> Reading? {
        func clean(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "O", with: "0").replacingOccurrences(of: "o", with: "0")
                .replacingOccurrences(of: "l", with: "1").replacingOccurrences(of: "I", with: "1")
                .replacingOccurrences(of: "|", with: "1")
        }
        var numbers: [(value: Int, rect: CGRect)] = []
        var clocks: [(text: String, rect: CGRect)] = []
        for box in boxes {
            // A single box may contain "2 1:23 7": split on spaces, spreading the rect.
            let parts = clean(box.text).split(separator: " ").map(String.init)
            for (i, part) in parts.enumerated() {
                let slice = box.rect.width / CGFloat(parts.count)
                let rect = CGRect(x: box.rect.minX + slice * CGFloat(i), y: box.rect.minY, width: slice, height: box.rect.height)
                if part.range(of: #"^\d{1,2}[:.]\d{2}$"#, options: .regularExpression) != nil {
                    clocks.append((part.replacingOccurrences(of: ".", with: ":"), rect))
                } else if part.range(of: #"^\d{1,2}$"#, options: .regularExpression) != nil, let v = Int(part), v <= 40 {
                    numbers.append((v, rect))
                }
            }
        }
        guard numbers.count >= 2 else { return nil }

        let anchorX: CGFloat
        var clockText: String?
        let anchorY: CGFloat?
        if let clock = clocks.min(by: { abs($0.rect.midX - 0.5) < abs($1.rect.midX - 0.5) }) {
            anchorX = clock.rect.midX
            anchorY = clock.rect.midY
            clockText = clock.text
        } else {
            anchorX = 0.5
            anchorY = nil
        }
        func sameRow(_ r: CGRect) -> Bool {
            guard let anchorY else { return true }
            return abs(r.midY - anchorY) < max(0.25, r.height)
        }
        let left = numbers.filter { $0.rect.maxX <= anchorX + 0.02 && sameRow($0.rect) }.max { $0.rect.midX < $1.rect.midX }
        let right = numbers.filter { $0.rect.minX >= anchorX - 0.02 && sameRow($0.rect) }.min { $0.rect.midX < $1.rect.midX }
        guard let left, let right, left.rect != right.rect else { return nil }
        // Both scores sit symmetrically around the clock; reject far-apart noise.
        guard abs((anchorX - left.rect.midX) - (right.rect.midX - anchorX)) < 0.2 else { return nil }
        return Reading(left: left.value, right: right.value, clock: clockText)
    }
}
