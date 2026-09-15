import CryptoTokenKit
import Foundation
import YubiKit

// MARK: - Seam

/// Everything the app needs from a YubiKey's OATH applet.
///
/// The only implementation shipped in the app talks to real hardware through
/// YubiKit; tests inject their own through ``YubiKeyConnecting``.
public protocol OATHSessionProtocol: Sendable {
    func keyVersion() async -> String
    /// Lists the credentials stored on the key.
    ///
    /// Deliberately the *only* thing the app can do without a confirmation: it reads
    /// names, never codes. A code is computed for one credential at a time, when the
    /// user has performed the gesture that asks for it.
    func accounts() async throws -> [OATHAccount]
    /// Computes one code, waiting for the physical touch when the credential requires it.
    func code(for accountID: Data, now: Date) async throws -> OATHCode
    func unlock(password: String) async throws
    /// Stores a new credential on the key. The applet must be unlocked.
    func addCredential(_ credential: NewCredential) async throws -> OATHAccount
    /// Removes a credential from the key. The applet must be unlocked.
    func deleteCredential(_ account: OATHAccount) async throws
    /// Renames a credential on the key, which changes its ID. The applet must be unlocked.
    func renameCredential(_ account: OATHAccount, name: String, issuer: String?) async throws
}

/// An open connection to a YubiKey, exposing its OATH session.
public protocol YubiKeyConnection: Sendable {
    var session: any OATHSessionProtocol { get }
    func waitUntilClosed() async -> Error?
    func close() async
}

/// Opens YubiKey connections.
public protocol YubiKeyConnecting: Sendable {
    /// Waits until a YubiKey is attached, then opens an OATH session on it.
    func connect() async throws -> any YubiKeyConnection
    /// Whether a YubiKey is attached right now, without opening a session.
    func hasConnectedDevice() async -> Bool
}

// MARK: - YubiKit implementation

public struct USBYubiKeyConnector: YubiKeyConnecting {

    public init() {}

    public func connect() async throws -> any YubiKeyConnection {
        // Checked before touching YubiKit: its USB connection asserts on a missing slot
        // manager (fatal in debug builds) and reports it as `unsupported`, which reads
        // as "bad key model" instead of "nothing to talk to".
        guard TKSmartCardSlotManager.default != nil else { throw OATHFailure.readerUnavailable }
        do {
            let connection = try await USBSmartCardConnection()
            let session = try await OATHSession.makeSession(connection: connection)
            return USBYubiKeyConnection(connection: connection, session: OATHSessionAdapter(session: session))
        } catch {
            throw OATHFailure.map(error)
        }
    }

    public func hasConnectedDevice() async -> Bool {
        guard TKSmartCardSlotManager.default != nil else { return false }
        do {
            return try await !USBSmartCardConnection.availableDevices().isEmpty
        } catch {
            return false
        }
    }
}

private struct USBYubiKeyConnection: YubiKeyConnection {
    let connection: USBSmartCardConnection
    let session: any OATHSessionProtocol

    func waitUntilClosed() async -> Error? {
        await connection.waitUntilClosed()
    }

    func close() async {
        await connection.close(error: nil)
    }
}

/// Thin projection of YubiKit's `OATHSession` onto the app's own model.
private actor OATHSessionAdapter: OATHSessionProtocol {

    private let session: OATHSession
    /// Credentials seen in the last snapshot, keyed by ID, needed to compute a single code later.
    private var credentials: [Data: OATHSession.Credential] = [:]

    init(session: OATHSession) {
        self.session = session
    }

    func keyVersion() async -> String {
        await session.version.description
    }

    func accounts() async throws -> [OATHAccount] {
        do {
            let listed = try await session.listCredentials()
            // The listing is the source of truth: anything the key no longer holds
            // (deleted or renamed elsewhere) must not stay resolvable for a code.
            credentials = Dictionary(listed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            return listed.map(OATHAccount.init)
        } catch {
            throw OATHFailure.map(error)
        }
    }

    func code(for accountID: Data, now: Date) async throws -> OATHCode {
        guard let credential = credentials[accountID] else { throw OATHFailure.credentialMissing }
        do {
            return OATHCode(try await session.calculateCredentialCode(for: credential, timestamp: now))
        } catch {
            throw OATHFailure.map(error)
        }
    }

    func unlock(password: String) async throws {
        do {
            try await session.unlock(password: password)
        } catch {
            throw OATHFailure.map(error)
        }
    }

    func addCredential(_ credential: NewCredential) async throws -> OATHAccount {
        do {
            let added = try await session.addCredential(template: credential.template)
            credentials[added.id] = added
            return OATHAccount(added)
        } catch {
            throw OATHFailure.map(error)
        }
    }

    func deleteCredential(_ account: OATHAccount) async throws {
        guard let credential = credentials[account.id] else { throw OATHFailure.credentialMissing }
        do {
            try await session.deleteCredential(credential)
            credentials[account.id] = nil
        } catch {
            throw OATHFailure.map(error)
        }
    }

    func renameCredential(_ account: OATHAccount, name: String, issuer: String?) async throws {
        guard let credential = credentials[account.id] else { throw OATHFailure.credentialMissing }
        guard await session.supports(.rename) else {
            throw OATHFailure.device(String(localized: "Cette YubiKey ne sait pas renommer un compte."))
        }
        do {
            try await session.renameCredential(credential, newName: name, newIssuer: issuer)
            // The ID derives from issuer and name: the cached credential is stale, and the
            // next snapshot is what re-keys it.
            credentials[account.id] = nil
        } catch {
            throw OATHFailure.map(error)
        }
    }
}

extension NewCredential {
    /// YubiKit model for writing a credential. The SDK zero-pads secrets shorter than
    /// 14 bytes and hashes the ones longer than the algorithm's block size.
    var template: OATHSession.CredentialTemplate {
        let type: OATHSession.CredentialType
        let digits: UInt8
        switch kind {
        case .totp(let period, let count):
            type = .totp(period: period)
            digits = count
        case .hotp(let counter, let count):
            type = .hotp(counter: counter)
            digits = count
        }

        return OATHSession.CredentialTemplate(
            type: type,
            algorithm: OATHSession.HashAlgorithm(rawValue: algorithm.rawValue) ?? .sha1,
            secret: secret,
            issuer: issuer,
            name: name,
            digits: digits,
            requiresTouch: requiresTouch
        )
    }
}

// MARK: - Translation

extension OATHAccount {
    init(_ credential: OATHSession.Credential) {
        let kind: Kind
        switch credential.type {
        case .totp(let period): kind = .totp(period: period)
        case .hotp(let counter): kind = .hotp(counter: counter)
        }
        self.init(
            id: credential.id,
            issuer: credential.issuer,
            name: credential.name,
            kind: kind,
            requiresTouch: credential.requiresTouch
        )
    }
}

extension OATHCode {
    init(_ code: OATHSession.Code) {
        self.init(code: code.code, validFrom: code.validFrom, validTo: code.validTo)
    }
}

extension OATHFailure {

    /// Maps SDK errors onto the handful of situations the UI reacts to.
    static func map(_ error: Error) -> OATHFailure {
        if let failure = error as? OATHFailure { return failure }

        if let oath = error as? OATHSessionError {
            switch oath {
            case .invalidPassword:
                return .wrongPassword
            case .credentialNotPresentOnCurrentYubiKey:
                return .credentialMissing
            case .connectionError(let connection, _):
                return map(connection)
            case .failedResponse(let response, _):
                switch response.status {
                case .securityConditionNotSatisfied:
                    return .passwordRequired
                case .incorrectParameters, .authMethodBlocked:
                    return .wrongPassword
                case .conditionsNotSatisfied:
                    return .touchRequired
                case .fileNotFound, .referencedDataNotFound, .invalidInstruction:
                    return .device(String(localized: "Cette YubiKey n'expose pas l'applet OATH."))
                default:
                    return .device(String(localized: "YubiKey : réponse \(response.status.description)."))
                }
            case .featureNotSupported:
                return .device(String(localized: "Cette YubiKey ne gère pas cette fonction OATH."))
            default:
                return .device(oath.localizedDescription)
            }
        }

        if let connection = error as? SmartCardConnectionError {
            return map(connection)
        }

        return .device(error.localizedDescription)
    }

    private static func map(_ error: SmartCardConnectionError) -> OATHFailure {
        switch error {
        case .busy:
            return .keyBusy
        case .connectionLost:
            return .keyUnavailable(String(localized: "YubiKey débranchée."))
        case .noDevicesFound:
            return .keyUnavailable(String(localized: "Aucune YubiKey détectée."))
        case .cancelled, .cancelledByUser:
            return .keyUnavailable(String(localized: "Connexion annulée."))
        case .unsupported:
            return .readerUnavailable
        case .setupFailed(let message, _), .transmitFailed(let message, _),
            .malformedData(let message), .pollingFailed(let message):
            return .device(message ?? String(localized: "Échec de communication avec la YubiKey."))
        @unknown default:
            return .device(String(localized: "Échec de communication avec la YubiKey."))
        }
    }
}
