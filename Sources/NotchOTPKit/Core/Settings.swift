import Foundation
import Observation

/// User-facing preferences, persisted in `UserDefaults`.
@MainActor
@Observable
public final class Settings {

    public enum ClipboardClear: TimeInterval, CaseIterable, Identifiable, Sendable {
        case never = 0
        case fifteen = 15
        case thirty = 30
        case fortyFive = 45
        case minute = 60
        case twoMinutes = 120

        public var id: TimeInterval { rawValue }
        public var seconds: TimeInterval { rawValue }

        public var label: String {
            switch self {
            case .never: return String(localized: "Jamais")
            case .fifteen: return String(localized: "15 secondes")
            case .thirty: return String(localized: "30 secondes")
            case .fortyFive: return String(localized: "45 secondes")
            case .minute: return String(localized: "1 minute")
            case .twoMinutes: return String(localized: "2 minutes")
            }
        }
    }

    /// How long a confirmed code stays on screen before the panel hides it again.
    /// A TOTP code also goes away with its own window; this is what covers the codes
    /// that have none, and the ones left visible on a panel nobody is looking at.
    public enum RevealTimeout: TimeInterval, CaseIterable, Identifiable, Sendable {
        case never = 0
        case oneMinute = 60
        case fiveMinutes = 300
        case fifteenMinutes = 900
        case thirtyMinutes = 1800

        public var id: TimeInterval { rawValue }
        public var seconds: TimeInterval { rawValue }

        public var label: String {
            switch self {
            case .never: return String(localized: "Jamais")
            case .oneMinute: return String(localized: "1 minute")
            case .fiveMinutes: return String(localized: "5 minutes")
            case .fifteenMinutes: return String(localized: "15 minutes")
            case .thirtyMinutes: return String(localized: "30 minutes")
            }
        }
    }

    /// What proves the user is there before a code leaves the key.
    public enum ConfirmationMethod: String, CaseIterable, Identifiable, Sendable {
        /// Fingerprint — or the double-click on an Apple Watch's side button — with
        /// Apple's own control embedded in the panel.
        case touchID
        /// Press and hold the target: for Macs without a Touch ID sensor.
        case hold

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .touchID: return String(localized: "Touch ID")
            case .hold: return String(localized: "Appui maintenu")
            }
        }

        public var detail: String {
            switch self {
            case .touchID:
                return String(localized: "Empreinte dans le panneau, ou double-clic sur le bouton latéral de ton Apple Watch — pour chaque code.")
            case .hold:
                return String(localized: "Maintenir la cible appuyée : pour les Macs sans capteur.")
            }
        }
    }

    private enum Key {
        static let clipboardClear = "clipboardClearSeconds"
        static let revealTimeout = "autoLockSeconds"
        static let rememberPassword = "rememberOATHPassword"
        /// Kept under its original name: the gesture it selects did not change, only
        /// what it now authorises.
        static let confirmationMethod = "unlockMethod"
    }

    public var clipboardClear: ClipboardClear {
        didSet { defaults.set(clipboardClear.seconds, forKey: Key.clipboardClear) }
    }

    public var revealTimeout: RevealTimeout {
        didSet { defaults.set(revealTimeout.seconds, forKey: Key.revealTimeout) }
    }

    public var confirmationMethod: ConfirmationMethod {
        didSet { defaults.set(confirmationMethod.rawValue, forKey: Key.confirmationMethod) }
    }

    /// Store the OATH password in the login keychain so the applet opens without typing.
    public var rememberOATHPassword: Bool {
        didSet { defaults.set(rememberOATHPassword, forKey: Key.rememberPassword) }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.clipboardClear =
            (defaults.object(forKey: Key.clipboardClear) as? Double)
            .flatMap(ClipboardClear.init(rawValue:)) ?? .fortyFive
        self.revealTimeout =
            (defaults.object(forKey: Key.revealTimeout) as? Double)
            .flatMap(RevealTimeout.init(rawValue:)) ?? .fiveMinutes
        self.rememberOATHPassword = defaults.bool(forKey: Key.rememberPassword)
        self.confirmationMethod =
            (defaults.string(forKey: Key.confirmationMethod))
            .flatMap(ConfirmationMethod.init(rawValue:)) ?? .touchID
    }
}
