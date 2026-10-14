import AppKit
import Observation
import SwiftUI

/// Owns the notch panel: placement, hover handling and the expand/collapse animation.
@MainActor
@Observable
public final class NotchWindowController {

    /// A notched screen exists and the panel is on it.
    public private(set) var isAvailable = false
    public private(set) var isExpanded = false
    /// Size of the physical notch: what the panel is when collapsed.
    public private(set) var notchSize: CGSize = .zero
    /// Size of the expanded panel, as placed on this screen.
    public private(set) var panelSize: CGSize = NotchGeometry.expandedSize
    /// Height of the physical notch; expanded content starts below it.
    public var notchHeight: CGFloat { notchSize.height }
    /// The panel currently owns the keyboard, so shortcuts and arrow keys reach it.
    public private(set) var hasKeyboardFocus = false

    /// Called for Escape while the panel holds the keyboard. Handled here rather than in
    /// SwiftUI: the focusable view is rebuilt whenever the panel changes state, and a
    /// rebuilt view silently stops receiving key presses.
    public var onEscapeKey: (@MainActor () -> Void)?

    /// Called with `true` when the panel becomes visible, `false` when it collapses.
    public var onVisibilityChange: (@MainActor (Bool) -> Void)?

    /// While set, moving the pointer away no longer collapses the panel: an authentication
    /// prompt or a half-typed password must not be yanked off screen. Clicking outside
    /// still dismisses it.
    public var keepsPanelOpen = false

    private let panel: NotchPanel
    private var geometry: NotchGeometry?
    private var mouseMonitors: [Any] = []
    /// Number of event monitors actually installed; `addGlobalMonitorForEvents`
    /// returns nil when it cannot watch events, which would silently kill hover.
    private(set) var installedMonitorCount = 0
    private var defaultCenterObservers: [any NSObjectProtocol] = []
    private var workspaceObservers: [any NSObjectProtocol] = []
    private var pendingCollapse: Task<Void, Never>?
    private var pendingExpand: Task<Void, Never>?
    /// Hides the window once the collapse animation has played out.
    private var pendingHide: Task<Void, Never>?

    private static let collapseGrace = Duration.milliseconds(700)
    private static let expandDelay = Duration.milliseconds(140)

    public init() {
        self.panel = NotchPanel(contentRect: CGRect(origin: .zero, size: NotchGeometry.expandedSize))
    }

    // MARK: - Setup

    public func attach<Content: View>(_ content: Content) {
        let hosting = NSHostingView(rootView: content)
        hosting.frame = CGRect(origin: .zero, size: panel.frame.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
    }

    public func start() {
        installScreenObservers()
        installMouseMonitors()
        updateGeometry()
    }

    public func stop() {
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors.removeAll()
        installedMonitorCount = 0
        defaultCenterObservers.forEach(NotificationCenter.default.removeObserver)
        defaultCenterObservers.removeAll()
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers.removeAll()
        pendingCollapse?.cancel()
        pendingCollapse = nil
        pendingExpand?.cancel()
        pendingExpand = nil
        pendingHide?.cancel()
        pendingHide = nil
        panel.orderOut(nil)
    }

    private func installScreenObservers() {
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            defaultCenterObservers.append(
                center.addObserver(forName: name, object: panel, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        guard let self else { return }
                        self.hasKeyboardFocus = self.panel.isKeyWindow
                        // SwiftUI only sees key presses when its hosting view is the first
                        // responder; a fresh key window otherwise swallows them.
                        if self.panel.isKeyWindow, let content = self.panel.contentView {
                            self.panel.makeFirstResponder(content)
                        }
                        Log.panel.notice("panel focus \(self.panel.isKeyWindow, privacy: .public)")
                    }
                }
            )
        }
        for name in [
            NSApplication.didChangeScreenParametersNotification,
            NSWindow.didChangeScreenNotification,
        ] {
            defaultCenterObservers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.updateGeometry() }
                }
            )
        }
        workspaceObservers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.updateGeometry() }
            }
        )
    }

    private func installMouseMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .leftMouseDragged]
        // Global: movements happening in other apps (the usual case for a background app).
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }) {
            mouseMonitors.append(monitor)
        }
        // Local: movements delivered to our own panel. Without this, moving the pointer
        // into the expanded panel would stop the global monitor and the collapse
        // scheduled on the way in would fire under the cursor.
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            Task { @MainActor in self?.handle(event) }
            return event
        }) {
            mouseMonitors.append(monitor)
        }
        // Escape, but only while our panel owns the keyboard: a local keyboard monitor
        // needs no accessibility permission, and it survives SwiftUI rebuilding its views.
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { [weak self] event in
            guard event.keyCode == 53, self?.panel.isKeyWindow == true else { return event }
            Task { @MainActor in self?.onEscapeKey?() }
            return nil
        }) {
            mouseMonitors.append(monitor)
        }
        installedMonitorCount = mouseMonitors.count
    }

    /// What the pointer position implies, given the current state.
    enum PointerAction: Equatable {
        case expand
        case collapseNow
        case scheduleCollapse
        case cancelCollapse
        case none
    }

    nonisolated static func pointerAction(
        for location: CGPoint,
        geometry: NotchGeometry,
        isExpanded: Bool,
        isButtonDown: Bool = false,
        keepsPanelOpen: Bool = false
    ) -> PointerAction {
        if isExpanded {
            if geometry.expandedRect.contains(location) {
                return isButtonDown ? .none : .cancelCollapse
            }
            if isButtonDown { return .collapseNow }
            return keepsPanelOpen ? .cancelCollapse : .scheduleCollapse
        }
        return geometry.hoverRect.contains(location) ? .expand : .none
    }

    // MARK: - Geometry

    private static func geometry(for screen: NSScreen) -> NotchGeometry? {
        NotchGeometry(
            screenFrame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea
        )
    }

    private func notchedScreen() -> (NSScreen, NotchGeometry)? {
        if let main = NSScreen.main, let geometry = Self.geometry(for: main) {
            return (main, geometry)
        }
        for screen in NSScreen.screens {
            if let geometry = Self.geometry(for: screen) {
                return (screen, geometry)
            }
        }
        return nil
    }

    private func updateGeometry() {
        guard let (_, geometry) = notchedScreen() else {
            isAvailable = false
            self.geometry = nil
            if isExpanded {
                isExpanded = false
                onVisibilityChange?(false)
            }
            panel.orderOut(nil)
            return
        }

        // Screen notifications fire for things that change nothing here (another window
        // of ours appearing, a tooltip); a redundant `setFrame(display: true)` would still
        // force a synchronous redraw of the open panel.
        guard geometry != self.geometry else { return }
        self.geometry = geometry
        isAvailable = true
        notchSize = geometry.notchRect.size
        panelSize = geometry.expandedRect.size
        // The window never changes size: the panel is drawn inside it by SwiftUI, and
        // the transparent remainder lets pointer events through. It is only on screen
        // while there is something to draw.
        panel.setFrame(geometry.windowRect, display: true)
        if isExpanded { panel.orderFrontRegardless() }
    }

    // MARK: - Expansion

    public func expand() {
        setExpanded(true)
    }

    public func collapse() {
        setExpanded(false)
    }

    private func setExpanded(_ expanded: Bool) {
        guard isAvailable, geometry != nil, isExpanded != expanded else { return }
        Log.panel.notice("panel \(expanded ? "expanding" : "collapsing", privacy: .public)")
        cancelPendingCollapse()
        pendingExpand?.cancel()
        pendingExpand = nil
        pendingHide?.cancel()
        pendingHide = nil

        if expanded {
            panel.orderFrontRegardless()
        } else {
            setKeyInput(false)
        }

        // One spring, owned by SwiftUI: the surface and the content follow the same clock,
        // and a hover that reverses mid-flight retargets it instead of fighting a second
        // animator. Reduce Motion gets a short cross-fade with no movement.
        withAnimation(PanelStyle.reducesMotion ? PanelStyle.reducedMotion : PanelStyle.spring) {
            isExpanded = expanded
        }

        if !expanded {
            // Collapsed, the panel draws nothing: once the spring has settled the window can
            // go, so no invisible surface sits over the user's windows.
            pendingHide = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(650))
                guard let self, !Task.isCancelled, !self.isExpanded else { return }
                self.panel.orderOut(nil)
            }
        }

        onVisibilityChange?(expanded)
    }

    /// Lets the panel take key status without activating the app: an embedded biometric
    /// prompt is interactive and macOS routes the sensor to it only when it can take focus.
    public func makeKeyForPrompt() {
        panel.allowsKeyInput = true
        if !panel.isKeyWindow { panel.makeKey() }
        Log.panel.notice("panel key for prompt: isKey=\(self.panel.isKeyWindow) canBecomeKey=\(self.panel.canBecomeKey)")
    }

    /// Enables keyboard input in the panel; required while a password field is visible.
    /// Lets the panel take key status *without* activating the app: a deliberate click
    /// inside gives it the keyboard, hovering never does.
    public func allowKeyStatus(_ allowed: Bool) {
        panel.allowsKeyInput = allowed
        panel.becomesKeyOnlyIfNeeded = false
        if !allowed, panel.isKeyWindow {
            panel.resignKey()
        }
    }

    public func setKeyInput(_ enabled: Bool) {
        panel.allowsKeyInput = enabled
        if enabled {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKey()
        } else if panel.isKeyWindow {
            panel.resignKey()
        }
    }

    // MARK: - Mouse

    private func handle(_ event: NSEvent) {
        guard let geometry else { return }
        let isButtonDown = event.type == .leftMouseDown || event.type == .leftMouseDragged
        let location = screenLocation(of: event)

        switch Self.pointerAction(
            for: location,
            geometry: geometry,
            isExpanded: isExpanded,
            isButtonDown: isButtonDown,
            keepsPanelOpen: keepsPanelOpen
        ) {
        case .expand:
            scheduleExpand()
        case .collapseNow:
            collapse()
        case .scheduleCollapse:
            scheduleCollapse()
        case .cancelCollapse:
            cancelPendingCollapse()
            pendingExpand?.cancel()
            pendingExpand = nil
        case .none:
            pendingExpand?.cancel()
            pendingExpand = nil
        }
    }

    /// Where the event happened, in screen coordinates.
    ///
    /// `NSEvent.mouseLocation` reads the *current* cursor position, which is not the same
    /// thing as the position of the event being handled — and it made this whole path
    /// impossible to exercise without a real mouse. Events that already carry a window
    /// are converted from it; global monitor events (other apps) fall back to the cursor.
    private func screenLocation(of event: NSEvent) -> CGPoint {
        guard let window = event.window else { return NSEvent.mouseLocation }
        return window.convertPoint(toScreen: event.locationInWindow)
    }

    private func cancelPendingCollapse() {
        pendingCollapse?.cancel()
        pendingCollapse = nil
    }

    private func scheduleExpand() {
        guard pendingExpand == nil else { return }
        pendingExpand = Task { [weak self] in
            try? await Task.sleep(for: Self.expandDelay)
            guard !Task.isCancelled else { return }
            self?.pendingExpand = nil
            self?.expand()
        }
    }

    private func scheduleCollapse() {
        guard pendingCollapse == nil else { return }
        pendingCollapse = Task { [weak self] in
            try? await Task.sleep(for: Self.collapseGrace)
            guard !Task.isCancelled else { return }
            self?.pendingCollapse = nil
            self?.collapse()
        }
    }
}
