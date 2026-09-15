import CryptoTokenKit
import Foundation

/// Facts about the running bundle, and the one hardware diagnostic the UI needs.
public enum AppInfo {

    /// Marketing version (`CFBundleShortVersionString`), e.g. `1.0`.
    public static var version: String {
        bundleString(forKey: "CFBundleShortVersionString") ?? "—"
    }

    /// Build number (`CFBundleVersion`), e.g. `1`.
    public static var build: String {
        bundleString(forKey: "CFBundleVersion") ?? "—"
    }

    /// Version and build together, the way the About pane shows them: `1.0 (1)`.
    public static var versionDescription: String {
        "\(version) (\(build))"
    }

    /// `CFBundleIdentifier`, or `—` when the code runs outside a bundle (tests, `swift run`).
    public static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "—"
    }

    /// Name shown to the user: `CFBundleDisplayName`, falling back to `CFBundleName`.
    public static var name: String {
        bundleString(forKey: "CFBundleDisplayName")
            ?? bundleString(forKey: "CFBundleName")
            ?? "YubicoNotch"
    }

    /// `NSHumanReadableCopyright`, or `nil` when the bundle does not carry one.
    public static var copyright: String? {
        bundleString(forKey: "NSHumanReadableCopyright")
    }

    /// Whether this process can see the Mac's smart-card slots at all.
    ///
    /// Read before anything touches YubiKit: an unsigned binary gets `nil` here even
    /// with a key plugged in — the card reader exists, the process is just not allowed
    /// to see it (YubiKit asserts on the same call, which is fatal in a debug build).
    /// `false` therefore means "no key, or the app is missing the
    /// `com.apple.security.smartcard` entitlement", and the UI has to say both.
    public static var smartCardAccess: Bool {
        TKSmartCardSlotManager.default != nil
    }

    private static func bundleString(forKey key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty
        else {
            return nil
        }
        return value
    }
}
