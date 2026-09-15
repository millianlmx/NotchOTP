import AppKit
import SwiftUI

/// Feedback that makes the panel feel alive: trackpad haptics and the success burst.
enum PanelFeedback {

    /// Fired when a confirmation hands a code over. The same firm tick Apple Pay gives
    /// when the payment goes through, because it marks the same moment.
    static func confirmed() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}

/// Green pulse played once when a code is handed over.
struct SuccessBurst: View {

    @State private var animate = false

    var diameter: CGFloat = 130

    private let tint = Color(nsColor: .systemGreen)

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [tint.opacity(0.5), tint.opacity(0)],
                        center: .center,
                        startRadius: 2,
                        endRadius: animate ? diameter : diameter * 0.2
                    )
                )
                .scaleEffect(animate ? 1 : 0.4)

            Image(systemName: "checkmark")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(tint)
                .scaleEffect(animate ? 1 : 0.35)
                .opacity(animate ? 1 : 0)
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) { animate = true }
        }
    }
}
