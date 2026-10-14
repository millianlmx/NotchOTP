import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Composes the App Store screenshots around the captures taken by `Capture.swift`.
///
/// The captures are the app's own windows, taken with alpha and nothing else in them.
/// This program draws what surrounds them: for the three panel shots, the top of a Mac
/// display in a bezel, the painted wallpaper and menu bar behind it, and the notch the panel
/// hangs from; for the settings shot, the caption and the backdrop alone, since a 480 × 598
/// window is the picture. Everything is laid out in a 1280 × 800 design space — the smallest
/// size App Store Connect accepts — and rendered at each requested size, so the sizes are
/// the same picture at different resolutions.
///
///     swift Scripts/Screenshots/Compose.swift build/screenshots/raw docs/app-store/screenshots
///
/// Three things about the drawn frame are deliberate. The wallpaper and the menu bar are
/// painted, not photographed: a real capture of the menu bar would carry whatever the
/// author had open, which is nobody's business on a store screenshot. The panel itself is
/// the real window, at its real size — 420 × 340 points, the size it is on every Mac — so
/// nothing here claims a feature the app does not have. And the panel hangs from the top of
/// the display, where it lives, rather than floating in a rectangle of its own.

// MARK: - Design space

let design = CGSize(width: 1280, height: 800)

/// The sizes App Store Connect accepts for macOS, all 16:10. Two are enough to ship; the
/// others are the same layout at another scale, and `--all-sizes` draws them.
let shippingSizes: [CGSize] = [
    CGSize(width: 2560, height: 1600),
    CGSize(width: 1280, height: 800),
]
let everySize: [CGSize] = [
    CGSize(width: 1280, height: 800),
    CGSize(width: 1440, height: 900),
    CGSize(width: 2560, height: 1600),
    CGSize(width: 2880, height: 1800),
]

/// Height of the physical notch, and of the band the panel draws over it: the value the
/// capture carries, taken from `NSScreen.safeAreaInsets.top` on the capture machine.
let notchHeight: CGFloat = 32
/// `NotchGeometry.expandedSize` — the panel is this size on every Mac.
let panelSize = CGSize(width: 420, height: 340)
/// The notch is as wide as the gap between the two menu bar areas.
let notchWidth: CGFloat = 185
/// The bezel around the drawn display.
let bezel: CGFloat = 18

// MARK: - Palette

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let canvasInk = rgb(0x08080C)
let ink = rgb(0xFFFFFF)
let inkSecondary = rgb(0xFFFFFF, 0.62)
let menuInk = rgb(0xFFFFFF, 0.92)

// MARK: - Shots

/// Which capture goes in which picture, and what it says.
struct Shot {
    enum Kind {
        /// The panel hanging from the top of a display, headline above it, caption below.
        case panel
        /// The settings window at its own size, headline above it.
        case window
    }

    let kind: Kind
    /// Capture name without the language suffix or the frame number.
    let capture: String
    let slug: String
    let copy: [String: (headline: String, subhead: String?)]
}

let shots: [Shot] = [
    Shot(
        kind: .panel,
        capture: "list",
        slug: "01-codes-in-the-notch",
        copy: [
            "en": (
                headline: "Your one-time codes,\nright in the notch.",
                subhead: "Hover it and the panel opens on your accounts — the codes wait for a gesture."
            ),
            "fr": (
                headline: "Tes codes à usage unique,\ndans l’encoche.",
                subhead: "Survole-la et le panneau s’ouvre sur tes comptes : les codes attendent un geste."
            ),
        ]
    ),
    Shot(
        kind: .panel,
        capture: "confirm",
        slug: "02-one-gesture-per-code",
        copy: [
            "en": (
                headline: "A fingerprint\nfor every code.",
                subhead: "Apple’s prompt is drawn inside the panel, and a code shown once needs a new gesture."
            ),
            "fr": (
                headline: "Une empreinte\npour chaque code.",
                subhead: "L’invite d’Apple s’affiche dans le panneau ; un code affiché exige un nouveau geste."
            ),
        ]
    ),
    Shot(
        kind: .panel,
        capture: "revealed",
        slug: "03-the-code-in-the-clipboard",
        copy: [
            "en": (
                headline: "It lands in\nthe clipboard.",
                subhead: "Wiped after the delay you choose, and only if it still holds the code."
            ),
            "fr": (
                headline: "Il arrive dans\nle presse-papiers.",
                subhead: "Effacé après le délai que tu choisis, et seulement s’il contient encore le code."
            ),
        ]
    ),
    Shot(
        kind: .window,
        capture: "settings",
        slug: "04-settings",
        copy: [
            "en": (
                headline: "Yours to tune.",
                subhead: nil
            ),
            "fr": (
                headline: "Réglé une fois.",
                subhead: nil
            ),
        ]
    ),
]

/// The frame kept from each burst, per language.
///
/// The states that last less than a second — the sheet, the code leaving the panel — are
/// caught as a burst and picked here, from the middle of each state's window rather than its
/// edge. `Capture.swift` writes a contact sheet next to the frames
/// (`build/screenshots/raw/contact-<state>-<language>.png`); that is what to look at when a
/// re-run shifts them.
let framePicks: [String: [String: String]] = [
    "en": [
        "list": "list-en-05",
        "confirm": "confirm-en-05",
        "revealed": "confirm-en-20",
        "settings": "settings-en-16",
    ],
    "fr": [
        "list": "list-fr-05",
        "confirm": "confirm-fr-05",
        "revealed": "confirm-fr-20",
        "settings": "settings-fr-16",
    ],
]

// MARK: - Context

/// The canvas is opaque from edge to edge — the backdrop is filled before anything else is
/// drawn — so the context is created without an alpha channel: the file that comes out of it
/// is about a tenth smaller, and it does not claim a transparency the picture does not have.
func context(size: CGSize) -> CGContext {
    guard let ctx = CGContext(
        data: nil,
        width: Int(size.width),
        height: Int(size.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        fatalError("could not create a \(size) context")
    }
    return ctx
}

func image(at url: URL) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        FileHandle.standardError.write(Data("missing or unreadable capture: \(url.path)\n".utf8))
        exit(1)
    }
    return image
}

func fill(_ ctx: CGContext, _ rect: CGRect, _ colour: CGColor) {
    ctx.setFillColor(colour)
    ctx.fill(rect)
}

/// Rounded rectangle path, in the context's own (bottom-left) coordinates.
func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func linear(_ ctx: CGContext, _ rect: CGRect, _ colours: [CGColor], _ locations: [CGFloat]? = nil) {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let gradient = CGGradient(colorsSpace: space, colors: colours as CFArray, locations: locations)
    else { return }
    ctx.saveGState()
    ctx.clip(to: rect)
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.minX, y: rect.minY),
        options: []
    )
    ctx.restoreGState()
}

/// A soft round light, drawn additively, so overlapping glows build a mesh instead of
/// stacking flat discs.
func glow(_ ctx: CGContext, at centre: CGPoint, radius: CGFloat, _ colour: CGColor) {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let gradient = CGGradient(
              colorsSpace: space,
              colors: [colour, colour.copy(alpha: 0)!] as CFArray,
              locations: [0, 1]
          )
    else { return }
    ctx.saveGState()
    ctx.clip(to: ctx.boundingBoxOfClipPath)
    ctx.setBlendMode(.plusLighter)
    ctx.drawRadialGradient(
        gradient,
        startCenter: centre,
        startRadius: 0,
        endCenter: centre,
        endRadius: radius,
        options: []
    )
    ctx.restoreGState()
}

/// A vignette: the canvas darkens towards its corners, so the eye stays on the display.
func vignette(_ ctx: CGContext, inner: CGFloat, outer: CGFloat, _ colour: CGColor) {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let gradient = CGGradient(
              colorsSpace: space,
              colors: [colour.copy(alpha: 0)!, colour] as CFArray,
              locations: [0, 1]
          )
    else { return }
    let centre = CGPoint(x: design.width / 2, y: design.height / 2)
    ctx.saveGState()
    ctx.drawRadialGradient(gradient, startCenter: centre, startRadius: inner,
                           endCenter: centre, endRadius: outer, options: [])
    ctx.restoreGState()
}

/// The panel's silhouette: rounded at the bottom, concave fillets at the top, so it reads
/// as the physical notch growing downwards. The same geometry as `NotchShape`.
func notchPath(in rect: CGRect, top: CGFloat, bottom: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.addQuadCurve(
        to: CGPoint(x: rect.minX + top, y: rect.maxY - top),
        control: CGPoint(x: rect.minX + top, y: rect.maxY)
    )
    path.addLine(to: CGPoint(x: rect.minX + top, y: rect.minY + bottom))
    path.addQuadCurve(
        to: CGPoint(x: rect.minX + top + bottom, y: rect.minY),
        control: CGPoint(x: rect.minX + top, y: rect.minY)
    )
    path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.minY))
    path.addQuadCurve(
        to: CGPoint(x: rect.maxX - top, y: rect.minY + bottom),
        control: CGPoint(x: rect.maxX - top, y: rect.minY)
    )
    path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.maxY - top))
    path.addQuadCurve(
        to: CGPoint(x: rect.maxX, y: rect.maxY),
        control: CGPoint(x: rect.maxX - top, y: rect.maxY)
    )
    path.closeSubpath()
    return path
}

// MARK: - Text

struct TextStyle {
    var font: NSFont
    var colour: CGColor
    var alignment: CTTextAlignment = .center
    var lineSpacing: CGFloat = 0
    /// Tracking, as a fraction of the size. SF Pro is drawn tighter as it grows.
    var tracking: CGFloat = -0.012
}

func attributed(_ string: String, _ style: TextStyle) -> NSAttributedString {
    var alignment = style.alignment
    var spacing = style.lineSpacing
    var settings: [CTParagraphStyleSetting] = []
    withUnsafePointer(to: &alignment) {
        settings.append(CTParagraphStyleSetting(
            spec: .alignment,
            valueSize: MemoryLayout<CTTextAlignment>.size,
            value: $0
        ))
    }
    withUnsafePointer(to: &spacing) {
        settings.append(CTParagraphStyleSetting(
            spec: .lineSpacingAdjustment,
            valueSize: MemoryLayout<CGFloat>.size,
            value: $0
        ))
    }
    return NSAttributedString(string: string, attributes: [
        kCTFontAttributeName as NSAttributedString.Key: style.font,
        kCTForegroundColorAttributeName as NSAttributedString.Key: style.colour,
        kCTParagraphStyleAttributeName as NSAttributedString.Key:
            CTParagraphStyleCreate(settings, settings.count),
        kCTKernAttributeName as NSAttributedString.Key:
            style.tracking * style.font.pointSize,
    ])
}

/// The height the string needs at this width, so a caption is never quietly clipped.
func height(of string: NSAttributedString, width: CGFloat) -> CGFloat {
    let framesetter = CTFramesetterCreateWithAttributedString(string)
    var range = CFRange()
    let size = CTFramesetterSuggestFrameSizeWithConstraints(
        framesetter,
        CFRangeMake(0, 0),
        nil,
        CGSize(width: width, height: .greatestFiniteMagnitude),
        &range
    )
    guard range.length == string.length else {
        FileHandle.standardError.write(
            Data("caption does not fit its column: \(string.string.prefix(40))…\n".utf8)
        )
        return size.height
    }
    return size.height
}

/// Draws a block centred on a line, `centreFromTop` below the top edge of the canvas.
@discardableResult
func drawCentered(
    _ string: String,
    centreFromTop: CGFloat,
    column: CGFloat,
    style: TextStyle,
    context ctx: CGContext
) -> CGRect {
    let attributed = attributed(string, style)
    let box = height(of: attributed, width: column)
    let framesetter = CTFramesetterCreateWithAttributedString(attributed)
    let rect = CGRect(
        x: (design.width - column) / 2,
        y: design.height - centreFromTop - box / 2,
        width: column,
        height: box
    )
    let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), CGPath(rect: rect, transform: nil), nil)
    ctx.saveGState()
    CTFrameDraw(frame, ctx)
    ctx.restoreGState()
    return rect
}

func width(of string: String, font: NSFont) -> CGFloat {
    let attributed = NSAttributedString(string: string, attributes: [
        kCTFontAttributeName as NSAttributedString.Key: font,
    ])
    return CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed), nil, nil, nil))
}

/// An SF Symbol in one colour, laid out from its centre.
func symbol(
    _ name: String,
    height: CGFloat,
    colour: CGColor,
    centre: CGPoint,
    context ctx: CGContext
) {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
    let configuration = NSImage.SymbolConfiguration(pointSize: height, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(cgColor: colour) ?? .white]))
    guard let image = base.withSymbolConfiguration(configuration)?
        .cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { return }
    let box = CGFloat(image.width) / CGFloat(image.height) * height
    ctx.draw(image, in: CGRect(
        x: centre.x - box / 2,
        y: centre.y - height / 2,
        width: box,
        height: height
    ))
}

// MARK: - The display

/// The wallpaper: a dark mesh, so the black panel reads as a silhouette against it. One
/// family of hues — violet, indigo, a touch of rose — so the field behind the panel does
/// not split into two colours at its edges.
func drawWallpaper(in rect: CGRect, context ctx: CGContext) {
    ctx.saveGState()
    ctx.clip(to: rect)
    linear(ctx, rect, [rgb(0x3C3F7A), rgb(0x2B1B4C), rgb(0x15112A)])
    glow(
        ctx,
        at: CGPoint(x: rect.midX, y: rect.maxY),
        radius: rect.width * 0.55,
        rgb(0x8F7DFF, 0.55)
    )
    glow(
        ctx,
        at: CGPoint(x: rect.minX + rect.width * 0.13, y: rect.maxY - rect.height * 0.38),
        radius: rect.width * 0.42,
        rgb(0xE0568F, 0.26)
    )
    glow(
        ctx,
        at: CGPoint(x: rect.maxX - rect.width * 0.10, y: rect.minY + rect.height * 0.14),
        radius: rect.width * 0.40,
        rgb(0x3F63FF, 0.22)
    )
    // A hairline of light where the glass meets the bezel, and a soft inner shadow under
    // the top edge: enough to read as a screen rather than a rectangle.
    ctx.addPath(rounded(rect, 22))
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.10))
    ctx.setLineWidth(1)
    ctx.strokePath()
    ctx.restoreGState()
}

/// Menus on the left, status items on the right: the two clusters the notch sits between.
///
/// Only the menus that fit are drawn, exactly as a real menu bar behaves when the notch
/// takes the middle of the screen.
func drawMenuBar(in screen: CGRect, context ctx: CGContext) {
    let band = CGRect(
        x: screen.minX,
        y: screen.maxY - notchHeight,
        width: screen.width,
        height: notchHeight
    )
    ctx.saveGState()
    ctx.addPath(rounded(screen, 22))
    ctx.clip()
    fill(ctx, band, rgb(0x000000, 0.26))
    ctx.restoreGState()

    let centre = band.midY
    // The panel takes the middle: the clusters get what is left, less a margin.
    let notch = CGRect(
        x: screen.midX - notchWidth / 2 - 12,
        y: band.minY,
        width: notchWidth + 24,
        height: band.height
    )
    let left = CGRect(x: band.minX + 8, y: band.minY, width: notch.minX - band.minX - 8, height: band.height)
    let right = CGRect(x: notch.maxX, y: band.minY, width: band.maxX - notch.maxX - 8, height: band.height)

    // Left: the Apple menu, the application's name, then as many menus as fit.
    let menuFont = NSFont.systemFont(ofSize: 12.5, weight: .regular)
    let nameFont = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
    symbol("apple.logo", height: 14, colour: menuInk, centre: CGPoint(x: left.minX + 12, y: centre + 0.5), context: ctx)

    var x = left.minX + 26
    let name = "Finder"
    ctx.drawText(name, at: x, centre: centre, font: nameFont)
    x += width(of: name, font: nameFont) + 18

    for item in menubarCopy {
        let itemWidth = width(of: item, font: menuFont)
        guard x + itemWidth < left.maxX else { break }
        ctx.drawText(item, at: x, centre: centre, font: menuFont)
        x += itemWidth + 16
    }

    // Right: NotchOTP's own key, then the Wi-Fi, the battery and the clock.
    let clockFont = NSFont.systemFont(ofSize: 12.5, weight: .medium)
    var rightEdge = right.maxX - 12
    let clock = width(of: clockText, font: clockFont)
    ctx.drawText(clockText, at: rightEdge - clock, centre: centre, font: clockFont)
    rightEdge -= clock + 20

    symbol("battery.100", height: 14, colour: menuInk, centre: CGPoint(x: rightEdge - 9, y: centre), context: ctx)
    rightEdge -= 34
    symbol("wifi", height: 13, colour: menuInk, centre: CGPoint(x: rightEdge - 7, y: centre), context: ctx)
    rightEdge -= 32
    symbol("key.horizontal.fill", height: 13, colour: menuInk, centre: CGPoint(x: rightEdge - 7, y: centre), context: ctx)
}

extension CGContext {
    /// A menu bar label, drawn from its left edge on the band's centre line.
    func drawText(_ string: String, at x: CGFloat, centre: CGFloat, font: NSFont) {
        let attributed = NSAttributedString(string: string, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: menuInk,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        saveGState()
        textPosition = CGPoint(x: x, y: centre - bounds.height / 2 - bounds.minY)
        CTLineDraw(line, self)
        restoreGState()
    }
}

/// The top of a Mac display: a bezel, the screen, the menu bar, and the panel hanging from
/// the top edge — or the bare notch, when the panel is closed.
func drawDisplay(_ rect: CGRect, panel: CGImage?, context ctx: CGContext) {
    let screen = rect.insetBy(dx: bezel, dy: bezel)

    // The bezel, lit from above, and the shadow that lifts the display off the canvas.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 64, color: rgb(0x000000, 0.72))
    ctx.addPath(rounded(rect, 34))
    ctx.setFillColor(rgb(0x101014))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(rounded(rect, 34))
    ctx.clip()
    linear(ctx, rect, [rgb(0x3A3A44), rgb(0x15151A), rgb(0x0C0C10)])
    ctx.restoreGState()

    // The screen itself.
    ctx.saveGState()
    ctx.addPath(rounded(screen, 22))
    ctx.clip()
    drawWallpaper(in: screen, context: ctx)
    ctx.restoreGState()

    drawMenuBar(in: screen, context: ctx)

    // The panel: the real capture, at its real size, hanging from the screen's top edge.
    let frame = CGRect(
        x: screen.midX - panelSize.width / 2,
        y: screen.maxY - panelSize.height,
        width: panelSize.width,
        height: panelSize.height
    )
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 58, color: rgb(0x000000, 0.78))
    if let panel {
        ctx.draw(panel, in: frame)
    } else {
        let notch = CGRect(
            x: screen.midX - notchWidth / 2,
            y: screen.maxY - notchHeight,
            width: notchWidth,
            height: notchHeight
        )
        ctx.addPath(notchPath(in: notch, top: 10, bottom: 22))
        ctx.setFillColor(rgb(0x000000))
        ctx.fillPath()
    }
    ctx.restoreGState()
}

// MARK: - Composition

/// Where a panel shot puts its display, in design units from the top edge: high enough for
/// a two-line headline above it, short enough that the panel is not floating in wallpaper.
let displayTop: CGFloat = 214
let displayHeight: CGFloat = 420

func compose(shot: Shot, language: String, capture: CGImage, size: CGSize) -> CGImage {
    let scale = size.width / design.width
    let ctx = context(size: size)
    ctx.scaleBy(x: scale, y: scale)
    ctx.interpolationQuality = .high

    // The studio behind the display.
    fill(ctx, CGRect(origin: .zero, size: design), canvasInk)
    glow(ctx, at: CGPoint(x: design.width / 2, y: design.height * 0.74), radius: 860, rgb(0x2A2350, 0.50))
    glow(ctx, at: CGPoint(x: design.width * 0.16, y: design.height * 0.14), radius: 640, rgb(0x2A1030, 0.50))
    vignette(ctx, inner: 420, outer: 1040, rgb(0x000000, 0.55))

    if shot.kind == .panel {
        // Narrow enough that the panel is not an island in the middle of a wide screen, wide
        // enough that both menu bar clusters have room beside the notch.
        let display = CGRect(
            x: 150,
            y: design.height - displayTop - displayHeight,
            width: design.width - 300,
            height: displayHeight
        )
        drawDisplay(display, panel: capture, context: ctx)
    }

    let copy = shot.copy[language]!
    let headlineStyle = TextStyle(
        font: NSFont.systemFont(ofSize: shot.kind == .panel ? 46 : 40, weight: .semibold),
        colour: ink,
        lineSpacing: 6
    )
    let subheadStyle = TextStyle(
        font: NSFont.systemFont(ofSize: 20, weight: .regular),
        colour: inkSecondary,
        lineSpacing: 5
    )

    switch shot.kind {
    case .panel:
        drawCentered(copy.headline, centreFromTop: 126, column: 1000, style: headlineStyle, context: ctx)
        if let subhead = copy.subhead {
            drawCentered(subhead, centreFromTop: 684, column: 880, style: subheadStyle, context: ctx)
        }

    case .window:
        drawCentered(copy.headline, centreFromTop: 74, column: 1000, style: headlineStyle, context: ctx)
        if let subhead = copy.subhead {
            drawCentered(subhead, centreFromTop: 122, column: 880, style: subheadStyle, context: ctx)
        }
        // The window at its own size — 480 × 598 points, from a 2× capture, so it stays
        // pixel-for-pixel what the app draws — centred in the room the caption leaves. It
        // is never enlarged: blown up, its text would stop being the size a user sees.
        let points = CGSize(width: CGFloat(capture.width) / 2, height: CGFloat(capture.height) / 2)
        let fit = min(1, 650 / points.height, 1000 / points.width)
        let window = CGRect(
            x: (design.width - points.width * fit) / 2,
            y: 52,
            width: points.width * fit,
            height: points.height * fit
        )
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 60, color: rgb(0x000000, 0.72))
        ctx.draw(capture, in: window)
        ctx.restoreGState()
    }

    guard let image = ctx.makeImage() else { fatalError("no image") }
    return image
}

func write(_ image: CGImage, to url: URL) {
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else { fatalError("no destination for \(url.path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(url.path)") }
    print(url.path)
}

// MARK: - Run

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(
        Data("usage: Compose.swift <raw-capture-directory> <output-directory> [en|fr] [--all-sizes]\n".utf8)
    )
    exit(2)
}

let rawDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
let outputDirectory = URL(fileURLWithPath: arguments[2], isDirectory: true)
let languages = arguments.dropFirst(3).first { $0 == "en" || $0 == "fr" }.map { [$0] } ?? ["en", "fr"]
let sizes = arguments.contains("--all-sizes") ? everySize : shippingSizes

/// The clock in the drawn menu bar: 9:41, the time Apple uses, in the language's format.
var clockText = "Tue 15 Sep 09:41"

/// The menu titles of the drawn menu bar. Painted, like the wallpaper: a real menu bar says
/// what the author had open, which is nobody's business on a store screenshot.
var menubarCopy = ["File", "Edit", "View", "Window", "Help"]

var written = 0
var missing: [String] = []

for language in languages {
    clockText = language == "fr" ? "mar. 15 sept. 09:41" : "Tue 15 Sep 09:41"
    menubarCopy = language == "fr"
        ? ["Fichier", "Édition", "Présentation", "Fenêtre", "Aide"]
        : ["File", "Edit", "View", "Window", "Help"]

    for shot in shots {
        guard let pick = framePicks[language]?[shot.capture] else { continue }
        let source = rawDirectory.appendingPathComponent("\(pick).png")
        guard FileManager.default.fileExists(atPath: source.path) else {
            missing.append("\(language)/\(pick)")
            continue
        }
        let capture = image(at: source)
        for size in sizes {
            let composed = compose(shot: shot, language: language, capture: capture, size: size)
            write(
                composed,
                to: outputDirectory
                    .appendingPathComponent(language)
                    .appendingPathComponent("\(Int(size.width))x\(Int(size.height))")
                    .appendingPathComponent("\(shot.slug).png")
            )
            written += 1
        }
    }
}

if !missing.isEmpty {
    FileHandle.standardError.write(
        Data("no capture yet for: \(missing.joined(separator: ", "))\n".utf8)
    )
}
print("\(written) images")
