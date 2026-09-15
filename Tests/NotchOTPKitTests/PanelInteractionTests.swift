import AppKit
import Foundation
import LocalAuthentication
import SwiftUI
import Testing

@testable import NotchOTPKit

/// Panel interactions driven with real events through our own window.
///
/// Serialized on purpose: `NSEvent` monitors are app-wide, so a second test sending
/// events at the same time would drive this panel too.
@MainActor
@Suite(.serialized)
struct PanelInteractionTests {

    /// Opening the panel is what makes the app ask the key for its contents — and nothing
    /// is read from the key before that.
    @Test func openingThePanelListsTheAccounts() async throws {
        _ = NSApplication.shared
        NSApp.activate()
        let github = account(issuer: "GitHub", name: "me")
        let harness = await Harness.make(accounts: [github])
        defer { harness.stop() }

        let window = makeWindow(harness)
        defer { window.stop() }
        #expect(harness.service.accounts.isEmpty)

        window.expand()
        settleExpanded()

        #expect(await harness.waitUntil { harness.service.status.isReady })
        #expect(harness.service.accounts.map(\.label) == ["GitHub · me"])
    }

    /// A click on a row asks for the gesture: it must not put anything on the pasteboard,
    /// and the panel must not be yanked away while the sheet waits for it.
    @Test func clickingARowOpensTheSheetAndCopiesNothing() async throws {
        _ = NSApplication.shared
        NSApp.activate()
        let github = account(issuer: "GitHub", name: "me")
        let harness = await Harness.make(
            accounts: [github],
            codes: [github.id: code("123456", from: Date())],
            configure: { $0.confirmationMethod = .hold }
        )
        defer { harness.stop() }

        let window = makeWindow(harness)
        defer { window.stop() }
        window.expand()
        let panel = try #require(settleExpanded())
        try #require(await harness.waitUntil { harness.service.status.isReady })
        settle()

        clickUntil(panel) { harness.service.pending != nil }

        #expect(harness.service.pending?.id == github.id)
        #expect(harness.pasteboard.string == nil)
        #expect(harness.service.revealed.isEmpty)

        settle(0.3)
        #expect(window.keepsPanelOpen, "a sheet waiting for a gesture must not be dismissed by a stray move")
    }

    /// The whole point of the sheet: the hold gesture is what hands the code over.
    @Test func holdingTheTargetHandsTheCodeOver() async throws {
        _ = NSApplication.shared
        NSApp.activate()
        let github = account(issuer: "GitHub", name: "me")
        let harness = await Harness.make(
            accounts: [github],
            codes: [github.id: code("123456", from: Date())],
            configure: { $0.confirmationMethod = .hold }
        )
        defer { harness.stop() }

        let window = makeWindow(harness)
        defer { window.stop() }
        window.expand()
        let panel = try #require(settleExpanded())
        try #require(await harness.waitUntil { harness.service.status.isReady })
        settle()

        clickUntil(panel) { harness.service.pending != nil }
        try #require(harness.service.pending != nil)

        await holdUntil(panel) { harness.pasteboard.string != nil }

        #expect(harness.pasteboard.string == "123456")
        #expect(harness.service.revealed[github.id]?.code == "123456")
        #expect(await harness.waitUntil { harness.service.pending == nil })
    }

    /// What the lock button must do: the connection closes, the watcher reconnects at once,
    /// and the accounts must *not* come back on their own while the panel stays open.
    @Test func lockingFromTheHeaderStaysLocked() async throws {
        _ = NSApplication.shared
        NSApp.activate()
        let github = account(issuer: "GitHub", name: "me")
        let harness = await Harness.make(
            accounts: [github],
            codes: [github.id: code("123456", from: Date())],
            configure: { $0.confirmationMethod = .hold }
        )
        defer { harness.stop() }

        let window = makeWindow(harness)
        defer { window.stop() }
        window.expand()
        let panel = try #require(settleExpanded())
        try #require(await harness.waitUntil { harness.service.status.isReady })
        settle()

        // The header's right-hand side, lock button first: icons run gear, lock, plus, search.
        for x in stride(from: 390.0, through: 270.0, by: -26) {
            click(panel, at: CGPoint(x: x, y: 286))
            settle(0.25)
            if harness.service.lockedByUser { break }
        }
        #expect(harness.service.lockedByUser, "the header's lock button was never reached")

        #expect(await harness.waitFor { await harness.connector.connectCount >= 2 })
        try? await Task.sleep(for: .milliseconds(300))
        #expect(harness.service.accounts.isEmpty, "the panel relisted itself after being locked")
        #expect(!harness.service.status.isReady)
    }

    @Test func thePointerLeavingTheOpenPanelCollapsesIt() async throws {
        _ = NSApplication.shared
        NSApp.activate()
        let harness = await Harness.make()
        defer { harness.stop() }
        let window = makeWindow(harness)
        defer { window.stop() }
        window.expand()
        settleExpanded()
        #expect(window.isExpanded)

        moveMouse(try #require(settleExpanded()), to: CGPoint(x: -400, y: -400))
        #expect(await harness.waitFor(timeout: .seconds(2)) { !window.isExpanded })
    }

    @Test func aPinnedPanelIgnoresThePointerLeavingButNotAClick() async throws {
        _ = NSApplication.shared
        NSApp.activate()
        let harness = await Harness.make()
        defer { harness.stop() }
        let window = makeWindow(harness)
        defer { window.stop() }
        window.expand()
        settleExpanded()

        window.keepsPanelOpen = true  // a gesture in progress, or a half-typed password
        let panel = try #require(settleExpanded())
        moveMouse(panel, to: CGPoint(x: -400, y: -400))
        try? await Task.sleep(for: .seconds(1.2))
        #expect(window.isExpanded, "a prompt in progress must not be dismissed by a stray move")

        click(panel, at: CGPoint(x: -400, y: -400))
        // The event monitor handles the click asynchronously.
        #expect(await harness.waitFor { !window.isExpanded })
    }

    // Keyboard shortcuts and the Escape monitor need the panel to hold the keyboard,
    // which a `swift test` process cannot reliably claim; their decision rules are
    // covered by PanelLogicTests instead.

    // MARK: - Helpers

    private func makeWindow(_ harness: Harness) -> NotchWindowController {
        let window = NotchWindowController()
        window.onVisibilityChange = { harness.service.setPanelVisible($0) }
        window.attach(NotchRootView(service: harness.service, settings: harness.settings, window: window) {})
        window.start()
        return window
    }

    private func visiblePanel() -> NSWindow? {
        NSApp.windows.first { $0 is NSPanel && $0.isVisible }
    }

    private func send(_ type: NSEvent.EventType, to window: NSWindow, at point: CGPoint, number: Int) {
        guard
            let event = NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: number,
                clickCount: 1,
                pressure: 1
            )
        else { return }
        // Our own event, our own window: no accessibility permission involved.
        NSApp.sendEvent(event)
    }

    private func click(_ window: NSWindow, at point: CGPoint) {
        send(.leftMouseDown, to: window, at: point, number: 1)
        send(.leftMouseUp, to: window, at: point, number: 2)
    }

    /// Rows are SwiftUI-drawn, so their coordinates are a guess: click down the list until
    /// the panel reacts. A click that lands nowhere costs one frame.
    private func clickUntil(_ panel: NSWindow, _ reached: () -> Bool) {
        for y in stride(from: 250.0, through: 150.0, by: -24) {
            click(panel, at: CGPoint(x: 200, y: y))
            settle(0.25)
            if reached() { return }
        }
    }

    /// Same for the confirmation target: press, hold past the ring's fill, release.
    ///
    /// The wait between press and release has to be an `await`: the ring's countdown is a
    /// task of its own, and a test that blocks the run loop never lets it resume.
    private func holdUntil(_ panel: NSWindow, _ reached: () -> Bool) async {
        for y in stride(from: 240.0, through: 90.0, by: -20) {
            let point = CGPoint(x: 210, y: y)
            send(.leftMouseDown, to: panel, at: point, number: 1)
            settle(0.1)
            for _ in 0..<40 where !reached() {
                try? await Task.sleep(for: .milliseconds(50))
            }
            send(.leftMouseUp, to: panel, at: point, number: 2)
            settle(0.1)
            if reached() { return }
        }
    }

    /// Pumps the run loop: a test process has no running event loop, so AppKit's window
    /// grow animation would otherwise never finish and the panel would stay notch-sized.
    private func settle(_ seconds: TimeInterval = 0.7) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// Waits until the panel really is the expanded size before clicking inside it.
    @discardableResult
    private func settleExpanded() -> NSWindow? {
        let deadline = Date().addingTimeInterval(2)
        var panel = visiblePanel()
        while (panel?.frame.width ?? 0) < 300, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            panel = visiblePanel()
        }
        settle(0.2)
        return panel
    }

    private func moveMouse(_ window: NSWindow, to point: CGPoint) {
        send(.mouseMoved, to: window, at: point, number: 0)
    }
}

/// Counts the requests while delegating to the real gate, so the assertions do not depend
/// on whether a finger happens to be on the sensor.
@MainActor
final class CountingRealGate: BiometricAuthenticating {
    private let real = BiometricGate()
    private(set) var calls = 0

    var context: LAContext? { real.context }

    func prepareForConfirmation() {
        real.prepareForConfirmation()
    }

    func authenticate(reason: String) async -> BiometricOutcome {
        calls += 1
        return await real.authenticate(reason: reason)
    }
}
