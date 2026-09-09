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
// Source artwork: `scripts/kelpie-silhouette.svg`, adapted from "Dog
// Silhouette" by GangandInfographie, from Openclipart
// (https://openclipart.org/detail/276049/dog-silhouette), released into the
// public domain under CC0. CC0 carries no redistribution condition to
// reconcile with Kelpie's MIT licence, and it permits the adaptation below.
//
// What was adapted, both about the hindquarters:
//
//  1. The original's tail is a thin whip carried up and *over* the back, tip
//     forward of a vertical line through its root. The Australian Kelpie
//     standard rules that out — "under no circumstances should the tail be
//     carried past a vertical line drawn through the root" — and describes one
//     that hangs in a very slight curve, reaches roughly to the hock, and is
//     furnished with a good brush. The tail here is a *separate closed
//     subpath*, wound the same way as the body, so a nonzero fill unions the
//     two and the stretch where it crosses the hind leg fills solid. Spliced
//     into the body's own outline, as the original had it, that crossing
//     cancels to a hole.
//  2. The original's croup detoured up into that tail, which left a peak on
//     the rump once the tail was its own shape. It is now one cubic from the
//     end of the topline to the top of the thigh, its handles along the
//     tangents either side so both joins stay smooth.
//
// Vector rather than raster throughout: the shapes were tuned by dragging the
// numbers and watching a 16px preview, which is not something masking and
// repainting a 2040x1746 bitmap would have allowed.
//
// Rasterising needs librsvg (`brew install librsvg`); the SVG is the only
// copy of the artwork in the repository, so there is no second file to keep
// in step with it.
//
// The artwork is pure black; it is recoloured here through its own alpha, so
// the colour stays one line to change.
let svgPath = "scripts/kelpie-silhouette.svg"
let outDir = "Sources/Kelpie/Assets.xcassets/AppIcon.appiconset"

/// The largest the artwork is ever drawn is 1024 * artworkScale, so rendering
/// it at 2400 leaves the compositor downsampling rather than enlarging.
let artworkRasterWidth = 2400

/// How much of the canvas the dog occupies. 0.86 crowds the rounded rect and
/// 0.70 leaves it looking lost; 0.78 sits where the emoji used to.
let artworkScale: CGFloat = 0.78
let artworkColor = NSColor(calibratedRed: 0.227, green: 0.137, blue: 0.090, alpha: 1) // #3A2317

/// The SVG's viewBox is trimmed to the artwork, so what comes back has no
/// margin and can be fitted by aspect ratio alone.
func rasterise(_ path: String, width: Int) -> NSImage {
    let out = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("kelpie-silhouette-\(width).png")
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    task.arguments = ["rsvg-convert", "-w", "\(width)", "-o", out.path, path]
    do {
        try task.run()
    } catch {
        fatalError("cannot run rsvg-convert — brew install librsvg")
    }
    task.waitUntilExit()
    guard task.terminationStatus == 0, let image = NSImage(contentsOf: out) else {
        fatalError("rsvg-convert failed on \(path) — run this from the repository root")
    }
    return image
}

let art = rasterise(svgPath, width: artworkRasterWidth)

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

// The menu bar icon: the same dog, drawn as a template image. macOS composites
// template images against whatever is behind the menu bar, so only the alpha
// channel matters — the artwork's own black is never shown, which is what keeps
// the resting item legible over a light wallpaper and a dark one alike.
//
// 15pt tall is 18pt wide at this aspect ratio, which fits the menu bar's budget
// while leaving the dog readable; the SF Symbol it replaces drew about the same
// height.
let menuBarDir = "Sources/Kelpie/Assets.xcassets/MenuBarIcon.imageset"
let menuBarHeight: CGFloat = 15

func drawMenuBarIcon(scale: Int) -> NSBitmapImageRep {
    let aspect = art.size.width / art.size.height
    let h = menuBarHeight * CGFloat(scale)
    let w = (menuBarHeight * aspect).rounded() * CGFloat(scale)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(w), pixelsHigh: Int(h),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("rep") }
    rep.size = NSSize(width: w, height: h)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("ctx") }
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    // Fitted to the full canvas: the SVG's viewBox is already trimmed to the
    // artwork, so there is no margin to trim off here.
    art.draw(in: NSRect(x: 0, y: 0, width: w, height: h), from: .zero,
             operation: .sourceOver, fraction: 1)
    return rep
}

for scale in [1, 2] {
    let rep = drawMenuBarIcon(scale: scale)
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
    try data.write(to: URL(fileURLWithPath: "\(menuBarDir)/menubar_\(scale)x.png"))
    print("wrote menubar_\(scale)x.png (\(rep.pixelsWide)x\(rep.pixelsHigh))")
}
