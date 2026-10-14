import SwiftUI

/// Visual constants for the panel.
///
/// The panel sits on the physical notch, so it is a black surface with vibrancy-free
/// content: semantic styles (`.primary`, `.secondary`) plus a hairline and a hover
/// highlight, the way AppKit sidebars and popovers are built.
enum PanelStyle {

    static let surface = Color.black
    static let hairline = Color.white.opacity(0.07)
    static let rowHighlight = Color.white.opacity(0.08)
    static let controlFill = Color.white.opacity(0.1)
    static let controlFillHover = Color.white.opacity(0.16)

    /// Matches the notch's own curve when collapsed, opens up when expanded.
    static let topCornerRadius: CGFloat = 10
    static let bottomCornerRadius: CGFloat = 22

    static let horizontalPadding: CGFloat = 16
    static let headerHeight: CGFloat = 44
    static let rowHeight: CGFloat = 48

    /// The one clock of the panel: the surface grows out of the notch on it, the content
    /// rides it, the sheet and the rows use it. Slow enough to be seen leaving the notch,
    /// damped enough that the overshoot reads as weight rather than bounce.
    static let spring = Animation.spring(response: 0.46, dampingFraction: 0.78)
    /// Reduce Motion: a cross-fade, no travel.
    static let reducedMotion = Animation.smooth(duration: 0.22)
    static let quick = Animation.smooth(duration: 0.18)

    /// The user asked for less movement in System Settings → Accessibility.
    static var reducesMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// How the content comes and goes inside the growing surface: it arrives a beat after
    /// the surface has started moving, sharpening as it settles, and leaves quickly so the
    /// surface closes on an empty panel instead of cropping a laid-out one.
    static var contentTransition: AnyTransition {
        if reducesMotion {
            return .opacity
        }
        let veiled = PanelContentVeil(veiled: true)
        let clear = PanelContentVeil(veiled: false)
        return .asymmetric(
            insertion: .modifier(active: veiled, identity: clear).animation(spring.delay(0.05)),
            removal: .modifier(active: veiled, identity: clear).animation(.smooth(duration: 0.16))
        )
    }
}

/// Content behind frosted glass: faded, blurred and slightly smaller, pinned to the top
/// where the notch is, so it reads as emerging from it.
struct PanelContentVeil: ViewModifier {
    var veiled: Bool

    func body(content: Content) -> some View {
        content
            .opacity(veiled ? 0 : 1)
            .blur(radius: veiled ? 12 : 0)
            .scaleEffect(veiled ? 0.94 : 1, anchor: .top)
    }
}

/// Label on the left, rounded field on the right: the alignment macOS forms use.
struct PanelLabeledField<Field: Hashable>: View {

    let label: String
    let prompt: String
    @Binding var text: String
    var focus: FocusState<Field?>.Binding
    let field: Field

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            TextField(prompt, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .focused(focus, equals: field)
        }
    }
}

/// Round icon button with the hover feedback macOS toolbars use.
struct PanelIconButton: View {

    let symbol: String
    let help: String
    var tint: Color = .secondary
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(hovering ? Color.primary : tint)
                .frame(width: 26, height: 26)
                .background(hovering ? PanelStyle.rowHighlight : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
        .animation(PanelStyle.quick, value: hovering)
    }
}
