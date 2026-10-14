// Drives a review recording of NotchOTP with synthetic pointer and keyboard input.
//
//   swift Scripts/Review/Recorder.swift --app <NotchOTP.app> [--demo] [--finger-wait 40]
//                                       [--no-paste] [--print-geometry]
//                                       [--marketing --timeline <file.json> --capture-start <epoch>]
// Started by Scripts/record-review-video.sh, which owns the recording itself; this file
// only acts.
//
// `--marketing` plays the short take Scripts/Marketing/record-clips.sh cuts into the
// Remotion video: hover, confirm one code, search, lock, leave. Each step is written to
// `--timeline` as seconds since `--capture-start`, so the cuts are computed, not eyeballed.
//
// It needs the **Accessibility** permission for whatever runs it: without it CGEvent
// posts are accepted by the kernel and then dropped on the floor, and every gesture
// below would silently do nothing. `--print-geometry` runs without any permission and
// prints where each target lands, which is the way to check the arithmetic.
//
// The coordinates are derived, not measured: the panel is 420 × 340 hung from the top
// edge (`NotchGeometry.expandedSize`), its header is 44 pt (`PanelStyle.headerHeight`),
// its rows 48 pt separated by 1 (`PanelStyle.rowHeight`, `VStack(spacing: 1)`), and the
// four header buttons are 26 pt wide, 10 apart, inset by `PanelStyle.horizontalPadding`
// = 16 — read those constants in the app if this ever drifts.

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - Progress

private let clock: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter
}()

func step(_ text: String) {
    print("[\(clock.string(from: Date()))] \(text)")
    fflush(stdout)
}

func pause(_ seconds: Double) {
    Thread.sleep(forTimeInterval: seconds)
}

// MARK: - Geometry

/// Where the panel is, in CoreGraphics global coordinates (origin top-left of the main
/// display, y growing downwards) — the space `CGEvent` wants.
struct Panel {
    /// Height of the physical notch, which is where the panel starts drawing.
    let notchHeight: CGFloat
    /// The expanded panel.
    let rect: CGRect

    static let headerHeight: CGFloat = 44
    static let rowHeight: CGFloat = 48
    static let rowSpacing: CGFloat = 1
    static let buttonSize: CGFloat = 26
    static let buttonSpacing: CGFloat = 10
    static let horizontalPadding: CGFloat = 16

    init?(notched screen: NSScreen, main: NSScreen) {
        let top = screen.safeAreaInsets.top
        guard top > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea,
              left.width > 0, right.width > 0
        else { return nil }

        let width = screen.frame.width - left.width - right.width
        guard width > 0 else { return nil }

        // NSScreen is bottom-left; the panel hangs from the top of the main display.
        let height = min(340, screen.frame.height)
        let panelWidth = min(420, screen.frame.width)
        let originX = min(max(left.maxX + width / 2 - panelWidth / 2, screen.frame.minX), screen.frame.maxX - panelWidth)

        self.notchHeight = top
        self.rect = CGRect(
            x: originX - main.frame.minX,
            y: main.frame.maxY - screen.frame.maxY,
            width: panelWidth,
            height: height
        )
    }

    /// Just under the notch: the 4 pt of `hoverMargin` reach down to `notchHeight + 4`,
    /// and the menu bar ends at `notchHeight + 1`, so this is content-area pointer travel.
    var hoverPoint: CGPoint {
        CGPoint(x: rect.midX, y: notchHeight + 2)
    }

    /// Centre of the account at `index`, from the top of the list.
    func row(_ index: Int) -> CGPoint {
        let firstRowTop = notchHeight + Self.headerHeight + 1
        let y = firstRowTop + Self.rowHeight / 2 + CGFloat(index) * (Self.rowHeight + Self.rowSpacing)
        return CGPoint(x: rect.midX, y: y)
    }

    /// Blank header, between the title and the buttons: a click here does nothing but
    /// give the panel key status.
    var headerBlank: CGPoint {
        CGPoint(x: rect.minX + 230, y: notchHeight + Self.headerHeight / 2)
    }

    /// Header buttons, right to left: `gearshape`, `lock.fill`, `plus`, `magnifyingglass`.
    /// `magnifyingglass` is the fourth: it only exists once the key is ready and the
    /// accounts are listed (`NotchRootView.header`).
    enum Button: Int {
        case settings = 0, lock, add, search
    }

    func button(_ which: Button) -> CGPoint {
        let centre = rect.maxX - Self.horizontalPadding - Self.buttonSize / 2
        return CGPoint(
            x: centre - CGFloat(which.rawValue) * (Self.buttonSize + Self.buttonSpacing),
            y: notchHeight + Self.headerHeight / 2
        )
    }

    /// The search field, under the header, once the magnifier has been pressed.
    var searchField: CGPoint {
        CGPoint(x: rect.midX, y: notchHeight + Self.headerHeight + 1 + 30)
    }
}

// MARK: - Input

final class Input {

    private let source = CGEventSource(stateID: .hidSystemState)
    private var pointer: CGPoint?

    /// Moves in steps so the app's hover tracking sees travel rather than a teleport,
    /// and so the recording shows a cursor a human could have moved.
    func glide(to point: CGPoint, steps: Int = 8) {
        let from = pointer ?? point
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let eased = t * t * (3 - 2 * t)
            move(to: CGPoint(x: from.x + (point.x - from.x) * eased,
                             y: from.y + (point.y - from.y) * eased))
            usleep(12_000)
        }
        move(to: point)
        pause(0.05)
    }

    func move(to point: CGPoint) {
        pointer = point
        post(.mouseMoved, at: point)
    }

    func click(_ point: CGPoint, button: CGMouseButton = .left) {
        glide(to: point, steps: 4)
        let down: CGEventType = button == .right ? .rightMouseDown : .leftMouseDown
        let up: CGEventType = button == .right ? .rightMouseUp : .leftMouseUp
        post(down, at: point, button: button)
        usleep(70_000)
        post(up, at: point, button: button)
    }

    func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        usleep(30_000)
        up.post(tap: .cghidEventTap)
        usleep(30_000)
    }

    func type(_ text: String) {
        for character in text {
            var units = Array(String(character).utf16)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { continue }
            down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            down.post(tap: .cghidEventTap)
            usleep(18_000)
            up.post(tap: .cghidEventTap)
            usleep(28_000)
        }
    }

    private func post(_ type: CGEventType, at point: CGPoint, button: CGMouseButton = .left) {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: button) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.post(tap: .cghidEventTap)
    }
}

private let keyV: CGKeyCode = 9
private let keyW: CGKeyCode = 13
private let keyEscape: CGKeyCode = 53
private let command = CGEventFlags.maskCommand

// MARK: - Applications

func launch(_ path: String, arguments: [String] = []) {
    let semaphore = DispatchSemaphore(value: 0)
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.arguments = arguments
    configuration.activates = false
    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: configuration) { _, error in
        if let error { step("launch failed: \(error.localizedDescription)") }
        semaphore.signal()
    }
    semaphore.wait()
}

/// A second instance, so the paste can never land in a document the user already had
/// open — and an explicit file rather than a new untitled document, because TextEdit
/// autosaves untitled documents into the user's iCloud folder, where they pile up.
func launchFreshInstance(_ path: String, extra: [String] = []) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-na", path] + extra
    try? process.run()
    process.waitUntilExit()
}

func isRunning(_ bundlePath: String) -> Bool {
    NSWorkspace.shared.runningApplications.contains {
        $0.bundleURL?.path == URL(fileURLWithPath: bundlePath).resolvingSymlinksInPath().path
            || $0.bundleURL?.path == bundlePath
    }
}

func runningPID(_ bundlePath: String) -> pid_t? {
    let path = URL(fileURLWithPath: bundlePath).resolvingSymlinksInPath().path
    return NSWorkspace.shared.runningApplications.first {
        $0.bundleURL?.resolvingSymlinksInPath().path == path
    }?.processIdentifier
}

func textEditPIDs() -> Set<pid_t> {
    Set(NSWorkspace.shared.runningApplications
        .filter { $0.bundleIdentifier == "com.apple.TextEdit" }
        .map(\.processIdentifier))
}

// MARK: - Is the panel actually open?

func axFrame(of element: AXUIElement) -> CGRect? {
    var positionRef: CFTypeRef?
    var sizeRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
          AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
          let positionValue = positionRef, let sizeValue = sizeRef,
          CFGetTypeID(positionValue) == AXValueGetTypeID(),
          CFGetTypeID(sizeValue) == AXValueGetTypeID()
    else { return nil }

    var origin = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
          AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
    else { return nil }
    return CGRect(origin: origin, size: size)
}

/// `true` expanded, `false` collapsed, `nil` when the app has no window to ask about.
///
/// The panel window is only on screen while the panel is open (it is ordered out
/// ~650 ms after a collapse, once the closing spring has played), and it is the only
/// window of the app that is this large and hung from the top edge — so a window that
/// matches *is* the open panel. This is what keeps the driver from clicking blind: with
/// the panel closed, a click at the row coordinates lands on whatever is behind it —
/// the user's own windows.
func panelIsExpanded(pid: pid_t) -> Bool? {
    let app = AXUIElementCreateApplication(pid)
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
          let windows = value as? [AXUIElement], !windows.isEmpty
    else { return nil }

    var saw = false
    for window in windows {
        guard let frame = axFrame(of: window) else { continue }
        saw = true
        if frame.width >= 400, frame.height >= 300, frame.origin.y < 5 { return true }
    }
    return saw ? false : nil
}

// MARK: - Options

struct Options {
    var appPath: String?
    var demo = false
    var fingerWait: Double = 6
    var paste = true
    var printGeometry = false
    var marketing = false
    var timelinePath: String?
    var captureStart: Double?

    static func parse() -> Options {
        var options = Options()
        var arguments = Array(CommandLine.arguments.dropFirst())
        while !arguments.isEmpty {
            let argument = arguments.removeFirst()
            switch argument {
            case "--app": options.appPath = arguments.first
                arguments.removeFirst()
            case "--demo": options.demo = true
            case "--finger-wait": options.fingerWait = Double(arguments.first ?? "") ?? 6
                arguments.removeFirst()
            case "--no-paste": options.paste = false
            case "--print-geometry": options.printGeometry = true
            case "--marketing": options.marketing = true
            case "--timeline": options.timelinePath = arguments.first
                arguments.removeFirst()
            case "--capture-start": options.captureStart = Double(arguments.first ?? "")
                arguments.removeFirst()
            default: FileHandle.standardError.write(Data("unknown argument \(argument)\n".utf8))
            }
        }
        return options
    }
}

// MARK: - Main

let options = Options.parse()

guard let main = NSScreen.screens.first else {
    FileHandle.standardError.write(Data("no screen\n".utf8))
    exit(1)
}
guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil }),
      let panel = Panel(notched: screen, main: main)
else {
    FileHandle.standardError.write(Data("no notched screen: the panel does not exist here\n".utf8))
    exit(1)
}

if options.printGeometry {
    print("""
    screen          \(screen.frame)
    notch height    \(panel.notchHeight)
    panel           \(panel.rect)
    hover point     \(panel.hoverPoint)
    row 0..3        \(panel.row(0)) \(panel.row(1)) \(panel.row(2)) \(panel.row(3))
    buttons         search \(panel.button(.search))  add \(panel.button(.add))  lock \(panel.button(.lock))  settings \(panel.button(.settings))
    search field    \(panel.searchField)
    """)
    exit(0)
}

guard let appPath = options.appPath, FileManager.default.fileExists(atPath: appPath) else {
    FileHandle.standardError.write(Data("--app needs the path of a built NotchOTP.app\n".utf8))
    exit(1)
}

// Without this the kernel accepts every post below and drops it: the take would be a
// minute of the app sitting there, and nothing would say so until it was watched.
guard AXIsProcessTrusted() else {
    FileHandle.standardError.write(Data("""
    No Accessibility permission: the synthetic events would be dropped silently, and the
    recording would show nothing happening.

    System Settings > Privacy & Security > Accessibility — enable the app that runs this
    (the terminal or agent host), then run again. Restart that app if the switch was
    already on: TCC applies the grant at its next launch.

    """.utf8))
    exit(3)
}

let input = Input()
// The marketing take is in English whatever the Mac's language: the thread is.
let arguments = (options.demo ? ["-demo"] : []) + (options.marketing ? ["-AppleLanguages", "(en)"] : [])
let textEdit = "/System/Applications/TextEdit.app"

func fail(_ reason: String) -> Never {
    FileHandle.standardError.write(Data("\n\(reason)\n".utf8))
    exit(4)
}

/// Opens the panel, and refuses to go on until the app confirms it is there.
///
/// Hovering is the only input here with no immediate effect, and the app can still be
/// installing its mouse monitors just after launch — the first attempt missed on a run
/// that had started 2.5 s earlier. `expandDelay` is 140 ms and the spring 340 ms, so a
/// retry is cheap. The retry is not the important part: the check is. Every click below
/// is relative to the panel, and with the panel closed those coordinates land on the
/// user's own windows.
func openPanel(pid: pid_t) {
    for attempt in 1...6 {
        input.glide(to: panel.hoverPoint, steps: attempt == 1 ? 10 : 6)
        for _ in 0..<12 {
            if panelIsExpanded(pid: pid) == true { return }
            pause(0.2)
        }
        step("hover \(attempt): the panel has not opened yet")
    }
    fail("the panel never opened — stopping before a single blind click")
}

func clickInPanel(_ point: CGPoint, pid: pid_t, button: CGMouseButton = .left) {
    guard panelIsExpanded(pid: pid) == true else {
        fail("the panel is closed: a click at \(point) would land on whatever is behind it")
    }
    input.click(point, button: button)
}

step("launch \(URL(fileURLWithPath: appPath).lastPathComponent) \(arguments.joined(separator: " "))")
launch(appPath, arguments: arguments)

var launched = 0
while launched < 40, runningPID(appPath) == nil {
    pause(0.25)
    launched += 1
}
guard let pid = runningPID(appPath) else { fail("the app did not start") }
pause(1.8)

if options.marketing {
    // Offsets into the recording, for the cuts. The capture started before this process
    // was even compiled, so the shell passes its start; the dates here are absolute.
    var marks: [(name: String, at: Date)] = []
    func mark(_ name: String) {
        marks.append((name, Date()))
        step(name)
    }

    mark("hover")
    openPanel(pid: pid)
    pause(2.2)

    // The first click into the freshly opened panel only gives it key status: a row's
    // tap gesture does not fire on it (a header button would). Typed text never reaches
    // the search field from here either (synthetic keys go to the active app, and the
    // panel cannot activate NotchOTP on this macOS), so the focus click lands on the
    // blank part of the header and the video cuts it out: `focus` → `confirm`.
    mark("focus")
    clickInPanel(panel.headerBlank, pid: pid)
    pause(1.0)

    mark("confirm")
    input.glide(to: panel.row(1), steps: 8)
    pause(0.4)
    clickInPanel(panel.row(1), pid: pid)
    pause(1.0)
    pause(options.fingerWait)
    pause(1.6)  // the sheet closes 900 ms after the code is handed over
    mark("code")
    input.glide(to: CGPoint(x: panel.rect.midX, y: panel.rect.maxY - 30), steps: 4)
    pause(3.0)

    mark("lock")
    clickInPanel(panel.button(.lock), pid: pid)
    pause(2.0)

    mark("leave")
    input.glide(to: CGPoint(x: panel.rect.midX, y: panel.rect.maxY + 260), steps: 14)
    pause(2.2)
    mark("done")

    if let path = options.timelinePath {
        let origin = options.captureStart ?? marks.first!.at.timeIntervalSince1970
        let entries = marks.map { mark -> [String: Any] in
            ["name": mark.name, "at": ((mark.at.timeIntervalSince1970 - origin) * 1000).rounded() / 1000]
        }
        let json = try! JSONSerialization.data(withJSONObject: entries, options: [.prettyPrinted])
        try! json.write(to: URL(fileURLWithPath: path))
        step("timeline written to \(path)")
    }
    exit(0)
}

step("hover the notch")
openPanel(pid: pid)
pause(0.5)

step("search")
clickInPanel(panel.button(.search), pid: pid)
pause(0.7)
clickInPanel(panel.searchField, pid: pid)
input.type("git")
pause(1.1)
input.key(keyEscape)          // closes the search
pause(0.5)

step("confirm the first account")
clickInPanel(panel.row(0), pid: pid)
pause(1.0)
step("waiting up to \(Int(options.fingerWait)) s for the confirmation")
pause(options.fingerWait)
pause(1.6)  // the sheet closes 900 ms after the code is handed over

step("code is in the clipboard")
input.glide(to: CGPoint(x: panel.rect.midX, y: panel.notchHeight + 120), steps: 4)
pause(1.8)

if options.paste {
    // A scratch file, never an untitled document: TextEdit autosaves those into the
    // user's iCloud folder, and three takes left three of them behind. `open -na` gives
    // this take its own instance, so the paste cannot reach a document already open.
    //
    // The instance is then killed rather than quit: ⌘W raises a save sheet and ⌘Q never
    // gets past it — the first runs left a TextEdit running for every take. Only pids
    // that appeared during this take are touched, so a TextEdit the user has open is
    // never in the set.
    let scratch = NSTemporaryDirectory() + "NotchOTP clipboard check.txt"
    FileManager.default.createFile(atPath: scratch, contents: Data())
    step("open \(scratch) in a fresh TextEdit instance and paste")

    let before = textEditPIDs()
    launchFreshInstance(textEdit, extra: [scratch])
    var fresh: Set<pid_t> = []
    for _ in 0..<40 {
        fresh = textEditPIDs().subtracting(before)
        if !fresh.isEmpty { break }
        pause(0.25)
    }

    pause(1.6)
    input.key(keyV, flags: command)   // the code really is in the clipboard
    pause(3.0)                        // long enough to read it on screen
    for pid in fresh { kill(pid, SIGKILL) }
    pause(1.2)

    try? FileManager.default.removeItem(atPath: scratch)
}

step("back to the panel, show the list and the clipboard countdown")
openPanel(pid: pid)
pause(2.4)

step("settings")
clickInPanel(panel.button(.settings), pid: pid)
pause(2.6)
input.key(keyW, flags: command)
pause(1.0)

step("right-click a row, then lock")
openPanel(pid: pid)
pause(1.0)
clickInPanel(panel.row(1), pid: pid, button: .right)
pause(2.0)
input.key(keyEscape)
pause(0.8)
clickInPanel(panel.button(.lock), pid: pid)
pause(1.6)

step("leave the notch")
input.glide(to: CGPoint(x: panel.rect.minX - 300, y: 400), steps: 14)
pause(2.0)

step("done — \(isRunning(appPath) ? "app still running" : "app is gone")")
