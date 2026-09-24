import AppKit
import Testing
@testable import Aura

@Suite("On-screen score reading")
struct ScoreReaderTests {
    /// Draws a fake CS2 score bar: "left  clock  right".
    private func hud(_ left: String, _ clock: String, _ right: String) -> CGImage {
        let size = NSSize(width: 768, height: 130)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor(white: 0.08, alpha: 1).setFill()
            rect.fill()
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 44, weight: .bold), .foregroundColor: NSColor.white]
            (left as NSString).draw(at: NSPoint(x: 230, y: 40), withAttributes: attrs)
            (clock as NSString).draw(at: NSPoint(x: 340, y: 40), withAttributes: attrs)
            (right as NSString).draw(at: NSPoint(x: 500, y: 40), withAttributes: attrs)
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }

    @Test func readsScoreAroundClock() {
        let boxes = ScreenScoreReader.recognize(hud("2", "1:23", "7"))
        let reading = ScreenScoreReader.parse(boxes)
        #expect(reading?.left == 2)
        #expect(reading?.right == 7)
        #expect(reading?.clock == "1:23")
    }

    @Test func parsesMergedBoxes() {
        let box = ScreenScoreReader.TextBox(text: "12 0:45 9", rect: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.3))
        #expect(ScreenScoreReader.parse([box]) == .init(left: 12, right: 9, clock: "0:45"))
    }

    @Test func rejectsNoise() {
        let box = ScreenScoreReader.TextBox(text: "GeForce NOW", rect: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.3))
        #expect(ScreenScoreReader.parse([box]) == nil)
    }

    @Test func supportedGames() {
        #expect(ScreenScoreReader.supports(game: "Counter-Strike 2"))
        #expect(!ScreenScoreReader.supports(game: "Battlefield 1"))
    }
}
