import Foundation

/// A credential the user is about to write to the OATH applet, built either from a
/// pasted `otpauth://` link or from the typed form.
///
/// Unlike `OATHAccount`, which only mirrors what the key already holds, this value
/// carries the raw secret: it is needed exactly once, to create the entry, and is
/// dropped as soon as the key has answered.
public struct NewCredential: Sendable, Equatable {

    public enum Kind: Sendable, Equatable {
        case totp(period: TimeInterval, digits: UInt8)
        case hotp(counter: UInt32, digits: UInt8)
    }

    /// Hash the key uses, as named by the `algorithm` query parameter.
    public enum Algorithm: UInt8, Sendable, Equatable {
        case sha1 = 0x01
        case sha256 = 0x02
        case sha512 = 0x03
    }

    public var issuer: String?
    public var name: String
    /// Raw secret bytes, already base32-decoded.
    public var secret: Data
    public var kind: Kind
    public var algorithm: Algorithm
    public var requiresTouch: Bool

    public init(
        issuer: String?,
        name: String,
        secret: Data,
        kind: Kind,
        algorithm: Algorithm,
        requiresTouch: Bool
    ) {
        self.issuer = issuer
        self.name = name
        self.secret = secret
        self.kind = kind
        self.algorithm = algorithm
        self.requiresTouch = requiresTouch
    }

    /// Why a pasted link or a typed form could not become a credential.
    public enum ParsingError: Error, Equatable, Sendable {
        case unsupportedScheme
        case missingName
        case missingSecret
        case invalidSecret
        /// Something else than TOTP or HOTP, e.g. `otpauth://steam/…`.
        case unsupportedType
        /// `otpauth://hotp/…` without a `counter`.
        case missingCounter
        /// Unparsable digits, period, counter or algorithm.
        case invalidValue

        /// Message shown in the notch panel.
        public var userMessage: String {
            switch self {
            case .unsupportedScheme: return String(localized: "Lien otpauth:// attendu.")
            case .missingName: return String(localized: "Nom du compte manquant.")
            case .missingSecret: return String(localized: "Clé secrète manquante.")
            case .invalidSecret: return String(localized: "Clé secrète invalide (base32, 10 octets minimum).")
            case .unsupportedType: return String(localized: "Type non supporté (TOTP ou HOTP).")
            case .missingCounter: return String(localized: "Compteur HOTP manquant.")
            case .invalidValue: return String(localized: "Valeur invalide dans le lien.")
            }
        }
    }

    /// Builds a credential from a Google Authenticator key URI:
    /// `otpauth://totp/Issuer:account?secret=…&issuer=…&algorithm=SHA1&digits=6&period=30`.
    ///
    /// The URI is split by hand instead of through `URLComponents`, because a secret has
    /// to come out byte for byte: query values are decoded with `+` read as a space (a
    /// literal plus is never valid base32, so form-style encoding is the only sensible
    /// reading), while an escaped `%2B` stays a literal plus.
    ///
    /// `requiresTouch` is always `false` here — the key URI format has no field for it.
    /// The form is where the user sets it, and the key reports its own flag back once
    /// the entry exists.
    public static func parse(otpauthURI: String) -> Result<NewCredential, ParsingError> {
        let text = otpauthURI.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let colon = text.firstIndex(of: ":"),
              text[text.startIndex..<colon].lowercased() == "otpauth"
        else { return .failure(.unsupportedScheme) }

        var remainder = text[text.index(after: colon)...]
        guard remainder.hasPrefix("//") else { return .failure(.unsupportedScheme) }
        remainder = remainder.dropFirst(2)

        // A fragment is not part of the key URI format; dropping it before the query is
        // read keeps a '#' from swallowing the parameters that follow.
        let head = remainder.prefix { $0 != "#" }
        let queryMark = head.firstIndex(of: "?")
        let hierPart = queryMark.map { head[head.startIndex..<$0] } ?? head
        let query = queryMark.map { head[head.index(after: $0)...] } ?? ""

        let slash = hierPart.firstIndex(of: "/")
        let host = (slash.map { hierPart[hierPart.startIndex..<$0] } ?? hierPart).lowercased()
        let rawLabel = slash.map { hierPart[hierPart.index(after: $0)...] } ?? ""

        let isTOTP: Bool
        switch host {
        case "totp": isTOTP = true
        case "hotp": isTOTP = false
        default: return .failure(.unsupportedType)
        }

        var parameters: [String: String] = [:]
        for field in query.split(separator: "&") {
            let equals = field.firstIndex(of: "=")
            let rawName = equals.map { field[field.startIndex..<$0] } ?? field
            let rawValue = equals.map { field[field.index(after: $0)...] } ?? ""
            parameters[percentDecoded(rawName, plusIsSpace: false).lowercased()] =
                percentDecoded(rawValue, plusIsSpace: true)
        }

        guard let secretText = parameters["secret"] else { return .failure(.missingSecret) }
        guard let secret = Base32.decode(secretText), !secret.isEmpty else {
            return .failure(.invalidSecret)
        }

        let algorithm: Algorithm
        switch parameters["algorithm"]?.uppercased() ?? "SHA1" {
        case "SHA1": algorithm = .sha1
        case "SHA256": algorithm = .sha256
        case "SHA512": algorithm = .sha512
        default: return .failure(.invalidValue)
        }

        let digits: UInt8
        if let digitsText = parameters["digits"] {
            guard let parsed = UInt8(trimmed(digitsText)), (6...8).contains(parsed) else {
                return .failure(.invalidValue)
            }
            digits = parsed
        } else {
            digits = 6
        }

        let kind: Kind
        if isTOTP {
            var period: TimeInterval = 30
            if let periodText = parameters["period"] {
                // `infinite` and `nan` both parse, so a bare `> 0` test is not enough.
                guard let seconds = TimeInterval(trimmed(periodText)), seconds.isFinite, seconds > 0
                else { return .failure(.invalidValue) }
                period = seconds
            }
            kind = .totp(period: period, digits: digits)
        } else {
            guard let counterText = parameters["counter"] else { return .failure(.missingCounter) }
            guard let counter = UInt32(trimmed(counterText)) else { return .failure(.invalidValue) }
            kind = .hotp(counter: counter, digits: digits)
        }

        // The label is `Issuer:account` or `account`. The split happens on a raw colon —
        // an escaped `%3A` is data inside a name, not a separator — and an issuer found
        // in the label wins over the `issuer` parameter.
        let label = percentDecoded(rawLabel, plusIsSpace: false)
        var labelIssuer: String?
        var account = label
        if let separator = label.firstIndex(of: ":") {
            labelIssuer = normalized(String(label[label.startIndex..<separator]))
            account = String(label[label.index(after: separator)...])
        }

        let name = trimmed(account)
        guard !name.isEmpty else { return .failure(.missingName) }

        return .success(
            NewCredential(
                issuer: labelIssuer ?? normalized(parameters["issuer"]),
                name: name,
                secret: secret,
                kind: kind,
                algorithm: algorithm,
                requiresTouch: false
            )
        )
    }

    /// Builds a credential from the typed form. `secretText` is base32 as the user typed
    /// it, separators and all.
    ///
    /// An algorithm is not part of the form: entries are created with the applet's
    /// default, HMAC-SHA1.
    public static func fromForm(
        issuer: String?,
        name: String,
        secretText: String,
        kind: Kind,
        requiresTouch: Bool
    ) -> Result<NewCredential, ParsingError> {
        let name = trimmed(name)
        guard !name.isEmpty else { return .failure(.missingName) }

        guard !trimmed(secretText).isEmpty else { return .failure(.missingSecret) }
        // The applet rejects a secret this short; checking here turns a form mistake into
        // a message instead of a failed round trip to the key.
        guard let secret = Base32.decode(secretText), secret.count >= minimumSecretLength else {
            return .failure(.invalidSecret)
        }

        return .success(
            NewCredential(
                issuer: normalized(issuer),
                name: name,
                secret: secret,
                kind: kind,
                algorithm: .sha1,
                requiresTouch: requiresTouch
            )
        )
    }

    /// Shortest secret the OATH applet accepts.
    private static let minimumSecretLength = 10

    /// Trims a value and treats a blank result as absent.
    private static func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let value = trimmed(text)
        return value.isEmpty ? nil : value
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Percent-decodes one URI component. A malformed escape is kept verbatim rather
    /// than failing the whole URI, and `+` is only read as a space where the component is
    /// a query value; in a path segment it stays a literal plus.
    private static func percentDecoded(_ text: Substring, plusIsSpace: Bool) -> String {
        let bytes = Array(text.utf8)
        var decoded: [UInt8] = []
        decoded.reserveCapacity(bytes.count)

        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x25, index + 2 < bytes.count,
               let high = hexDigit(bytes[index + 1]), let low = hexDigit(bytes[index + 2]) {
                decoded.append(high << 4 | low)
                index += 3
            } else {
                decoded.append(byte == 0x2B && plusIsSpace ? 0x20 : byte)
                index += 1
            }
        }

        return String(decoding: decoded, as: UTF8.self)
    }

    private static func hexDigit(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39: return byte - 0x30
        case 0x41...0x46: return byte - 0x41 + 10
        case 0x61...0x66: return byte - 0x61 + 10
        default: return nil
        }
    }
}
