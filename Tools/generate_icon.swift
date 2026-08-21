import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: generate_icon <iconset-directory>\n", stderr)
    exit(2)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, pixels) in variants {
    let size = CGFloat(pixels)
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let outer = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    outer.fill()

    let inset = size * 0.055
    let tile = outer.insetBy(dx: inset, dy: inset)
    let path = NSBezierPath(roundedRect: tile, xRadius: size * 0.22, yRadius: size * 0.22)
    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.18, green: 0.12, blue: 0.36, alpha: 1),
        ending: NSColor(calibratedRed: 0.42, green: 0.20, blue: 0.68, alpha: 1)
    )!
    gradient.draw(in: path, angle: -55)

    let font = NSFont(name: "Apple Color Emoji", size: size * 0.55) ?? .systemFont(ofSize: size * 0.55)
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    let glyph = "😀" as NSString
    let glyphSize = glyph.size(withAttributes: attributes)
    let point = NSPoint(
        x: (size - glyphSize.width) / 2,
        y: (size - glyphSize.height) / 2 - size * 0.015
    )
    glyph.draw(at: point, withAttributes: attributes)

    image.unlockFocus()
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else { fatalError("Could not render \(name)") }
    try png.write(to: output.appendingPathComponent(name), options: .atomic)
}
