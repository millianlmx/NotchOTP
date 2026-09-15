import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Lets the user frame a region of their screen(s) with the mouse and returns the
/// `otpauth://` payload of the QR code inside it.
///
/// One borderless overlay per screen is shown; the drag selects on the screen it started
/// on, the other overlays stay visible and disappear with it. The picker hides its own
/// overlays before capturing, so the selection never ends up in the screenshot.
@MainActor
public final class ScreenRegionPicker {

    /// Why a selection produced no payload. The caller only ever sees these, never a raw
    /// ScreenCaptureKit error.
    public enum Failure: Error, Equatable {
        /// Escape, right click, or a selection too small to be intentional.
        case cancelled
        /// Screen recording is not granted to this app (TCC).
        case permissionDenied
        case captureFailed(String)
        /// Nothing readable in the region, or no `otpauth://` QR code in it.
        case noCodeFound
    }

    /// Anything smaller (in points) is a stray click rather than a selection.
    private static let minimumSide: CGFloat = 8
    private static let escapeKeyCode: UInt16 = 53
    private static let hint = String(localized: "Sélectionne le QR code — Échap pour annuler")
    /// The window server needs a beat to actually take the overlays off screen, and the
    /// screenshot grabs whatever is composited right now.
    private static let overlayHideDelay = Duration.milliseconds(120)

    private struct Overlay {
        let screen: NSScreen
        let window: SelectionWindow
        let view: SelectionView
    }

    private var overlays: [Overlay] = []
    private var keyMonitor: Any?
    /// Set while `pickOTPAuthRegion()` is suspended; resumed exactly once.
    private var completion: ((Result<String, Failure>) -> Void)?
    /// Screen the drag started on — the only one we are allowed to capture.
    private var dragScreen: NSScreen?
    private var isCapturing = false

    public init() {}

    /// Shows the overlays and returns the payload of the `otpauth://` QR code the user
    /// framed. The overlays are closed on every exit path, success included.
    public func pickOTPAuthRegion() async throws(Failure) -> String {
        guard completion == nil else {
            throw Failure.captureFailed(String(localized: "Une sélection est déjà en cours."))
        }
        presentOverlays()

        let result: Result<String, Failure> = await withCheckedContinuation { continuation in
            completion = { continuation.resume(returning: $0) }
        }
        switch result {
        case .success(let payload):
            return payload
        case .failure(let failure):
            throw failure
        }
    }

    // MARK: - Overlays

    private func presentOverlays() {
        installKeyMonitor()
        overlays = NSScreen.screens.map { screen in
            let window = SelectionWindow(
                contentRect: CGRect(origin: .zero, size: screen.frame.size),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.hidesOnDeactivate = false
            window.animationBehavior = .none
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]

            let view = SelectionView(
                frame: CGRect(origin: .zero, size: screen.frame.size),
                screen: screen,
                hint: Self.hint
            )
            view.delegate = self
            window.contentView = view
            window.setFrame(screen.frame, display: false)
            window.orderFrontRegardless()
            return Overlay(screen: screen, window: window, view: view)
        }

        // Escape only reaches the key window, and the crosshair only shows once our app
        // owns the pointer.
        NSApp.activate()
        overlays.first { $0.screen.frame.contains(NSEvent.mouseLocation) }?
            .window.makeKeyAndOrderFront(nil)
        NSCursor.crosshair.set()
    }

    private func hideOverlays() {
        for overlay in overlays {
            overlay.window.orderOut(nil)
        }
    }

    /// Closes everything and resumes the caller; resumes at most once.
    private func finish(_ result: Result<String, Failure>) {
        let completion = self.completion
        self.completion = nil
        tearDownOverlays()
        isCapturing = false
        completion?(result)
    }

    private func tearDownOverlays() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        for overlay in overlays {
            overlay.window.close()
        }
        overlays.removeAll()
        dragScreen = nil
        NSCursor.arrow.set()
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == Self.escapeKeyCode else { return event }
            Task { @MainActor in self?.selectionDidCancel() }
            return nil
        }
    }

    // MARK: - Capture

    /// Captures `region` (in screen coordinates) and decodes the QR code inside it.
    /// Captures the region and returns the `otpauth://` payload inside it.
    /// Internal so the capture + decode chain can be exercised without a mouse drag.
    func captureOTPAuth(in region: CGRect, on screen: NSScreen) async -> Result<String, Failure> {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            return .failure(Self.failure(from: error))
        }

        guard let displayID = Self.displayID(of: screen) else {
            return .failure(.captureFailed(String(localized: "Écran de la sélection introuvable.")))
        }
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            return .failure(.captureFailed(String(localized: "Écran de la sélection absent de la liste de capture.")))
        }

        let configuration = SCStreamConfiguration()
        let source = Self.sourceRect(for: region, on: screen)
        configuration.sourceRect = source
        // `sourceRect` is in points, `width`/`height` in pixels: on a Retina screen the
        // selection must be scaled up or the captured region is a quarter of the area.
        let scale = screen.backingScaleFactor
        configuration.width = Int((source.width * scale).rounded())
        configuration.height = Int((source.height * scale).rounded())
        configuration.showsCursor = false
        configuration.capturesAudio = false
        // `colorSpaceName` is the SDK's `CFString` typed color space, not a `CGColorSpace`.
        configuration.colorSpaceName = CGColorSpace.sRGB

        let filter = SCContentFilter(display: display, excludingWindows: [])
        switch await Self.captureImage(filter: filter, configuration: configuration) {
        case .failure(let failure):
            return .failure(failure)
        case .success(let image):
            do {
                guard let payload = try BarcodeScanner.otpauthPayload(in: image) else {
                    return .failure(.noCodeFound)
                }
                return .success(payload)
            } catch {
                return .failure(.captureFailed(error.localizedDescription))
            }
        }
    }

    private static func captureImage(
        filter: SCContentFilter,
        configuration: SCStreamConfiguration
    ) async -> Result<CGImage, Failure> {
        await withCheckedContinuation { continuation in
            SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            ) { image, error in
                if let image {
                    continuation.resume(returning: .success(image))
                } else if let error {
                    continuation.resume(returning: .failure(failure(from: error)))
                } else {
                    continuation.resume(returning: .failure(.captureFailed(String(localized: "La capture d'écran a échoué."))))
                }
            }
        }
    }

    /// `sourceRect` is a point rectangle whose origin is the **top left** of that
    /// display, while the overlay works in Cocoa coordinates, whose origin is the bottom
    /// left of the main screen. Rounding outward to whole points keeps the pixel size a
    /// whole multiple of the backing scale.
    private nonisolated static func sourceRect(for region: CGRect, on screen: NSScreen) -> CGRect {
        let clipped = region.integral.intersection(screen.frame)
        return CGRect(
            x: clipped.minX - screen.frame.minX,
            y: screen.frame.maxY - clipped.maxY,
            width: clipped.width,
            height: clipped.height
        )
    }

    private nonisolated static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        let value = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
        if let number = value as? NSNumber { return CGDirectDisplayID(number.uint32Value) }
        if let identifier = value as? CGDirectDisplayID { return identifier }
        return nil
    }

    /// A refused screen-recording prompt reaches us as an `SCStreamError`, sometimes with
    /// a message and sometimes only with an error code; the app has to be able to tell
    /// the user it is a permission problem rather than a broken selection.
    nonisolated static func failure(from error: any Error) -> Failure {
        let error = error as NSError
        let declined = error.domain == SCStreamErrorDomain
            && error.code == SCStreamError.Code.userDeclined.rawValue
        let mentionsDenial = ["not authorized", "declined", "denied"].contains {
            error.localizedDescription.localizedCaseInsensitiveContains($0)
        }
        return declined || mentionsDenial
            ? .permissionDenied
            : .captureFailed(error.localizedDescription)
    }
}

// MARK: - Overlay callbacks

extension ScreenRegionPicker: SelectionOverlayDelegate {

    func selectionDidBegin(in view: SelectionView) {
        guard !isCapturing, dragScreen == nil else { return }
        dragScreen = view.hostScreen
    }

    func selectionDidEnd(in view: SelectionView, rect: CGRect) {
        guard !isCapturing, let dragScreen, dragScreen === view.hostScreen else { return }
        guard rect.width >= Self.minimumSide, rect.height >= Self.minimumSide else {
            finish(.failure(.cancelled))
            return
        }

        guard let window = view.window else {
            finish(.failure(.cancelled))
            return
        }
        // View coordinates → window coordinates → screen coordinates, while the overlays
        // are still alive.
        let region = window.convertToScreen(view.convert(rect, to: nil))
        isCapturing = true
        // The overlays must not show up in the screenshot they are triggering.
        hideOverlays()
        Task { @MainActor in
            try? await Task.sleep(for: Self.overlayHideDelay)
            finish(await captureOTPAuth(in: region, on: dragScreen))
        }
    }

    func selectionDidCancel() {
        guard !isCapturing else { return }
        finish(.failure(.cancelled))
    }
}

@MainActor
protocol SelectionOverlayDelegate: AnyObject {
    func selectionDidBegin(in view: SelectionView)
    func selectionDidEnd(in view: SelectionView, rect: CGRect)
    func selectionDidCancel()
}

/// Borderless windows refuse key status by default; we need it so the Escape monitor and
/// the crosshair cursor work.
final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Overlay content: dimmed screen, the selection punched through it, and the hint pill.
final class SelectionView: NSView {

    weak var delegate: (any SelectionOverlayDelegate)?

    /// Screen this overlay covers; the picker captures only the one the drag started on.
    let hostScreen: NSScreen

    private let hint: String
    private var anchor: CGPoint?
    private var selection: CGRect?

    init(frame: NSRect, screen: NSScreen, hint: String) {
        self.hostScreen = screen
        self.hint = hint
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    /// The first click must start the selection even though our app was not active.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        anchor = point
        selection = CGRect(origin: point, size: .zero)
        delegate?.selectionDidBegin(in: self)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        updateSelection(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        updateSelection(with: event)
        guard let selection, let delegate else { return }
        delegate.selectionDidEnd(in: self, rect: selection)
    }

    override func rightMouseDown(with event: NSEvent) {
        delegate?.selectionDidCancel()
    }

    /// Rectangle between the press point and the current point, in any drag direction.
    private func updateSelection(with event: NSEvent) {
        guard let anchor else { return }
        let point = convert(event.locationInWindow, from: nil)
        let rect = CGRect(
            x: min(anchor.x, point.x),
            y: min(anchor.y, point.y),
            width: abs(point.x - anchor.x),
            height: abs(point.y - anchor.y)
        )
        // Dragging past a screen edge keeps the part that is actually on this screen,
        // which is also what the capture will get.
        selection = rect.intersection(bounds)
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(NSColor.black.withAlphaComponent(0.25).cgColor)

        if let selection, !selection.isEmpty {
            // Even-odd fill leaves the selection untouched so the QR code stays readable.
            context.addRect(bounds)
            context.addRect(selection)
            context.fillPath(using: .evenOdd)
            drawBorder(around: selection, in: context)
        } else {
            context.fill(bounds)
        }
        drawHint(in: context)
    }

    private func drawBorder(around rect: CGRect, in context: CGContext) {
        // A true one-pixel border: points would be two pixels on a Retina screen.
        let hairline = 1 / (window?.backingScaleFactor ?? 2)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(hairline)
        context.stroke(rect.insetBy(dx: hairline / 2, dy: hairline / 2))

        let handle: CGFloat = 6
        context.setFillColor(NSColor.white.cgColor)
        for corner in [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
        ] {
            context.fill(
                CGRect(
                    x: corner.x - handle / 2,
                    y: corner.y - handle / 2,
                    width: handle,
                    height: handle
                )
            )
        }
    }

    private func drawHint(in context: CGContext) {
        let text = NSAttributedString(
            string: hint,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.white,
            ]
        )
        let size = text.size()
        let padding = CGSize(width: 14, height: 8)
        let pill = CGRect(
            x: bounds.midX - (size.width + padding.width * 2) / 2,
            y: bounds.maxY - size.height - padding.height * 2 - 24,
            width: size.width + padding.width * 2,
            height: size.height + padding.height * 2
        )
        context.setFillColor(NSColor.black.withAlphaComponent(0.65).cgColor)
        context.addPath(
            CGPath(
                roundedRect: pill,
                cornerWidth: pill.height / 2,
                cornerHeight: pill.height / 2,
                transform: nil
            )
        )
        context.fillPath()
        text.draw(at: CGPoint(x: pill.minX + padding.width, y: pill.minY + padding.height))
    }
}
