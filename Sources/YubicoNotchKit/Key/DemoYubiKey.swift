#if DEBUG
import CryptoKit
import Foundation
import LocalAuthentication

/// Development harness: a fake YubiKey with rotating TOTP codes and a fake Touch ID
/// prompt, so the whole panel can be exercised (and screenshotted) without hardware.
///
/// Enabled with the `-demo` launch argument; never reachable in a release build.

public struct DemoBiometricGate: BiometricAuthenticating {
    public init() {}

    public var context: LAContext? { nil }

    public func prepareForConfirmation() {}

    public func authenticate(reason: String) async -> BiometricOutcome {
        try? await Task.sleep(for: .milliseconds(900))
        return .success
    }
}

public struct DemoYubiKeyConnector: YubiKeyConnecting {

    public init() {}

    public func connect() async throws -> any YubiKeyConnection {
        DemoConnection(session: DemoOATHSession())
    }

    public func hasConnectedDevice() async -> Bool { true }
}

private struct DemoConnection: YubiKeyConnection {
    let session: any OATHSessionProtocol

    func waitUntilClosed() async -> Error? {
        try? await Task.sleep(for: .seconds(3600))
        return nil
    }

    func close() async {}
}

actor DemoOATHSession: OATHSessionProtocol {

    private struct Credential {
        let account: OATHAccount
        let secret: [UInt8]
        let digits: Int
    }

    private static let period: TimeInterval = 30

    private var credentials: [Data: Credential]
    private var hotpCounter: UInt32 = 0

    init() {
        let definitions: [(issuer: String, name: String, kind: OATHAccount.Kind, touch: Bool, digits: Int, secret: String)] = [
            ("GitHub", "millian@exemple.com", .totp(period: 30), false, 6, "JBSWY3DPEHPK3PXP"),
            ("Google", "millian@exemple.com", .totp(period: 30), true, 6, "KRSXG5CTMVRXEZLU"),
            ("AWS", "root", .hotp(counter: 0), false, 6, "MFRGGZDFMZTWQ2LK"),
            ("Proton", "millian", .totp(period: 60), false, 8, "GEZDGNBVGY3TQOJQ"),
        ]

        var credentials: [Data: Credential] = [:]
        for definition in definitions {
            let id = Data("\(definition.issuer):\(definition.name)".utf8)
            credentials[id] = Credential(
                account: OATHAccount(
                    id: id,
                    issuer: definition.issuer,
                    name: definition.name,
                    kind: definition.kind,
                    requiresTouch: definition.touch
                ),
                secret: [UInt8](Base32.decode(definition.secret) ?? Data()),
                digits: definition.digits
            )
        }
        self.credentials = credentials
    }

    func keyVersion() async -> String { "5.7.4 (demo)" }

    func unlock(password: String) async throws {}

    func accounts() async throws -> [OATHAccount] {
        credentials.values.map(\.account).sorted { $0.label < $1.label }
    }

    func code(for accountID: Data, now: Date) async throws -> OATHCode {
        guard let credential = credentials[accountID] else { throw OATHFailure.credentialMissing }
        return try makeCode(credential, now: now)
    }

    func addCredential(_ credential: NewCredential) async throws -> OATHAccount {
        let id = Data("\(credential.issuer ?? ""):\(credential.name)".utf8)
        let kind: OATHAccount.Kind
        let digits: Int
        switch credential.kind {
        case .totp(let period, let count):
            kind = .totp(period: period)
            digits = Int(count)
        case .hotp(let counter, let count):
            kind = .hotp(counter: counter)
            digits = Int(count)
        }

        let account = OATHAccount(
            id: id,
            issuer: credential.issuer,
            name: credential.name,
            kind: kind,
            requiresTouch: credential.requiresTouch
        )
        credentials[id] = Credential(account: account, secret: [UInt8](credential.secret), digits: digits)
        return account
    }

    func deleteCredential(_ account: OATHAccount) async throws {
        guard credentials.removeValue(forKey: account.id) != nil else {
            throw OATHFailure.credentialMissing
        }
    }

    func renameCredential(_ account: OATHAccount, name: String, issuer: String?) async throws {
        guard let credential = credentials.removeValue(forKey: account.id) else {
            throw OATHFailure.credentialMissing
        }
        let id = Data("\(issuer ?? ""):\(name)".utf8)
        credentials[id] = Credential(
            account: OATHAccount(
                id: id,
                issuer: issuer,
                name: name,
                kind: credential.account.kind,
                requiresTouch: credential.account.requiresTouch
            ),
            secret: credential.secret,
            digits: credential.digits
        )
    }

    private func makeCode(_ credential: Credential, now: Date) throws -> OATHCode {
        switch credential.account.kind {
        case .totp(let period):
            let value = Self.totp(secret: credential.secret, period: period, digits: credential.digits, now: now)
            let start = now.timeIntervalSince1970 - now.timeIntervalSince1970.truncatingRemainder(dividingBy: period)
            let validFrom = Date(timeIntervalSince1970: start)
            return OATHCode(code: value, validFrom: validFrom, validTo: validFrom.addingTimeInterval(period))
        case .hotp:
            hotpCounter += 1
            let value = Self.hotp(secret: credential.secret, counter: UInt64(hotpCounter), digits: credential.digits)
            return OATHCode(code: value, validFrom: now, validTo: now.addingTimeInterval(Self.period))
        }
    }

    private static func totp(secret: [UInt8], period: TimeInterval, digits: Int, now: Date) -> String {
        hotp(secret: secret, counter: UInt64(now.timeIntervalSince1970 / period), digits: digits)
    }

    private static func hotp(secret: [UInt8], counter: UInt64, digits: Int) -> String {
        var message = counter.bigEndian
        let mac = Array(
            HMAC<Insecure.SHA1>.authenticationCode(
                for: Data(bytes: &message, count: MemoryLayout<UInt64>.size),
                using: SymmetricKey(data: Data(secret))
            )
        )
        let offset = Int(mac[mac.count - 1] & 0x0f)
        let truncated =
            (UInt32(mac[offset]) & 0x7f) << 24
            | UInt32(mac[offset + 1]) << 16
            | UInt32(mac[offset + 2]) << 8
            | UInt32(mac[offset + 3])
        let modulus = (0..<digits).reduce(UInt32(1)) { value, _ in value * 10 }
        return String(format: "%0\(digits)d", truncated % modulus)
    }
}
#endif
