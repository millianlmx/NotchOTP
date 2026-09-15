import AppKit
import CoreGraphics
import Testing

@testable import YubicoNotchKit

private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

private let notch = NotchGeometry(
    screenFrame: screen,
    safeAreaTop: 37,
    auxiliaryTopLeftArea: CGRect(x: 0, y: 945, width: 656, height: 37),
    auxiliaryTopRightArea: CGRect(x: 856, y: 945, width: 656, height: 37)
)!

private func action(
    _ point: CGPoint,
    expanded: Bool,
    buttonDown: Bool = false,
    pinned: Bool = false
) -> NotchWindowController.PointerAction {
    NotchWindowController.pointerAction(
        for: point,
        geometry: notch,
        isExpanded: expanded,
        isButtonDown: buttonDown,
        keepsPanelOpen: pinned
    )
}

@Test func hoveringTheCollapsedNotchExpandsIt() {
    #expect(action(CGPoint(x: notch.notchRect.midX, y: notch.notchRect.midY), expanded: false) == .expand)
    // A few points below the notch still count, so the gesture is forgiving.
    #expect(action(CGPoint(x: notch.notchRect.midX, y: notch.notchRect.minY - 3), expanded: false) == .expand)
}

@Test func thePointerAwayFromTheNotchLeavesItCollapsed() {
    #expect(action(CGPoint(x: 200, y: 500), expanded: false) == .none)
    #expect(action(CGPoint(x: notch.notchRect.midX, y: notch.notchRect.minY - 8), expanded: false) == .none)
}

@Test func movingOutOfTheOpenPanelSchedulesACollapse() {
    #expect(action(CGPoint(x: notch.expandedRect.midX, y: notch.expandedRect.midY), expanded: true) == .cancelCollapse)
    #expect(action(CGPoint(x: 100, y: 100), expanded: true) == .scheduleCollapse)
}

@Test func aPinnedPanelSurvivesThePointerLeaving() {
    // A pending Touch ID request or a half-typed password must not be dismissed by a
    // stray pointer movement...
    #expect(action(CGPoint(x: 100, y: 100), expanded: true, pinned: true) == .cancelCollapse)
    // ...but a deliberate click outside still closes the panel.
    #expect(action(CGPoint(x: 100, y: 100), expanded: true, buttonDown: true, pinned: true) == .collapseNow)
}

@Test func aClickOutsideTheOpenPanelCollapsesItImmediately() {
    #expect(action(CGPoint(x: 100, y: 100), expanded: true, buttonDown: true) == .collapseNow)
    #expect(action(CGPoint(x: notch.expandedRect.midX, y: notch.expandedRect.midY), expanded: true, buttonDown: true) == .none)
}

@Test func theOpenPanelCoversTheNotchArea() {
    // Otherwise the pointer would look like it left the panel while hovering the notch.
    #expect(notch.expandedRect.contains(CGPoint(x: notch.notchRect.midX, y: notch.notchRect.midY)))
}

@MainActor
@Test func thePanelWatchesPointerEventsInAndOutOfTheApp() {
    _ = NSApplication.shared
    let controller = NotchWindowController()
    controller.start()
    defer { controller.stop() }

    // One global monitor (other apps), one local for our own panel, and one local for
    // Escape while the panel holds the keyboard. A nil monitor would mean hover,
    // outside-click or Escape silently never fire.
    #expect(controller.installedMonitorCount == 3)
    #expect(controller.isAvailable)
    #expect(controller.notchHeight > 0)
}
