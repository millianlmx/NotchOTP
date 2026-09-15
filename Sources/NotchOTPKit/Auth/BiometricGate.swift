import Foundation
import LocalAuthentication

public enum BiometricOutcome: Equatable, Sendable {
    case success
    case cancelled
    case unavailable(String)
    case failed(String)
}

@MainActor
public protocol BiometricAuthenticating: Sendable {
    /// Context the panel's embedded biometric view is bound to, or `nil` when nothing is
    /// being confirmed. When a view is bound to it, macOS draws the biometric prompt inside
    /// that view instead of presenting its own authentication alert.
    var context: LAContext? { get }

    /// Arms the context the confirmation about to start will use.
    func prepareForConfirmation()

    func authenticate(reason: String) async -> BiometricOutcome
}

/// Confirmation gesture: Touch ID, or the double-click on the side button of a paired
/// Apple Watch — the same two ways Apple Pay lets you authorise something.
///
/// **One context per confirmation, never one for the whole run.** Reuse lives in the
/// context: measured on macOS 26, a context that has already matched answers the next
/// `evaluatePolicy` in ten milliseconds with no new touch, which is how one fingerprint
/// came to open every code after it. Handing out a context that has never authenticated
/// anything is therefore the only construction in which each code asks again — and the
/// previous one is invalidated so that nothing is left that could answer for it.
///
/// `touchIDAuthenticationAllowableReuseDuration` stays at zero as well: it covers the
/// reuse macOS allows after a *device unlock*, and leaving it at its default is one less
/// window to reason about.
///
/// The context is only created when a confirmation starts, because the panel's embedded
/// view has to be bound to *that* context — and the view must be in a window before the
/// evaluation, otherwise macOS falls back to its own alert.
@MainActor
public final class BiometricGate: BiometricAuthenticating {

    /// Biometry, or a companion device, whichever the user reaches for. Both policies are
    /// drawn by the embedded view; `…OrCompanion` only exists from macOS 15 on.
    ///
    /// With no watch anywhere near, the companion policy behaves exactly like the
    /// biometric one, so nothing changes for a Mac on its own.
    static var policy: LAPolicy {
        if #available(macOS 15.0, *) {
            return .deviceOwnerAuthenticationWithBiometricsOrCompanion
        }
        return .deviceOwnerAuthenticationWithBiometrics
    }

    private var current: LAContext?

    public var context: LAContext? { current }

    public init() {}

    public func prepareForConfirmation() {
        // Safe: a confirmation only starts once the previous sheet is gone, so the context
        // being retired has no view and no evaluation left on it.
        current?.invalidate()
        let fresh = LAContext()
        fresh.localizedCancelTitle = String(localized: "Annuler")
        current = fresh
        Log.auth.notice("fresh biometric context for the next code")
    }

    public func authenticate(reason: String) async -> BiometricOutcome {
        guard let localContext = current else {
            return .unavailable(String(localized: "Aucune confirmation en cours."))
        }

        var error: NSError?
        guard localContext.canEvaluatePolicy(Self.policy, error: &error) else {
            Log.auth.error("no confirmation method available: \(Self.describe(error))")
            return .unavailable(Self.describe(error))
        }

        Log.auth.notice("evaluatePolicy starting")
        let started = ContinuousClock.now
        do {
            let granted = try await localContext.evaluatePolicy(Self.policy, localizedReason: reason)
            // Worth its line: a finger left on the sensor makes the next evaluation answer
            // in milliseconds with no new touch, which is exactly the shape of the bug
            // "one fingerprint and every code after it came free".
            let elapsed = ContinuousClock.now - started
            Log.auth.notice(
                "evaluatePolicy \(granted ? "granted" : "refused", privacy: .public) in \(elapsed.description, privacy: .public)"
            )
            return granted ? .success : .failed(Self.refusedMessage)
        } catch let failure as LAError {
            let elapsed = ContinuousClock.now - started
            Log.auth.notice(
                "evaluatePolicy failed in \(elapsed.description, privacy: .public): \(failure.code.rawValue, privacy: .public)"
            )
            switch failure.code {
            case .userCancel, .systemCancel, .appCancel:
                return .cancelled
            case .biometryNotAvailable, .biometryNotEnrolled:
                return .unavailable(Self.describe(error))
            case .biometryLockout:
                return .failed(String(localized: "Touch ID est verrouillé après trop de tentatives."))
            case .invalidContext:
                return .unavailable(String(localized: "Session biométrique invalide, relance l'app."))
            case .companionNotAvailable:
                // Only reachable when the policy insisted on a companion; the
                // biometrics-or-companion one falls back on its own.
                return .unavailable(String(localized: "Aucun appareil à proximité pour confirmer."))
            default:
                return .failed(Self.describe(failure))
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static let refusedMessage = String(localized: "Confirmation refusée.")

    private static func describe(_ error: Error?) -> String {
        guard let error else { return String(localized: "Aucun moyen de confirmer sur ce Mac.") }
        switch (error as? LAError)?.code {
        case .biometryNotEnrolled:
            return String(localized: "Aucune empreinte enregistrée sur ce Mac.")
        case .biometryNotAvailable:
            return String(localized: "Touch ID indisponible — utilise l'appui maintenu dans les réglages.")
        default:
            return error.localizedDescription
        }
    }
}
