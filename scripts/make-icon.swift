import AppKit

// Compose the Kelpie app icon: macOS-style rounded rect + a dog silhouette.
//
// Run it from the repository root:
//
//   swift scripts/make-icon.swift
//
// It writes all seven sizes straight into the asset catalogue, so there is
// nothing to copy afterwards and the committed icons are always exactly what
// this script produces.
//
// Source artwork: "Dog Silhouette" by GangandInfographie, from Openclipart
// (https://openclipart.org/detail/276049/dog-silhouette), released into the
// public domain under CC0. It ships in this repository — unlike the Noto Emoji
// dog it replaces, CC0 carries no redistribution condition to reconcile with
// Kelpie's MIT licence.
//
// The artwork is pure black; it is recoloured here through its own alpha
// rather than being edited, so the file on disk stays byte-identical to what
// Openclipart publishes and the colour is one line to change.
let srcPath = "scripts/dog-silhouette.png"
let outDir = "Sources/Kelpie/Assets.xcassets/AppIcon.appiconset"

/// How much of the canvas the dog occupies. 0.86 crowds the rounded rect and
/// 0.70 leaves it looking lost; 0.78 sits where the emoji used to.
let artworkScale: CGFloat = 0.78
let artworkColor = NSColor(calibratedRed: 0.227, green: 0.137, blue: 0.090, alpha: 1) // #3A2317

guard let art = NSImage(contentsOfFile: srcPath) else {
    fatalError("cannot load \(srcPath) — run this from the repository root")
}

func drawIcon(size: Int) -> NSBitmapImageRep {
    let s = CGFloat(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("rep") }
    rep.size = NSSize(width: s, height: s)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
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

    // Fit the artwork into a centred box, keeping its aspect ratio, and nudge
    // it down slightly: the tail reaches higher than the paws drop.
    let box = s * artworkScale
    let aspect = art.size.width / art.size.height
    let w = aspect >= 1 ? box : box * aspect
    let h = aspect >= 1 ? box / aspect : box
    let dst = NSRect(x: (s - w) / 2, y: (s - h) / 2 - s * 0.02, width: w, height: h)

    // Recolour through the artwork's own alpha: draw it into a scratch image,
    // flood the colour over only what it covered, then composite that.
    let tinted = NSImage(size: dst.size)
    tinted.lockFocus()
    let local = NSRect(origin: .zero, size: dst.size)
    art.draw(in: local, from: .zero, operation: .sourceOver, fraction: 1)
    artworkColor.setFill()
    local.fill(using: .sourceAtop)
    tinted.unlockFocus()
    tinted.draw(in: dst, from: .zero, operation: .sourceOver, fraction: 1)

    return rep
}

for size in [16, 32, 64, 128, 256, 512, 1024] {
    let rep = drawIcon(size: size)
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
    try data.write(to: URL(fileURLWithPath: "\(outDir)/icon_\(size).png"))
    print("wrote icon_\(size).png")
}
