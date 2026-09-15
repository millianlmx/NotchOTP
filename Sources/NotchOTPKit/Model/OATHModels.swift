import Foundation

/// A TOTP/HOTP credential stored in the OATH applet of a YubiKey.
///
/// The secret never leaves the key: only this metadata and the generated codes
/// travel to the app.
public struct OATHAccount: Identifiable, Sendable, Hashable {

    public enum Kind: Sendable, Hashable {
        case totp(period: TimeInterval)
        case hotp(counter: UInt32)
    }

    /// Credential ID as stored on the key; unique per key.
    public let id: Data
    public let issuer: String?
    public let name: String
    public let kind: Kind
    /// The key asks for a physical touch before revealing this code.
    public let requiresTouch: Bool

    public init(id: Data, issuer: String?, name: String, kind: Kind, requiresTouch: Bool) {
        self.id = id
        self.issuer = issuer
        self.name = name
        self.kind = kind
        self.requiresTouch = requiresTouch
    }

    public var isTOTP: Bool {
        if case .totp = kind { return true }
        return false
    }

    public var period: TimeInterval? {
        if case .totp(let period) = kind { return period }
        return nil
    }

    /// Primary line of the row: the issuer when known, the account name otherwise.
    public var title: String {
        guard let issuer, !issuer.isEmpty else { return name }
        return issuer
    }

    /// Secondary line of the row: the account name, omitted when it is already the title.
    public var subtitle: String? {
        guard let issuer, !issuer.isEmpty, issuer != name else { return nil }
        return name
    }

    public var label: String {
        guard let issuer, !issuer.isEmpty else { return name }
        return "\(issuer) · \(name)"
    }
}

/// A one-time code computed by the YubiKey, with its validity window.
public struct OATHCode: Sendable, Hashable {

    public let code: String
    public let validFrom: Date
    public let validTo: Date

    public init(code: String, validFrom: Date, validTo: Date) {
        self.code = code
        self.validFrom = validFrom
        self.validTo = validTo
    }

    /// Code split in two halves, as shown on the key's own display and by Yubico Authenticator.
    public var grouped: String {
        let count = code.count
        guard count >= 6, count.isMultiple(of: 2) else { return code }
        let half = count / 2
        return "\(code.prefix(half)) \(code.suffix(half))"
    }
}

/// Failure surfaced to the UI, already translated into something actionable.
public enum OATHFailure: Error, Equatable, Sendable {
    /// No smart card slot manager: nothing to talk to (no YubiKey attached, or the
    /// process is not allowed to reach the smart card service).
    case readerUnavailable
    case keyUnavailable(String)
    case keyBusy
    /// The OATH applet is password protected and still locked.
    case passwordRequired
    case wrongPassword
    /// The key never saw the required touch before the operation failed.
    case touchRequired
    case credentialMissing
    case device(String)

    /// Message shown in the notch panel.
    public var userMessage: String {
        switch self {
        case .readerUnavailable:
            return String(localized: "Aucune YubiKey détectée.")
        case .keyUnavailable(let detail):
            return detail.isEmpty ? String(localized: "YubiKey indisponible.") : detail
        case .keyBusy:
            return String(localized: "YubiKey occupée par une autre application.")
        case .passwordRequired:
            return String(localized: "Mot de passe OATH requis.")
        case .wrongPassword:
            return String(localized: "Mot de passe OATH incorrect.")
        case .touchRequired:
            return String(localized: "Touche ta YubiKey.")
        case .credentialMissing:
            return String(localized: "Ce compte n'existe plus sur la YubiKey.")
        case .device(let detail):
            return detail.isEmpty ? String(localized: "Erreur de communication avec la YubiKey.") : detail
        }
    }
}
