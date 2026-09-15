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

    static let spring = Animation.spring(response: 0.34, dampingFraction: 0.82)
    static let quick = Animation.smooth(duration: 0.18)

    /// The user asked for less movement in System Settings → Accessibility.
    static var reducesMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
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
