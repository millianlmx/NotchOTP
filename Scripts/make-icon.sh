#!/bin/bash
# Draws Resources/AppIcon.icns: a macOS-style squircle with a notch carved out of it
# and an SF Symbol key in the middle.
#
#   Scripts/make-icon.sh        regenerate the .icns (+ a 512x512 preview in /tmp)
#
# The artwork is drawn by a small Swift program that is written to a scratch
# directory and run with `swift` in script mode, so the repository only keeps the
# script itself and the generated .icns.
set -euo pipefail

cd "$(dirname "$0")/.."

ICNS="Resources/AppIcon.icns"
PREVIEW="/tmp/YubicoNotch-AppIcon-512.png"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/IconMaker.swift" <<'SWIFT'
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Everything is laid out in a 1024-unit design space and scaled to each icon size,
// so the geometry stays identical from 16 to 1024 pixels.
let canvas: CGFloat = 1024
// Apple's macOS grid: the squircle occupies ~80 % of the canvas, the rest is the
// padding (and the drop shadow) that keeps icons from touching each other in the Dock.
let side: CGFloat = 824
// Superellipse exponent. n = 5 puts the 45° point at 0.8706 * a, which is the same
// spot as a circular corner of radius 0.22 * side, i.e. a continuous ("squircle") corner
// of the size Apple uses.
let squircleExponent: CGFloat = 5
let notchWidth: CGFloat = side * 0.38
let notchHeight: CGFloat = side * 0.13
let notchCornerRadius: CGFloat = side * 0.05
let glyphWidth: CGFloat = side * 0.46
// The notch eats the top of the shape, so the glyph sits a hair below the geometric
// centre, where it looks centred.
let glyphDrop: CGFloat = side * 0.02

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let gradientTop = rgb(0x3A, 0x3A, 0x3E)      // graphite
let gradientBottom = rgb(0x1C, 0x1C, 0x1E)   // near-black
let notchBlack = rgb(0, 0, 0)

let colourSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func context(pixels: Int) -> CGContext {
    guard
        let ctx = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colourSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else {
        fatalError("cannot allocate a \(pixels)x\(pixels) bitmap")
    }
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    return ctx
}

/// Superellipse `|x/a|^n + |y/b|^n = 1`, sampled as a polygon: at icon resolutions the
/// segments are far below one pixel, so the outline reads as a smooth curve.
func squirclePath(centre: CGPoint, radius a: CGFloat, exponent n: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let steps = 1440
    for step in 0...steps {
        let t = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let cosT = cos(t)
        let sinT = sin(t)
        let point = CGPoint(
            x: centre.x + a * copysign(pow(abs(cosT), 2 / n), cosT),
            y: centre.y + a * copysign(pow(abs(sinT), 2 / n), sinT)
        )
        if step == 0 {
            path.move(to: point)
        } else {
            path.addLine(to: point)
        }
    }
    path.closeSubpath()
    return path
}

/// The notch: flush with the top edge of the shape, square at the top, rounded at the
/// bottom, exactly like the cutout it stands for.
func notchPath(in body: CGRect) -> CGPath {
    let left = body.midX - notchWidth / 2
    let right = body.midX + notchWidth / 2
    let top = body.maxY
    let bottom = body.maxY - notchHeight
    let path = CGMutablePath()
    path.move(to: CGPoint(x: left, y: top))
    path.addLine(to: CGPoint(x: right, y: top))
    path.addArc(
        tangent1End: CGPoint(x: right, y: bottom),
        tangent2End: CGPoint(x: left, y: bottom),
        radius: notchCornerRadius
    )
    path.addArc(
        tangent1End: CGPoint(x: left, y: bottom),
        tangent2End: CGPoint(x: left, y: top),
        radius: notchCornerRadius
    )
    path.closeSubpath()
    return path
}

/// Bounding box of the pixels that are not fully transparent.
func alphaBounds(of image: CGImage) -> CGRect? {
    let width = image.width
    let height = image.height
    guard
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colourSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else { return nil }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let data = ctx.data else { return nil }
    let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
    var minX = width, minY = height, maxX = -1, maxY = -1
    for y in 0..<height {
        for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 8 {
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)
        }
    }
    guard maxX >= minX, maxY >= minY else { return nil }
    // CoreGraphics bitmaps have the origin at the bottom left, like the rest of the
    // drawing code, so the scan-produced rect already has the right orientation.
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

/// `key.horizontal.fill` rendered white, plus the box of its visible pixels so the
/// glyph can be sized by how wide it actually looks rather than by its layout box.
func keyGlyph(pixelBox: Int) -> (image: CGImage, visible: CGRect)? {
    guard let symbol = NSImage(systemSymbolName: "key.horizontal.fill", accessibilityDescription: nil) else {
        return nil
    }
    let configuration = NSImage.SymbolConfiguration(pointSize: CGFloat(pixelBox), weight: .medium)
    guard let configured = symbol.withSymbolConfiguration(configuration) else { return nil }
    var proposed = CGRect(origin: .zero, size: configured.size)
    guard let raw = configured.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
        return nil
    }
    guard let visible = alphaBounds(of: raw) else { return nil }
    let ctx = context(pixels: raw.width)
    let frame = CGRect(x: 0, y: 0, width: raw.width, height: raw.height)
    ctx.draw(raw, in: frame)
    // The symbol is black; keeping the destination's coverage and replacing its colour
    // with white turns it into a white glyph with the same antialiasing.
    ctx.setBlendMode(.sourceIn)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(frame)
    guard let white = ctx.makeImage() else { return nil }
    return (white, visible)
}

func drawIcon(in ctx: CGContext, scale: CGFloat) {
    ctx.scaleBy(x: scale, y: scale)
    let body = CGRect(
        x: (canvas - side) / 2,
        y: (canvas - side) / 2,
        width: side,
        height: side
    )
    let shape = squirclePath(centre: CGPoint(x: body.midX, y: body.midY), radius: side / 2, exponent: squircleExponent)

    // Drop shadow, cast by the shape itself, then the graphite gradient inside it.
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -side * 0.012),
        blur: side * 0.03,
        color: rgb(0, 0, 0, 0.4)
    )
    ctx.addPath(shape)
    ctx.clip()
    if let gradient = CGGradient(
        colorsSpace: colourSpace,
        colors: [gradientTop, gradientBottom] as CFArray,
        locations: [0, 1]
    ) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: body.midX, y: body.maxY),
            end: CGPoint(x: body.midX, y: body.minY),
            options: []
        )
    }
    ctx.restoreGState()

    // Light inner shadow: the shape's own outline is stroked with a blur while the clip
    // keeps only the inside, which darkens the rim just enough to give it depth.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.setShadow(offset: .zero, blur: side * 0.035, color: rgb(0, 0, 0, 0.5))
    ctx.setStrokeColor(rgb(0, 0, 0, 0.28))
    ctx.setLineWidth(side * 0.045)
    ctx.addPath(shape)
    ctx.strokePath()
    ctx.restoreGState()

    // The notch, pure black, on top of everything.
    ctx.saveGState()
    ctx.setFillColor(notchBlack)
    ctx.addPath(notchPath(in: body))
    ctx.fillPath()
    ctx.restoreGState()

    // The key, rasterised at the size it will actually occupy, then sized by its
    // visible width.
    let glyphPixels = max(4, Int((glyphWidth * scale).rounded()))
    if let glyph = keyGlyph(pixelBox: glyphPixels) {
        let imageSide = CGFloat(glyph.image.width)
        // Scale the raster so the glyph's *visible* pixels — not its layout box, which
        // has margins — span 46 % of the shape's width.
        let scaleUp = glyphWidth / glyph.visible.width
        let drawnWidth = imageSide * scaleUp
        let drawnHeight = CGFloat(glyph.image.height) * scaleUp
        let centre = CGPoint(x: body.midX, y: body.midY - glyphDrop)
        ctx.draw(
            glyph.image,
            in: CGRect(
                x: centre.x - drawnWidth / 2,
                y: centre.y - drawnHeight / 2,
                width: drawnWidth,
                height: drawnHeight
            )
        )
    }
}

func render(size: Int, supersample: CGFloat) -> CGImage {
    let big = context(pixels: Int((CGFloat(size) * supersample).rounded()))
    drawIcon(in: big, scale: CGFloat(size) * supersample / canvas)
    guard let rendered = big.makeImage() else { fatalError("cannot render \(size)px") }
    guard supersample > 1 else { return rendered }

    // Downsample once, with high-quality interpolation, instead of letting each size
    // be drawn with its own amount of aliasing.
    let small = context(pixels: size)
    small.interpolationQuality = .high
    small.draw(rendered, in: CGRect(x: 0, y: 0, width: size, height: size))
    guard let downscaled = small.makeImage() else { fatalError("cannot downscale \(size)px") }
    return downscaled
}

func write(_ image: CGImage, to url: URL) {
    guard
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        )
    else {
        fatalError("cannot write \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("cannot write \(url.path)") }
}

// MARK: - Entry point

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: IconMaker <iconset directory> [preview.png]\n".utf8))
    exit(2)
}
let iconset = URL(fileURLWithPath: arguments[1], isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// The ten files `iconutil` expects, drawn at seven sizes.
let slots: [(pixels: Int, names: [String])] = [
    (16, ["icon_16x16.png"]),
    (32, ["icon_16x16@2x.png", "icon_32x32.png"]),
    (64, ["icon_32x32@2x.png"]),
    (128, ["icon_128x128.png"]),
    (256, ["icon_128x128@2x.png", "icon_256x256.png"]),
    (512, ["icon_256x256@2x.png", "icon_512x512.png"]),
    (1024, ["icon_512x512@2x.png"]),
]

for slot in slots {
    // Small icons get more supersampling: that is where aliasing shows the most.
    let supersample: CGFloat = slot.pixels <= 128 ? 4 : 2
    let image = render(size: slot.pixels, supersample: supersample)
    for name in slot.names {
        write(image, to: iconset.appendingPathComponent(name))
    }
    print("  \(slot.pixels)x\(slot.pixels) -> \(slot.names.joined(separator: ", "))")
}

if arguments.count >= 3 {
    let preview = URL(fileURLWithPath: arguments[2])
    write(render(size: 512, supersample: 2), to: preview)
    print("  preview -> \(preview.path)")
}
SWIFT

echo "Drawing ${ICNS}…"
swift "$WORK/IconMaker.swift" "$WORK/AppIcon.iconset" "$PREVIEW"
iconutil -c icns "$WORK/AppIcon.iconset" -o "$ICNS"

echo "Wrote $ICNS"
sips -g pixelWidth -g pixelHeight "$ICNS" | sed 's/^/  /'
echo "Preview: $PREVIEW"
