import Foundation
import LocalAuthentication
import YubicoNotchKit

// MARK: - Biometrics

@MainActor
final class RecordingGate: BiometricAuthenticating {
    var context: LAContext? { nil }

    private(set) var calls = 0
    private(set) var preparations = 0
    private let outcome: BiometricOutcome

    init(outcome: BiometricOutcome) {
        self.outcome = outcome
    }

    func prepareForConfirmation() {
        preparations += 1
    }

    func authenticate(reason: String) async -> BiometricOutcome {
        calls += 1
        return outcome
    }
}

struct FixedGate: BiometricAuthenticating {
    let outcome: BiometricOutcome

    var context: LAContext? { nil }

    func prepareForConfirmation() {}

    func authenticate(reason: String) async -> BiometricOutcome { outcome }
}

// MARK: - Pasteboard

@MainActor
final class FakePasteboard: Pasteboard {
    private(set) var value: String?
    private(set) var changeCount = 0

    var string: String? { value }

    func setString(_ newValue: String) {
        value = newValue
        changeCount += 1
    }

    func clear() {
        value = nil
        changeCount += 1
    }
}

// MARK: - Key

actor FakeSession: OATHSessionProtocol {

    private var accounts: [OATHAccount]
    private var codes: [Data: OATHCode]
    private var password: String?
    private var listFailure: OATHFailure?
    private var unlocked = false
    private var addFailure: OATHFailure?
    private var deleteFailure: OATHFailure?
    private var renameFailure: OATHFailure?

    private(set) var unlockCount = 0
    private(set) var listCount = 0
    /// How many codes the app asked the key to compute. The whole point of the
    /// confirmation model is that this stays at zero until a gesture asks for one.
    private(set) var codeRequests = 0
    private(set) var added: [NewCredential] = []

    init(
        accounts: [OATHAccount] = [],
        codes: [Data: OATHCode] = [:],
        password: String? = nil,
        listFailure: OATHFailure? = nil
    ) {
        self.accounts = accounts
        self.codes = codes
        self.password = password
        self.listFailure = listFailure
    }

    func keyVersion() async -> String { "5.7.4" }

    func accounts() async throws -> [OATHAccount] {
        listCount += 1
        if let listFailure { throw listFailure }
        if password != nil, !unlocked { throw OATHFailure.passwordRequired }
        return accounts
    }

    func code(for accountID: Data, now: Date) async throws -> OATHCode {
        codeRequests += 1
        guard let code = codes[accountID] else { throw OATHFailure.credentialMissing }
        return code
    }

    func unlock(password provided: String) async throws {
        unlockCount += 1
        guard let password else { return }
        guard password == provided else { throw OATHFailure.wrongPassword }
        unlocked = true
    }

    func addCredential(_ credential: NewCredential) async throws -> OATHAccount {
        if let addFailure { throw addFailure }
        let kind: OATHAccount.Kind
        switch credential.kind {
        case .totp(let period, _): kind = .totp(period: period)
        case .hotp(let counter, _): kind = .hotp(counter: counter)
        }
        let account = OATHAccount(
            id: Data("\(credential.issuer ?? ""):\(credential.name)".utf8),
            issuer: credential.issuer,
            name: credential.name,
            kind: kind,
            requiresTouch: credential.requiresTouch
        )
        added.append(credential)
        accounts.append(account)
        return account
    }

    func failNextAdd(with failure: OATHFailure) {
        addFailure = failure
    }

    func deleteCredential(_ account: OATHAccount) async throws {
        if let deleteFailure { throw deleteFailure }
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else {
            throw OATHFailure.credentialMissing
        }
        accounts.remove(at: index)
        codes[account.id] = nil
    }

    func renameCredential(_ account: OATHAccount, name: String, issuer: String?) async throws {
        if let renameFailure { throw renameFailure }
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else {
            throw OATHFailure.credentialMissing
        }
        let renamed = OATHAccount(
            id: Data("\(issuer ?? ""):\(name)".utf8),
            issuer: issuer,
            name: name,
            kind: account.kind,
            requiresTouch: account.requiresTouch
        )
        accounts[index] = renamed
        // The ID follows the label, so the code cached under the old one moves with it.
        if let cached = codes[account.id] {
            codes[account.id] = nil
            codes[renamed.id] = cached
        }
    }

    func failNextDelete(with failure: OATHFailure) {
        deleteFailure = failure
    }

    func failNextRename(with failure: OATHFailure) {
        renameFailure = failure
    }
}

actor ConnectionState {
    private var closed = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private(set) var closeCount = 0

    var isClosed: Bool { closed }

    func reopen() {
        closed = false
    }

    func waitUntilClosed() async {
        if closed { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func close() {
        closed = true
        closeCount += 1
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

struct FakeConnection: YubiKeyConnection {
    let session: any OATHSessionProtocol
    let state: ConnectionState

    func waitUntilClosed() async -> Error? {
        await state.waitUntilClosed()
        return nil
    }

    func close() async {
        await state.close()
    }
}

actor FakeConnector: YubiKeyConnecting {
    private let connection: FakeConnection
    private let state: ConnectionState
    private var devicePresent: Bool

    private(set) var connectCount = 0

    init(connection: FakeConnection, state: ConnectionState, devicePresent: Bool = true) {
        self.connection = connection
        self.state = state
        self.devicePresent = devicePresent
    }

    func setDevicePresent(_ present: Bool) {
        devicePresent = present
    }

    func connect() async throws -> any YubiKeyConnection {
        while !devicePresent {
            try? await Task.sleep(for: .milliseconds(5))
        }
        connectCount += 1
        await state.reopen()
        return connection
    }

    func hasConnectedDevice() async -> Bool { devicePresent }
}

actor FailingConnector: YubiKeyConnecting {
    private let failure: OATHFailure

    private(set) var connectAttempts = 0

    init(failure: OATHFailure) {
        self.failure = failure
    }

    func connect() async throws -> any YubiKeyConnection {
        connectAttempts += 1
        throw failure
    }

    func hasConnectedDevice() async -> Bool { false }
}

// MARK: - Harness

@MainActor
struct Harness {

    let service: YubiKeyService
    let settings: Settings
    let clipboard: Clipboard
    let pasteboard: FakePasteboard
    let connector: FakeConnector
    let state: ConnectionState
    let session: FakeSession
    let passwords: OATHPasswordStore

    static func make(
        accounts: [OATHAccount] = [],
        codes: [Data: OATHCode] = [:],
        password: String? = nil,
        listFailure: OATHFailure? = nil,
        gate: BiometricOutcome = .success,
        customGate: (any BiometricAuthenticating)? = nil,
        devicePresent: Bool = true,
        configure: (Settings) -> Void = { _ in }
    ) async -> Harness {
        let defaults = UserDefaults(suiteName: "app.yubiconotch.tests.\(UUID().uuidString)")!
        let settings = Settings(defaults: defaults)
        configure(settings)

        let session = FakeSession(
            accounts: accounts,
            codes: codes,
            password: password,
            listFailure: listFailure
        )
        let state = ConnectionState()
        let connection = FakeConnection(session: session, state: state)
        let connector = FakeConnector(connection: connection, state: state, devicePresent: devicePresent)
        let pasteboard = FakePasteboard()
        let clipboard = Clipboard(pasteboard: pasteboard)
        let passwords = OATHPasswordStore(
            service: "app.yubiconotch.tests",
            account: UUID().uuidString
        )

        let service = YubiKeyService(
            connector: connector,
            gate: customGate ?? FixedGate(outcome: gate),
            passwords: passwords,
            settings: settings,
            clipboard: clipboard
        )
        let harness = Harness(
            service: service,
            settings: settings,
            clipboard: clipboard,
            pasteboard: pasteboard,
            connector: connector,
            state: state,
            session: session,
            passwords: passwords
        )
        service.start()
        _ = await harness.waitUntil { harness.service.status != .searching }
        return harness
    }

    func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    func waitFor(timeout: Duration = .seconds(2), _ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await condition()
    }

    /// Opens the panel the way the window controller does, and waits for the listing: the
    /// starting point of every test that needs credentials on screen.
    @discardableResult
    func openPanel() async -> Bool {
        service.setPanelVisible(true)
        return await waitUntil { self.service.status.isReady }
    }

    /// One full confirmation — the gesture, then the key — and the wait for the sheet to
    /// close itself.
    @discardableResult
    func confirm(_ account: OATHAccount) async -> Bool {
        service.requestCode(for: account)
        await service.performConfirmation()
        return await waitUntil { self.service.pending == nil }
    }

    func stop() {
        service.stop()
    }
}

// MARK: - Fixtures

func account(
    issuer: String?,
    name: String,
    touch: Bool = false,
    period: TimeInterval = 30,
    kind: OATHAccount.Kind? = nil
) -> OATHAccount {
    OATHAccount(
        id: Data("\(issuer ?? ""):\(name)".utf8),
        issuer: issuer,
        name: name,
        kind: kind ?? .totp(period: period),
        requiresTouch: touch
    )
}

func code(_ value: String, from start: Date, period: TimeInterval = 30) -> OATHCode {
    OATHCode(code: value, validFrom: start, validTo: start.addingTimeInterval(period))
}
