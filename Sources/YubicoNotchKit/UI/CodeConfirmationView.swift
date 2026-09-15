import LocalAuthentication
import SwiftUI

/// The sheet Apple Pay puts in front of a payment, put in front of a code.
///
/// It states what is about to happen — which credential, the code still masked — and asks
/// for the gesture that makes it happen. There is no "Confirmer" button: what is being
/// confirmed is that someone asked for *this* code, and the fingerprint is that ask.
///
/// The fingerprint is asked for one code at a time, with a context that has never
/// authenticated anything (see `BiometricGate`): a context kept for the whole run answers
/// the next code in milliseconds with no new touch, which is how one fingerprint came to
/// open every code after it.
struct CodeConfirmationView: View {

    let account: OATHAccount
    /// The code once it has been handed over; `nil` while it is still masked.
    let code: OATHCode?
    let phase: YubiKeyService.Phase
    let context: LAContext?
    let method: Settings.ConfirmationMethod

    /// Start the confirmation — or start it again after an attempt that did not go through.
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private static let mask = "••• •••"

    var body: some View {
        VStack(spacing: 10) {
            credential
            codeLine
            gesture.frame(height: 76)
            hint
            Button("Annuler", action: onCancel)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, PanelStyle.horizontalPadding)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// A cancelled attempt leaves the sheet up, and the way to ask again is to click the
    /// thing that asks — never a stray click on the ring, which has its own gesture.
    private var canRetry: Bool { method == .touchID && phase == .waiting }

    @ViewBuilder
    private var gesture: some View {
        if code != nil {
            SuccessBurst(diameter: 76)
        } else if phase == .reading {
            Image(systemName: account.requiresTouch ? "hand.tap.fill" : "key.horizontal.fill")
                .font(.system(size: 26, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .frame(width: 76, height: 76)
        } else if method == .touchID, let context {
            Group {
                if canRetry {
                    Button(action: onConfirm) { sensor(context) }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .accessibilityLabel("Réessayer la confirmation")
                } else {
                    sensor(context)
                }
            }
        } else if method == .touchID {
            // A gate with no embedded control — the demo's fake Touch ID — still asks; it
            // just has no sensor to draw. Only test and demo gates have no context; the
            // real one always has a live one.
            TouchIDGlyph(phase: phase == .reading ? .authenticating : .idle, size: 44)
                .onAppear { onConfirm() }
        } else {
            HoldToConfirmView(isWorking: false, onComplete: onConfirm)
        }
    }

    /// A finger never goes *through* the embedded view — the evaluation is started by the
    /// panel — but as a plain `NSView` it would swallow clicks, which would make the sheet
    /// untappable after a cancelled attempt.
    private func sensor(_ context: LAContext) -> some View {
        TouchIDSensorView(context: context, onReady: onConfirm)
            .allowsHitTesting(false)
    }

    private var credential: some View {
        VStack(spacing: 1) {
            Text(account.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if let subtitle = account.subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var codeLine: some View {
        Group {
            if let code {
                Text(code.grouped)
                    .monospacedDigit()
                    .foregroundStyle(Color(nsColor: .systemGreen))
            } else {
                Text(Self.mask)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Code masqué")
            }
        }
        .font(.system(size: 17, weight: .semibold))
        .tracking(0.5)
    }

    private var hint: some View {
        Text(hintText)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineSpacing(1)
            .padding(.horizontal, 22)
            .frame(height: 30, alignment: .top)
    }

    private var hintText: String {
        if code != nil { return "Code copié dans le presse-papiers." }
        switch phase {
        case .reading:
            return account.requiresTouch ? "Touche la clé." : "Lecture de la clé…"
        case .waiting, .copied:
            return method == .touchID
                ? "Pose le doigt, ou double-clique sur le bouton latéral de ton Apple Watch."
                : "Maintiens la cible appuyée pour confirmer."
        }
    }
}
