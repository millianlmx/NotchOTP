// A plain gradient window covering the notched display, below the NotchOTP panel and
// above everything else: the marketing take crops the screen around the notch, and
// without this the user's own windows would be the background of the video.
//
//   swift Scripts/Marketing/Backdrop.swift
//
// Prints "ready" once the window is on screen; runs until killed. It takes mouse events
// (so a stray click during the take lands here, not in a window behind it) and never
// appears in the Dock or ⌘Tab.

import AppKit

final class Delegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens[0]
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = .normal
        window.isOpaque = true
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let gradient = CAGradientLayer()
        gradient.colors = [
            NSColor(srgbRed: 0.16, green: 0.18, blue: 0.30, alpha: 1).cgColor,
            NSColor(srgbRed: 0.33, green: 0.24, blue: 0.46, alpha: 1).cgColor,
            NSColor(srgbRed: 0.55, green: 0.30, blue: 0.42, alpha: 1).cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)

        let view = NSView(frame: screen.frame)
        view.wantsLayer = true
        view.layer = gradient
        window.contentView = view

        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        self.window = window

        print("ready")
        fflush(stdout)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = Delegate()
app.delegate = delegate
app.run()
