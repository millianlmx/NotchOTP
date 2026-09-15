import AppKit
import SwiftUI

/// The credential list: macOS-style selection, hover highlight, and the per-row actions.
///
/// A row shows a code only once the user has confirmed it. Until then it shows the mask —
/// and still shows the countdown, because knowing how long a code computed *now* would
/// last is exactly what decides when to ask for one.
struct AccountListView: View {

    let accounts: [OATHAccount]
    let revealed: [Data: OATHCode]
    let now: Date
    let selection: Data?
    let isAnimatingAppearance: Bool

    let onConfirm: (OATHAccount) -> Void
    let onRename: (OATHAccount) -> Void
    let onDelete: (OATHAccount) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 1) {
                ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                    AccountRowView(
                        account: account,
                        code: revealed[account.id],
                        now: now,
                        isSelected: selection == account.id,
                        onConfirm: { onConfirm(account) }
                    )
                    .contextMenu {
                        Button(revealed[account.id] == nil ? "Afficher le code…" : "Copier le code") {
                            onConfirm(account)
                        }
                        Divider()
                        Button("Renommer…") { onRename(account) }
                        Button("Supprimer…", role: .destructive) { onDelete(account) }
                    }
                    // Rows rise in one after another when the panel opens. A transition
                    // rather than a reveal flag: a flag means the rows sit at zero opacity
                    // until something fires, and they were not clickable meanwhile.
                    .transition(
                        isAnimatingAppearance
                            ? .offset(y: 10).combined(with: .opacity).animation(PanelStyle.spring.delay(Double(index) * 0.035))
                            : .identity
                    )
                }
            }
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One credential: the code — masked until confirmed — and its countdown.
struct AccountRowView: View {

    let account: OATHAccount
    /// The code the user confirmed, if any. `nil` keeps it masked.
    let code: OATHCode?
    let now: Date
    var isSelected = false
    let onConfirm: () -> Void

    @State private var hovering = false

    private var highlighted: Bool { isSelected || hovering }

    /// A six-digit code's worth of dots. What is behind the mask is not its length, any
    /// more than the last four digits of a card number are the card.
    private static let mask = "••• •••"

    var body: some View {
        HStack(spacing: 12) {
            labels
            Spacer(minLength: 8)
            codeValue
            if let window {
                CountdownRing(
                    progress: CodeClock.progress(from: window.validFrom, to: window.validTo, now: now),
                    remaining: CodeClock.remaining(until: window.validTo, now: now),
                    period: account.period ?? 30
                )
                .frame(width: 26, height: 26)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: PanelStyle.rowHeight)
        .background(
            isSelected ? Color.accentColor.opacity(0.28) : (hovering ? PanelStyle.rowHighlight : .clear),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 6)
        .onHover { hovering = $0 }
        .animation(PanelStyle.quick, value: hovering)
        .onTapGesture { onConfirm() }
        .help(account.label)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(account.label)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(code == nil ? "Afficher le code" : "Copier le code")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onConfirm() }
    }

    /// The window the countdown talks about: the confirmed code's own, or the one a code
    /// computed right now would fall in.
    private var window: (validFrom: Date, validTo: Date)? {
        if let code { return (code.validFrom, code.validTo) }
        guard let period = account.period else { return nil }
        return CodeClock.window(period: period, now: now)
    }

    @ViewBuilder
    private var codeValue: some View {
        if let code {
            Text(code.grouped)
                .monospacedDigit()
                .foregroundStyle(.primary)
        } else {
            Text(Self.mask)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Code masqué")
        }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(account.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            HStack(spacing: 4) {
                if let subtitle = account.subtitle {
                    Text(subtitle).lineLimit(1)
                }
                if account.requiresTouch {
                    Label("contact", systemImage: "hand.tap")
                } else if !account.isTOTP {
                    Text("HOTP")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    /// VoiceOver reads the code and its remaining life the way a person would say it —
    /// or says that there is nothing to read yet.
    private var accessibilityValue: String {
        guard let code else {
            return account.requiresTouch
                ? String(localized: "Code masqué. Confirmation requise, la clé demandera un contact.")
                : String(localized: "Code masqué. Confirmation requise.")
        }
        guard let period = account.period else { return code.code }
        let remaining = Int(CodeClock.remaining(until: code.validTo, now: now).rounded(.up))
        return String(localized: "\(code.code), encore \(remaining) secondes sur \(Int(period))")
    }
}

/// Time left in the validity window, as a ring that empties.
struct CountdownRing: View {

    let progress: Double
    let remaining: TimeInterval
    let period: TimeInterval

    private var urgent: Bool { remaining <= 5 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0.02, 1 - progress))
                .stroke(
                    urgent ? Color(nsColor: .systemOrange) : Color.primary.opacity(0.8),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text("\(Int(remaining.rounded(.up)))")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(urgent ? Color(nsColor: .systemOrange) : .primary)
        }
        .animation(.linear(duration: 0.5), value: progress)
        .accessibilityHidden(true)
    }
}

/// Destructive action, confirmed inside the panel rather than in a system alert.
struct DeleteAccountConfirmation: View {

    let account: OATHAccount
    let isWorking: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "trash")
                .font(.system(size: 26, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(nsColor: .systemRed))

            VStack(spacing: 3) {
                Text("Supprimer « \(account.label) » ?")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                Text("Le compte sera effacé de la YubiKey. Cette action est définitive.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            HStack(spacing: 8) {
                Button("Annuler", action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)

                Button("Supprimer", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(Color(nsColor: .systemRed))
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Rename editor: the credential keeps its secret, only its label changes.
struct RenameAccountForm: View {

    let account: OATHAccount
    let isWorking: Bool
    let onCancel: () -> Void
    let onSubmit: (String, String?) -> Void

    @State private var issuer: String
    @State private var name: String
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case issuer
        case name
    }

    init(
        account: OATHAccount,
        isWorking: Bool,
        onCancel: @escaping () -> Void,
        onSubmit: @escaping (String, String?) -> Void
    ) {
        self.account = account
        self.isWorking = isWorking
        self.onCancel = onCancel
        self.onSubmit = onSubmit
        _issuer = State(initialValue: account.issuer ?? "")
        _name = State(initialValue: account.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Renommer le compte")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            PanelLabeledField(label: String(localized: "Émetteur"), prompt: "GitHub", text: $issuer, focus: $focus, field: .issuer)
            PanelLabeledField(label: String(localized: "Compte"), prompt: String(localized: "prenom@exemple.com"), text: $name, focus: $focus, field: .name)

            Spacer(minLength: 0)

            Divider().overlay(PanelStyle.hairline)

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Annuler", action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                Button("Renommer") {
                    onSubmit(name.trimmingCharacters(in: .whitespaces), issuer.isEmpty ? nil : issuer)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
                .disabled(isWorking || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, PanelStyle.horizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { focus = .name }
    }
}
