import AppKit
import SwiftUI

/// Wires the app together: notch panel, key service, status bar item and settings window.
@MainActor
public final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private let settings: Settings
    private let service: YubiKeyService
    private let launchAtLogin = LaunchAtLogin()
    private let settingsRoute = SettingsRoute()
    private let window = NotchWindowController()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var observers: [any NSObjectProtocol] = []

    public init(demo: Bool = false) {
        let settings = Settings()
        self.settings = settings
        // `-demo` swaps in a fake key and a fake sensor. It survives the release build on
        // purpose: it is how someone with no YubiKey — an App Store reviewer, for one — can
        // see the panel work.
        if demo {
            self.service = YubiKeyService(
                connector: DemoYubiKeyConnector(),
                gate: DemoBiometricGate(),
                settings: settings
            )
        } else {
            self.service = YubiKeyService(settings: settings)
        }
        super.init()
    }

    // MARK: - Lifecycle

    public func applicationDidFinishLaunching(_ notification: Notification) {
        window.onVisibilityChange = { [weak self] visible in
            self?.service.setPanelVisible(visible)
        }
        window.attach(
            NotchRootView(
                service: service,
                settings: settings,
                window: window,
                onOpenSettings: { [weak self] in self?.showSettings() }
            )
        )
        window.start()
        service.start()
        #if DEBUG
            // `-confirm` drives the whole path on real hardware: open the panel, wait for
            // the listing, then ask for the first account. The sheet does the rest — the
            // only thing left to provide is a finger.
            if ProcessInfo.processInfo.arguments.contains("-confirm") {
                Task {
                    // Nobody is hovering the notch in a scripted run, and an unpinned panel
                    // collapses as soon as the pointer is seen elsewhere.
                    window.keepsPanelOpen = true
                    window.expand()
                    for _ in 0..<60 where service.accounts.isEmpty {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    if let account = service.accounts.first {
                        service.requestCode(for: account)
                    }
                }
            }
        #endif
        installStatusItem()
        observeSystemLock()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        service.stop()
        window.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.forEach(DistributedNotificationCenter.default().removeObserver)
        observers.removeAll()
    }

    /// Locking the screen or putting the Mac to sleep must hide the codes.
    private func observeSystemLock() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.sessionDidResignActiveNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.willSleepNotification,
        ] {
            observers.append(
                workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.service.lock() }
                }
            )
        }
        observers.append(
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.apple.screenIsLocked"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.service.lock() }
            }
        )
    }

    // MARK: - Status bar

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "key.horizontal.fill", accessibilityDescription: "NotchOTP")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: statusDescription, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        switch service.status {
        case .ready:
            menu.addItem(item("Verrouiller", #selector(lockNow), "l"))
        case .locked:
            menu.addItem(item("Ouvrir le panneau", #selector(openPanel), ""))
        case .searching, .unavailable:
            break
        }

        menu.addItem(item("Ouvrir le panneau", #selector(openPanel), ""))
        menu.addItem(item("Ajouter un compte…", #selector(addAccount), ""))
        menu.addItem(item("Réglages…", #selector(showSettingsFromMenu), ","))
        menu.addItem(.separator())
        menu.addItem(item("À propos de NotchOTP", #selector(showAbout), ""))
        menu.addItem(.separator())
        menu.addItem(item("Quitter NotchOTP", #selector(quit), "q"))
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private var statusDescription: String {
        switch service.status {
        case .searching:
            return "YubiKey non connectée"
        case .locked(let info):
            return "YubiKey \(info.firmware) · verrouillée"
        case .ready(let info):
            let count = service.accounts.count
            return "YubiKey \(info.firmware) · \(count) compte\(count > 1 ? "s" : "")"
        case .unavailable(let message):
            return message
        }
    }

    @objc private func lockNow() {
        service.lock()
    }

    @objc private func openPanel() {
        window.expand()
    }

    /// The panel is where accounts are added; the form itself only exists there, so this
    /// just opens the notch and lets the panel take over.
    @objc private func addAccount() {
        window.expand()
    }

    @objc private func showSettingsFromMenu() {
        showSettings()
    }

    @objc private func showAbout() {
        showSettings(.about)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Settings window

    /// Shows the settings window, optionally on a given pane. Without an argument the
    /// window keeps whatever pane it was last on, which is what the menu item expects.
    private func showSettings(_ tab: SettingsTab? = nil) {
        if let tab {
            settingsRoute.tab = tab
        }
        if settingsWindow == nil {
            let root = SettingsView(
                settings: settings,
                launchAtLogin: launchAtLogin,
                route: settingsRoute
            )
            let window = NSWindow(contentViewController: NSHostingController(rootView: root))
            window.title = AppInfo.name
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
