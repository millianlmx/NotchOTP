import SwiftUI

/// Touch ID mark with the three states the unlock flow goes through.
///
/// macOS owns the actual biometric sheet; this is the in-app surface: it pulses while the
/// sensor waits for a finger, then confirms with a green check.
struct TouchIDGlyph: View {

    enum Phase: Equatable {
        case idle
        case authenticating
        case granted
    }

    let phase: Phase
    var size: CGFloat = 62

    @State private var breath = false

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.10))
                .frame(width: size * 1.75, height: size * 1.75)
                .scaleEffect(breath ? 1.04 : 0.96)
                .blur(radius: 6)

            Circle()
                .strokeBorder(tint.opacity(0.22), lineWidth: 0.5)
                .frame(width: size * 1.5, height: size * 1.5)

            Group {
                if phase == .granted {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.5, weight: .medium))
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                } else {
                    Image(systemName: "touchid")
                        .font(.system(size: size * 0.78, weight: .light))
                        .transition(.opacity)
                }
            }
            .foregroundStyle(tint)
            .symbolRenderingMode(.hierarchical)
        }
        .animation(.smooth(duration: 0.32), value: phase)
        .onAppear { updateBreath() }
        .onChange(of: phase) { _, _ in updateBreath() }
    }

    private var tint: Color {
        switch phase {
        case .idle: return .primary
        case .authenticating: return .accentColor
        case .granted: return Color(nsColor: .systemGreen)
        }
    }

    private func updateBreath() {
        breath = false
        let duration: Double = phase == .idle ? 2.2 : 0.75
        withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
            breath = true
        }
    }
}
