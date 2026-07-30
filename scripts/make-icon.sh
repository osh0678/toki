#!/usr/bin/env bash
# Generates Resources/Toki.icns from code — no design tool, no binary to hand-edit.
#
# A carrot-coloured squircle with a white `hare.fill` glyph, rendered at every size
# macOS asks for. Re-run this after changing the colours or the glyph; the resulting
# .icns is committed so a plain `./build.sh` needs nothing extra.
set -euo pipefail
cd "$(dirname "$0")/.."

ICONSET="build/Toki.iconset"
OUTPUT="Resources/Toki.icns"

rm -rf "$ICONSET"
mkdir -p "$ICONSET" Resources

swift - "$ICONSET" <<'SWIFT'
import AppKit

let outputDirectory = CommandLine.arguments[1]

/// Filename and pixel size for each entry `iconutil` expects.
let entries: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

/// The symbol tinted white on transparency. Drawing the template and then filling
/// with `.sourceAtop` inside its own canvas tints only the glyph's own pixels, which
/// is why this is rendered separately instead of straight onto the icon.
func whiteGlyph(side: CGFloat) -> NSImage? {
    guard let symbol = NSImage(systemSymbolName: "hare.fill", accessibilityDescription: nil),
          let sized = symbol.withSymbolConfiguration(
              NSImage.SymbolConfiguration(pointSize: side, weight: .semibold)
          )
    else { return nil }

    let canvas = NSImage(size: sized.size)
    canvas.lockFocus()
    sized.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    NSColor.white.set()
    NSRect(origin: .zero, size: sized.size).fill(using: .sourceAtop)
    canvas.unlockFocus()
    return canvas
}

func render(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }

    let side = CGFloat(pixels)
    rep.size = NSSize(width: side, height: side)

    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    // macOS icons leave breathing room rather than bleeding to the edge.
    let inset = side * 0.085
    let plate = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let corner = plate.width * 0.235
    let squircle = NSBezierPath(roundedRect: plate, xRadius: corner, yRadius: corner)

    NSGradient(
        colors: [
            NSColor(srgbRed: 0.98, green: 0.63, blue: 0.34, alpha: 1),
            NSColor(srgbRed: 0.89, green: 0.40, blue: 0.19, alpha: 1)
        ]
    )?.draw(in: squircle, angle: -90)

    if let glyph = whiteGlyph(side: plate.width * 0.5) {
        let size = glyph.size
        glyph.draw(
            in: NSRect(
                x: plate.midX - size.width / 2,
                y: plate.midY - size.height / 2,
                width: size.width,
                height: size.height
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for entry in entries {
    guard let data = render(pixels: entry.pixels) else {
        FileHandle.standardError.write(Data("렌더 실패: \(entry.name)\n".utf8))
        exit(1)
    }
    let url = URL(filePath: outputDirectory).appending(path: entry.name)
    try data.write(to: url)
}
print("PNG \(entries.count)개 렌더 완료")
SWIFT

iconutil -c icns "$ICONSET" -o "$OUTPUT"
rm -rf "$ICONSET"

echo "✅ ${OUTPUT} ($(du -h "$OUTPUT" | cut -f1))"
echo "   적용:  ./build.sh && open build/Toki.app"
