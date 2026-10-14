import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Captures the panel by itself, in the states the App Store screenshots need.
///
/// Two things make the difference between a usable capture and a throwaway one:
///
/// * the panel is grabbed *alone* — `screencapture -l`, which keeps the alpha, drops the
///   shadow and leaves the desktop out, so the composition is the only thing that decides
///   what surrounds it;
/// * the states that only last a moment are caught by bursting. The confirmation sheet
///   lives 900 ms in demo mode before the fake finger answers, and the revealed code goes
///   away with its own TOTP window: timing one shot would fail most runs, so this takes a
///   burst and lets the caller pick.
///
///     swift Scripts/Screenshots/Capture.swift list    en build/screenshots/raw
///     swift Scripts/Screenshots/Capture.swift confirm fr build/screenshots/raw
///     swift Scripts/Screenshots/Capture.swift settings en build/screenshots/raw

// MARK: - Arguments

let usage = "usage: Capture.swift <list|confirm|settings> <en|fr> <output-directory> [path-to-app]"

guard CommandLine.arguments.count >= 4 else {
    FileHandle.standardError.write(Data("\(usage)\n".utf8))
    exit(2)
}

let state = CommandLine.arguments[1]
let language = CommandLine.arguments[2]
let output = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
let app = URL(
    fileURLWithPath: CommandLine.arguments.count > 4
        ? CommandLine.arguments[4]
        : "build/NotchOTP.app"
)

/// One state: the launch arguments it needs, and how long to keep watching for it.
///
/// The burst starts before the thing being looked for can appear, and the interval is short
/// enough that the shortest-lived state — the sheet, which lives the 900 ms the demo's fake
/// sensor takes to answer — lands in a good number of frames. The frames to keep are then
/// picked from the middle of each state's window, in `Compose.swift`, so an ordinary
/// variation in launch timing does not land on the wrong one.
let plan: (arguments: [String], burst: Int, interval: Duration)

switch state {
case "list":
    plan = (["-demo", "-panel"], burst: 6, interval: .milliseconds(250))
case "confirm":
    plan = (["-demo", "-panel", "-confirm"], burst: 60, interval: .milliseconds(80))
case "settings":
    plan = (["-demo", "-settings"], burst: 20, interval: .milliseconds(250))
default:
    FileHandle.standardError.write(Data("\(usage)\n".utf8))
    exit(2)
}

// MARK: - Window discovery

/// The window to capture: the only NotchOTP window bigger than the collapsed notch.
///
/// The panel is 420 × 340 and the preferences window 480 × 570; the collapsed notch is
/// 185 × 32 and is skipped by the width test, whatever state the panel is in.
func targetWindows() -> [[String: Any]] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    return windows.filter { window in
        guard window[kCGWindowOwnerName as String] as? String == "NotchOTP",
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let width = bounds["Width"] as? CGFloat,
              let height = bounds["Height"] as? CGFloat
        else { return false }
        return width > 300 && height > 200
    }
}

// MARK: - Process helpers

func run(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw Failure.command(executable, process.terminationStatus)
    }
}

enum Failure: LocalizedError {
    case command(String, Int32)
    case noWindow(String)

    var errorDescription: String? {
        switch self {
        case .command(let tool, let status): "\(tool) exited with \(status)"
        case .noWindow(let state): "no NotchOTP window on screen for « \(state) »"
        }
    }
}

// MARK: - Contact sheet

/// Tiles a burst into one image, each frame numbered, so the frame to keep can be picked by
/// looking rather than by guessing. The number is the two digits of the file name.
func writeContactSheet(_ files: [URL], to url: URL) {
    let tile = CGSize(width: 280, height: 227)
    let columns = 8
    let rows = (files.count + columns - 1) / columns
    let size = CGSize(
        width: CGFloat(columns) * (tile.width + 6) + 6,
        height: CGFloat(max(rows, 1)) * (tile.height + 26) + 6
    )
    guard let ctx = CGContext(
        data: nil,
        width: Int(size.width),
        height: Int(size.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return }

    ctx.setFillColor(CGColor(srgbRed: 0.10, green: 0.10, blue: 0.12, alpha: 1))
    ctx.fill(CGRect(origin: .zero, size: size))
    ctx.interpolationQuality = .high

    let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    for (index, file) in files.enumerated() {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { continue }
        let column = index % columns
        let row = index / columns
        // The context is bottom-left origin: the first frame goes top-left.
        let origin = CGPoint(
            x: 6 + CGFloat(column) * (tile.width + 6),
            y: size.height - 6 - CGFloat(row + 1) * (tile.height + 26)
        )
        let slot = CGRect(origin: origin, size: tile)
        // The panel (840 × 680) and the settings window (960 × 1196) do not share an aspect
        // ratio, so each frame is fitted into its slot rather than drawn at a fixed size.
        let room = slot.insetBy(dx: 12, dy: 26)
        let fit = min(room.width / CGFloat(image.width), room.height / CGFloat(image.height))
        ctx.draw(image, in: CGRect(
            x: slot.midX - CGFloat(image.width) * fit / 2,
            y: slot.minY + 20,
            width: CGFloat(image.width) * fit,
            height: CGFloat(image.height) * fit
        ))

        let number = String(format: "%02d", index)
        let attributed = NSAttributedString(string: number, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key:
                CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.9),
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        ctx.textPosition = CGPoint(x: slot.minX + 12, y: slot.minY + 2)
        CTLineDraw(line, ctx)
    }

    guard let sheet = ctx.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
              url as CFURL,
              UTType.png.identifier as CFString,
              1,
              nil
          )
    else { return }
    CGImageDestinationAddImage(destination, sheet, nil)
    CGImageDestinationFinalize(destination)
    print("contact sheet: \(url.lastPathComponent)")
}

// MARK: - Run

try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

// A leftover instance would hold its own panel, and two panels on screen make the window
// pick a coin toss. `NSRunningApplication` misses a process whose launch is still settling,
// so the match is made on the executable path instead.
try? run("/usr/bin/pkill", ["-f", "NotchOTP.app/Contents/MacOS/NotchOTP"])
try? await Task.sleep(for: .milliseconds(400))

let configuration = NSWorkspace.OpenConfiguration()
configuration.arguments =
    plan.arguments + ["-AppleLanguages", "(\(language))"]
// The panel draws the same whether the app is frontmost or not; a window with a title bar
// and a tab strip does not — inactive windows grey their controls out. The settings shot
// is the one that has to be taken with the app in front.
configuration.activates = state == "settings"

let instance: NSRunningApplication
do {
    instance = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
} catch {
    FileHandle.standardError.write(Data("could not launch \(app.path): \(error)\n".utf8))
    exit(1)
}

var captured = 0
var writtenFrames: [URL] = []
do {
    for frame in 0..<plan.burst {
        // The expand animation (0.34 s), the demo listing and the SwiftUI render of a fresh
        // window all take a moment: a frame without a window is skipped, not fatal.
        try await Task.sleep(for: plan.interval)

        guard let window = targetWindows().first,
              let number = window[kCGWindowNumber as String] as? Int
        else { continue }

        let file = output.appendingPathComponent(
            String(format: "%@-%@-%02d.png", state, language, frame)
        )
        // A window that has just been created has no surface to grab yet, and
        // `screencapture` says so instead of writing a file: that frame is simply skipped.
        do {
            try run("/usr/sbin/screencapture", ["-x", "-o", "-l", String(number), file.path])
        } catch {
            try? FileManager.default.removeItem(at: file)
            continue
        }
        captured += 1
        writtenFrames.append(file)

        let bounds = window[kCGWindowBounds as String] as? [String: Any]
        let width = bounds?["Width"] as? CGFloat ?? 0
        print("\(file.lastPathComponent)  \(Int(width)) pt wide")
    }

    if captured == 0 { throw Failure.noWindow(state) }
    writeContactSheet(
        writtenFrames,
        to: output.appendingPathComponent("contact-\(state)-\(language).png")
    )
} catch {
    instance.terminate()
    FileHandle.standardError.write(Data("capture failed: \(error)\n".utf8))
    exit(1)
}

instance.terminate()
