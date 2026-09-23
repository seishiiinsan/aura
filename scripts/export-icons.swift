// Exports the real icons of installed catalog apps to assets/icons/<bundleID>.png (512 px)
// so Aura can show them on Discord through raw.githubusercontent.com.
// Usage: swift scripts/export-icons.swift [extra.bundle.id …]
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let catalog = try String(contentsOf: root.appendingPathComponent("Sources/Aura/Engine/AppCatalog.swift"), encoding: .utf8)
let regex = try NSRegularExpression(pattern: #""([A-Za-z0-9.\-]+)": \.init\(category"#)
var ids = regex.matches(in: catalog, range: NSRange(catalog.startIndex..., in: catalog)).compactMap {
    Range($0.range(at: 1), in: catalog).map { String(catalog[$0]) }
}
ids += CommandLine.arguments.dropFirst()

let outDir = root.appendingPathComponent("assets/icons")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let indexURL = outDir.appendingPathComponent("index.json")
var index = Set((try? JSONDecoder().decode([String].self, from: Data(contentsOf: indexURL))) ?? [])

var exported = 0
for id in Set(ids) {
    guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { continue }
    let icon = NSWorkspace.shared.icon(forFile: appURL.path)
    let size = 512
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { continue }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    icon.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    try png.write(to: outDir.appendingPathComponent("\(id).png"))
    index.insert(id)
    exported += 1
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(index.sorted()).write(to: indexURL)
print("Exported \(exported) icons (\(index.count) in index)")
