// Zeichnet das App-Symbol und legt ein .iconset an.  Aufruf: swift make-icon.swift <Ziel.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let r = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let shape = NSBezierPath(roundedRect: r, xRadius: r.width * 0.22, yRadius: r.width * 0.22)
    NSGradient(colors: [NSColor(calibratedRed: 0.16, green: 0.47, blue: 0.98, alpha: 1),
                        NSColor(calibratedRed: 0.53, green: 0.24, blue: 0.86, alpha: 1)])!.draw(in: shape, angle: -55)
    shape.addClip()

    // „Text“-Zeilen oben links
    NSColor(white: 1, alpha: 0.92).setFill()
    for (i, w) in [0.55, 0.42, 0.5].enumerated() {
        let y = r.maxY - r.height * (0.2 + 0.13 * CGFloat(i))
        NSBezierPath(roundedRect: NSRect(x: r.minX + r.width * 0.12, y: y, width: r.width * w, height: r.height * 0.07),
                     xRadius: r.height * 0.035, yRadius: r.height * 0.035).fill()
    }
    // Mosaik unten rechts
    let n = 6, cell = r.width / CGFloat(n)
    for i in 0..<n { for j in 0..<n where i > j {
        let a = 0.25 + 0.65 * Double((i * 7 + j * 13) % 10) / 10
        NSColor(white: 1, alpha: a).setFill()
        NSRect(x: r.minX + CGFloat(i) * cell, y: r.minY + CGFloat(j) * cell, width: cell, height: cell)
            .insetBy(dx: cell * 0.05, dy: cell * 0.05).fill()
    }}
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (px, name) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"),
                   (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")] {
    try render(px).write(to: out.appendingPathComponent("icon_\(name).png"))
}
