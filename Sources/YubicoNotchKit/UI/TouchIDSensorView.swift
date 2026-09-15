import LocalAuthentication
import LocalAuthenticationEmbeddedUI
import SwiftUI

/// Hosts the embedded biometric control while staying transparent to mouse events.
///
/// `LAAuthenticationView` only *displays* the biometric state — the evaluation is started
/// by the panel and a finger never goes through it — but as a plain `NSView` it would
/// swallow clicks, which would make the sheet behind it untappable. Clicking the sheet is
/// how the user asks for another attempt.
final class ClickThroughContainer: NSView {
    /// Apple's own view tells us how much room it wants, instead of us guessing a size
    /// per `NSControlSize`.
    var measuredSize = CGSize(width: 128, height: 128)

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Apple's own biometric control, embedded in the panel.
///
/// This is what removes the system alert: once an `LAAuthenticationView` is bound to a
/// context, macOS presents the prompt inside this view — the sensor hint, the waiting
/// state, the retry state — and never in a `coreautha` window of its own.
struct TouchIDSensorView: NSViewRepresentable {

    let context: LAContext
    var controlSize: NSControl.ControlSize = .regular
    /// Called once the view is actually in a window. Starting the evaluation before that
    /// would make macOS fall back to its own alert.
    var onReady: () -> Void = {}

    @MainActor
    final class Coordinator {
        var started = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context swiftUI: Context) -> ClickThroughContainer {
        let container = ClickThroughContainer(frame: .zero)
        let view = LAAuthenticationView(context: context, controlSize: controlSize)
        let fitting = view.fittingSize
        if fitting.width > 0, fitting.height > 0 {
            container.measuredSize = fitting
        }
        Log.auth.notice(
            "embedded LAAuthenticationView size \(container.measuredSize.debugDescription, privacy: .public)"
        )
        view.frame = CGRect(origin: .zero, size: container.measuredSize)
        view.autoresizingMask = [.width, .height]
        container.frame = CGRect(origin: .zero, size: container.measuredSize)
        container.addSubview(view)
        let coordinator = swiftUI.coordinator
        let ready = onReady
        Task { @MainActor in
            // Give SwiftUI a beat to attach the view to its window.
            for _ in 0..<40 {
                if coordinator.started { return }
                if view.window != nil {
                    coordinator.started = true
                    Log.auth.notice("embedded view is in window, key=\(view.window?.isKeyWindow ?? false)")
                    ready()
                    return
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
            if !coordinator.started {
                coordinator.started = true
                Log.auth.error("embedded view never reached a window; starting anyway")
                ready()
            }
        }
        return container
    }

    func updateNSView(_ nsView: ClickThroughContainer, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ClickThroughContainer, context: Context) -> CGSize? {
        nsView.measuredSize
    }
}
