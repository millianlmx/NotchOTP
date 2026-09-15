import AppKit
import SwiftUI

/// Form for writing a new credential to the key, typed or pasted as an `otpauth://` link.
struct AddAccountForm: View {

    @Binding var draft: CredentialDraft
    let service: YubiKeyService
    let onCancel: () -> Void
    let onSubmitted: () -> Void
    /// Asks for a region of the screen to read a QR code from.
    let onScanScreen: () -> Void
    /// Opens the Screen Recording pane of System Settings.
    let onOpenScreenRecordingSettings: () -> Void

    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case issuer
        case name
        case secret
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelLabeledField(label: String(localized: "Émetteur"), prompt: "GitHub", text: $draft.issuer, focus: $focus, field: .issuer)
            PanelLabeledField(label: String(localized: "Compte"), prompt: String(localized: "prenom@exemple.com"), text: $draft.name, focus: $focus, field: .name)
            PanelLabeledField(label: String(localized: "Clé secrète"), prompt: "JBSWY3DPEHPK3PXP", text: $draft.secret, focus: $focus, field: .secret)

            HStack(spacing: 10) {
                Picker("Type", selection: $draft.isHOTP) {
                    Text("TOTP").tag(false)
                    Text("HOTP").tag(true)
                }
                .frame(width: 118)

                Picker("Chiffres", selection: $draft.digits) {
                    Text("6").tag(UInt8(6))
                    Text("8").tag(UInt8(8))
                }
                .frame(width: 106)

                if !draft.isHOTP {
                    Picker("Période", selection: $draft.period) {
                        Text("30 s").tag(TimeInterval(30))
                        Text("60 s").tag(TimeInterval(60))
                    }
                    .frame(width: 106)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.top, 1)

            Toggle("Exiger un contact physique", isOn: $draft.requiresTouch)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if let message = draft.message {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(message, systemImage: draft.isImported ? "checkmark.circle" : "exclamationmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(draft.isImported ? Color(nsColor: .systemGreen) : Color(nsColor: .systemRed))
                        .lineLimit(2)
                    if draft.showsPermissionHelp {
                        Button("Ouvrir Réglages", action: onOpenScreenRecordingSettings)
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
            }

            Spacer(minLength: 0)

            Divider().overlay(PanelStyle.hairline)

            HStack(spacing: 8) {
                Button {
                    draft.fillFromPasteboard()
                } label: {
                    Label("Coller un lien", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    onScanScreen()
                } label: {
                    Label("Scanner l'écran", systemImage: "qrcode.viewfinder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer(minLength: 4)

                Button("Annuler", action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)

                Button("Ajouter") { submit() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
                    .disabled(service.adding)
            }
        }
        .padding(.horizontal, PanelStyle.horizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { focus = .name }
    }

    private func submit() {
        switch draft.credential() {
        case .failure(let error):
            draft.report(error.userMessage)
        case .success(let credential):
            draft.report(nil)
            Task {
                if await service.addCredential(credential) {
                    onSubmitted()
                }
            }
        }
    }
}

/// Form state for a credential being added.
struct CredentialDraft: Equatable {
    var issuer = ""
    var name = ""
    var secret = ""
    var isHOTP = false
    var digits: UInt8 = 6
    var period: TimeInterval = 30
    var requiresTouch = false
    var message: String?
    /// The last message came from a successful import rather than a validation failure.
    var isImported = false
    /// The message is about the screen-recording permission: offer to open the pane.
    var showsPermissionHelp = false

    func credential() -> Result<NewCredential, EditingError> {
        let kind: NewCredential.Kind = isHOTP
            ? .hotp(counter: 0, digits: digits)
            : .totp(period: period, digits: digits)

        return NewCredential
            .fromForm(
                issuer: issuer.isEmpty ? nil : issuer,
                name: name,
                secretText: secret,
                kind: kind,
                requiresTouch: requiresTouch
            )
            .mapError(EditingError.init)
    }

    /// Fills the form from an `otpauth://` URI sitting in the pasteboard.
    mutating func fillFromPasteboard() {
        guard let text = NSPasteboard.general.string(forType: .string),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            report(String(localized: "Presse-papiers vide."))
            return
        }
        apply(otpauthURI: text)
    }

    /// Fills the form from an `otpauth://` URI, wherever it came from.
    mutating func apply(otpauthURI: String) {
        switch NewCredential.parse(otpauthURI: otpauthURI) {
        case .failure(let error):
            report(error.userMessage)
        case .success(let credential):
            issuer = credential.issuer ?? ""
            name = credential.name
            secret = Self.secretText(from: otpauthURI) ?? ""
            requiresTouch = credential.requiresTouch
            switch credential.kind {
            case .totp(let duration, let count):
                isHOTP = false
                period = duration
                digits = count
            case .hotp(_, let count):
                isHOTP = true
                digits = count
            }
            message = String(localized: "Lien importé.")
            isImported = true
        }
    }

    mutating func report(_ text: String?, permissionHelp: Bool = false) {
        message = text
        isImported = false
        showsPermissionHelp = permissionHelp
    }

    /// The raw `secret` parameter, as written in the link, so the field shows exactly
    /// what will be sent to the key.
    private static func secretText(from uri: String) -> String? {
        guard let range = uri.range(of: "secret=") else { return nil }
        let rest = uri[range.upperBound...]
        let end = rest.firstIndex { $0 == "&" || $0 == "#" } ?? rest.endIndex
        let raw = String(rest[rest.startIndex..<end])
        return raw.removingPercentEncoding ?? raw
    }
}

/// Form validation failure, ready to display.
struct EditingError: Error {
    let message: String

    init(parsing error: NewCredential.ParsingError) {
        self.message = error.userMessage
    }

    var userMessage: String { message }
}
