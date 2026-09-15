import AppKit
import NotchOTPKit

@main
enum NotchOTPApp {

    /// Held for the lifetime of the process: `NSApplication.delegate` is a weak reference.
    @MainActor static let controller = AppController(
        demo: ProcessInfo.processInfo.arguments.contains("-demo")
    )

    @MainActor
    static func main() {
        let app = NSApplication.shared
        // Menu bar and notch only: no Dock icon, no main menu.
        app.setActivationPolicy(.accessory)
        app.delegate = controller
        app.run()
    }
}
