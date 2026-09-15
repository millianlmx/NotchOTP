import Foundation
import Observation
import ServiceManagement

/// The app's login item, through `SMAppService` (macOS 13+).
///
/// The system owns the registration, so the state is read back from
/// `SMAppService.mainApp.status` instead of being mirrored in `UserDefaults`: a mirror
/// would drift the moment the user removes the login item in System Settings.
@MainActor
@Observable
public final class LaunchAtLogin {

    /// Whether YubicoNotch is registered to open at login.
    ///
    /// `.requiresApproval` counts as registered: macOS holds the item until it is
    /// approved in System Settings, and switching the preference off has to unregister
    /// it wherever it is in that process.
    public private(set) var isEnabled: Bool

    /// Last failure, already phrased for the user, or `nil`.
    public private(set) var errorMessage: String?

    private let service: SMAppService

    public init(service: SMAppService = .mainApp) {
        self.service = service
        isEnabled = Self.isRegistered(service.status)
    }

    /// Re-reads the state from the system. Worth calling when the settings window comes
    /// back to the front: the user may have changed the item from System Settings.
    public func refresh() {
        isEnabled = Self.isRegistered(service.status)
    }

    /// Registers or unregisters the login item, keeping the last error for the UI.
    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error, enabling: enabled)
        }
        refresh()
    }

    /// Whether macOS is holding the login item until the user approves it in System
    /// Settings; the settings window offers to open that pane.
    public var needsApproval: Bool {
        service.status == .requiresApproval
    }

    /// One line saying what macOS currently thinks of the login item.
    public var statusDescription: String {
        switch service.status {
        case .enabled:
            return "YubicoNotch s'ouvre à l'ouverture de session."
        case .notRegistered:
            return "YubicoNotch ne s'ouvre que lorsque tu la lances."
        case .requiresApproval:
            return "Enregistrée : macOS attend ton autorisation dans Réglages Système → Général → Ouverture."
        case .notFound:
            return "Élément de connexion introuvable : lance l'app depuis son bundle."
        @unknown default:
            return "État de l'élément de connexion inconnu."
        }
    }

    /// Opens Réglages Système → Général → Ouverture, where macOS asks for the approval.
    public static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func isRegistered(_ status: SMAppService.Status) -> Bool {
        switch status {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound:
            return false
        @unknown default:
            return false
        }
    }

    private static func message(for error: Error, enabling: Bool) -> String {
        let failure = error as NSError
        let action = enabling ? "activer" : "désactiver"
        // SMAppService reports failures in `SMAppServiceErrorDomain` with a readable
        // reason ("Unable to read plist: …") and no public code list, so the system's
        // own sentence is what the user gets. The legacy `kSMError*` codes belong to the
        // job-based API and never show up here.
        let reason = failure.localizedFailureReason ?? failure.localizedDescription
        return "Impossible d'\(action) l'ouverture à la connexion : \(reason)"
    }
}
