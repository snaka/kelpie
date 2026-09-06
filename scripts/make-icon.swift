import AppKit

// Compose the Kelpie app icon: macOS-style rounded rect + Noto Emoji dog.
//
// U+1F415 (the whole dog) rather than U+1F436 (the dog face): a kelpie is a
// working dog, and the standing figure reads as one where a cropped face does
// not. 0.66 is as large as it goes before the ears crowd the rounded rect.
//
// Source artwork (Apache 2.0, © Google):
//   curl -sfLO https://raw.githubusercontent.com/googlefonts/noto-emoji/main/png/512/emoji_u1f415.png
// Run `swift scripts/make-icon.swift` next to the downloaded PNG, then copy
// out/icon_*.png into Sources/Kelpie/Assets.xcassets/AppIcon.appiconset/.
let srcPath = "emoji_u1f415.png"
let outDir = "out"

guard let emoji = NSImage(contentsOfFile: srcPath) else {
    fatalError("cannot load \(srcPath)")
}
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func drawIcon(size: Int) -> NSBitmapImageRep {
    let s = CGFloat(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("rep") }
    rep.size = NSSize(width: s, height: s)
    NSGraphicsContext.saveGraphicsState()
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("ctx") }
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high

    // Apple's macOS icon grid: 824x824 rounded rect centered on a 1024 canvas,
    // corner radius ~185.
    let inset = s * 100.0 / 1024.0
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = s * 185.0 / 1024.0
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    guard let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.67, green: 0.85, blue: 0.55, alpha: 1),
        ending: NSColor(calibratedRed: 0.40, green: 0.67, blue: 0.34, alpha: 1)
    ) else { fatalError("gradient") }
    gradient.draw(in: path, angle: -90)

    let e = s * 0.66
    let er = NSRect(x: (s - e) / 2, y: (s - e) / 2, width: e, height: e)
    emoji.draw(in: er, from: .zero, operation: .sourceOver, fraction: 1)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for size in [16, 32, 64, 128, 256, 512, 1024] {
    let rep = drawIcon(size: size)
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
    try data.write(to: URL(fileURLWithPath: "\(outDir)/icon_\(size).png"))
    print("wrote icon_\(size).png")
}
