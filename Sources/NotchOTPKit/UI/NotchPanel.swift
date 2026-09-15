import AppKit

/// Borderless, transparent, non-activating panel pinned under the notch.
///
/// Non-activating means clicking it never steals focus from the frontmost app;
/// keyboard input is enabled only while a text field is on screen (password prompt).
final class NotchPanel: NSPanel {

    var allowsKeyInput = false

    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        level = .statusBar
        // The panel is a black surface like the notch itself, so its semantic colours
        // must resolve for a dark surface whatever the user's system appearance is.
        appearance = NSAppearance(named: .darkAqua)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { allowsKeyInput }
    override var canBecomeMain: Bool { false }
}
