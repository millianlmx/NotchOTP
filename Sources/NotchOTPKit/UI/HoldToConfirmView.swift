import SwiftUI

/// Press-and-hold confirmation: the ring fills while the pointer stays down, and the code
/// is handed over once it closes.
///
/// This is the target of the *appui maintenu* setting: for Macs without a Touch ID sensor,
/// and for anyone who would rather never see a biometric prompt. With Touch ID the
/// fingerprint is the confirmation and this ring is not shown.
struct HoldToConfirmView: View {

    /// How long the hold lasts. Long enough to be deliberate, short enough not to annoy.
    static let duration: TimeInterval = 0.85

    let isWorking: Bool
    let onComplete: () -> Void

    @State private var progress: Double = 0
    @State private var countdown: Task<Void, Never>?

    var body: some View {
        HoldRing(progress: progress, isWorking: isWorking)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in begin() }
                    .onEnded { _ in abort() }
            )
            .accessibilityElement()
            .accessibilityLabel("Maintenir pour confirmer")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onComplete() }
            .onDisappear { countdown?.cancel() }
    }

    private func begin() {
        guard countdown == nil, !isWorking else { return }
        withAnimation(.linear(duration: Self.duration)) { progress = 1 }
        countdown = Task {
            try? await Task.sleep(for: .seconds(Self.duration))
            guard !Task.isCancelled else { return }
            countdown = nil
            onComplete()
        }
    }

    /// Released too early: the ring empties and nothing happens.
    private func abort() {
        countdown?.cancel()
        countdown = nil
        guard !isWorking else { return }
        withAnimation(.easeOut(duration: 0.22)) { progress = 0 }
    }
}

/// The ring itself, without the gesture, so it can be rendered on its own.
struct HoldRing: View {

    let progress: Double
    var isWorking = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.quaternary, lineWidth: 3)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Image(systemName: isWorking ? "hourglass" : "hand.tap.fill")
                .font(.system(size: 22, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: 76, height: 76)
        .animation(.easeOut(duration: 0.2), value: isWorking)
    }
}
