import Foundation
import LocalAuthentication
import Observation

/// Orchestrates the key lifecycle: watching for a YubiKey, listing what is stored on it,
/// and handing over one code per confirmation gesture.
///
/// The model is Apple Pay's. The panel shows what is on the key the way Wallet shows the
/// passes, and nothing that matters leaves without a deliberate gesture — one gesture, one
/// code. The app never even computes a code it was not asked for: listing a key reads
/// credential names, nothing else.
@MainActor
@Observable
public final class YubiKeyService {

    public struct KeyInfo: Equatable, Sendable {
        public let firmware: String

        public init(firmware: String) {
            self.firmware = firmware
        }
    }

    public enum Status: Equatable, Sendable {
        /// No YubiKey attached.
        case searching
        /// Key attached, OATH session not open: nothing is listed yet.
        case locked(KeyInfo)
        /// Session open: the credentials are listed, no code is revealed.
        case ready(KeyInfo)
        /// Key attached but unusable (busy, no OATH applet, communication error).
        case unavailable(String)

        public var keyInfo: KeyInfo? {
            switch self {
            case .locked(let info), .ready(let info): return info
            case .searching, .unavailable: return nil
            }
        }

        public var isReady: Bool {
            if case .ready = self { return true }
            return false
        }
    }

    /// Where the confirmation sheet stands.
    public enum Phase: Equatable, Sendable {
        /// Waiting for the gesture.
        case waiting
        /// Gesture done, the key is computing — it may be waiting for a touch.
        case reading
        /// Code handed over: the sheet shows the tick before it closes.
        case copied
    }

    public private(set) var status: Status = .searching
    /// Credentials on the key. Identifiers and labels only: no code is derived from them.
    public private(set) var accounts: [OATHAccount] = []
    /// Codes the user confirmed with a gesture, still inside their validity window.
    public private(set) var revealed: [Data: OATHCode] = [:]
    /// The credential whose sheet is up, waiting for its gesture.
    public private(set) var pending: OATHAccount?
    public private(set) var phase: Phase = .waiting
    /// The user locked on purpose. The panel stays locked while it remains open — leaving
    /// the notch and coming back is what lists the accounts again.
    public private(set) var lockedByUser = false
    public private(set) var errorMessage: String?
    /// A confirmation gesture is on screen.
    public private(set) var authenticating = false
    /// The OATH applet asked for a password that we could not supply.
    public private(set) var passwordPrompt = false
    /// A credential is being written to the key.
    public private(set) var adding = false
    /// Transient success message (credential added).
    public private(set) var confirmation: String?
    /// Ticks while the app runs; drives the countdowns and the masking.
    public private(set) var now = Date()

    public let clipboard: Clipboard

    /// Context the panel's embedded biometric view binds to; `nil` for non-biometric setups.
    public var biometricContext: LAContext? { gate.context }

    private let connector: any YubiKeyConnecting
    private let gate: any BiometricAuthenticating
    private let passwords: OATHPasswordStore
    private let settings: Settings

    private var connection: (any YubiKeyConnection)?
    private var watcher: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var lastFirmware = ""
    private var opening = false
    private var panelVisible = false
    private var lastConfirmedAt: Date?
    private var confirmationTask: Task<Void, Never>?
    /// Bumped on every confirmation and every lock, so the outcome of an evaluation whose
    /// sheet is gone can be ignored instead of handing a code over to nobody.
    private var confirmationGeneration = 0

    public init(
        connector: any YubiKeyConnecting = USBYubiKeyConnector(),
        gate: any BiometricAuthenticating = BiometricGate(),
        passwords: OATHPasswordStore = OATHPasswordStore(),
        settings: Settings,
        clipboard: Clipboard = Clipboard()
    ) {
        self.connector = connector
        self.gate = gate
        self.passwords = passwords
        self.settings = settings
        self.clipboard = clipboard
    }

    // MARK: - Lifecycle

    public func start() {
        guard watcher == nil else { return }
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    let connection = try await self.connector.connect()
                    await self.didConnect(connection)
                    let closeError = await connection.waitUntilClosed()
                    await self.didDisconnect(closeError)
                } catch let failure as OATHFailure {
                    await self.didFail(failure)
                    try? await Task.sleep(for: .seconds(Self.retryDelay(for: failure)))
                } catch {
                    await self.didFail(.device(error.localizedDescription))
                    try? await Task.sleep(for: .seconds(3))
                }
            }
        }
        restartTicker()
    }

    public func stop() {
        watcher?.cancel()
        watcher = nil
        ticker?.cancel()
        ticker = nil
    }

    /// Runs the clock every countdown is drawn from, at the cadence the panel deserves: a
    /// second while it is on screen, five while it is not.
    ///
    /// Restarted rather than left running, because the sleep in progress is the whole
    /// problem: a tick that lands just before the notch opens leaves the rings frozen for
    /// the rest of its five-second nap, so the countdown only starts moving six seconds
    /// after the panel appears.
    private func restartTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick(now: Date())
                let interval: Duration = self.panelVisible ? .seconds(1) : .seconds(5)
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Tells the service whether the panel is on screen.
    ///
    /// The key is only asked for its contents while the panel is open: nothing is read in
    /// the background. Closing the panel also drops a confirmation in progress — the sheet
    /// went away, so there is no longer a gesture to honour.
    public func setPanelVisible(_ visible: Bool) {
        guard panelVisible != visible else { return }
        panelVisible = visible
        // On the way in *and* on the way out: the countdown has to start moving the moment
        // the panel is on screen, and drop back to its idle cadence when it is not.
        restartTicker()
        guard visible else {
            cancelConfirmation()
            return
        }
        // A fresh opening is a fresh intent: a lock taken while the panel was on screen
        // does not survive leaving the notch and coming back to it.
        lockedByUser = false
        Task { await self.open() }
    }

    private static func retryDelay(for failure: OATHFailure) -> Int {
        switch failure {
        case .keyBusy: return 5
        default: return 3
        }
    }

    private func didConnect(_ connection: any YubiKeyConnection) async {
        self.connection = connection
        lastFirmware = await connection.session.keyVersion()
        Log.key.notice("key connected: firmware \(self.lastFirmware, privacy: .public)")
        status = .locked(KeyInfo(firmware: lastFirmware))
        errorMessage = nil
        passwordPrompt = false
        // The watcher reconnects the moment a lock closes the connection: without this,
        // locking would list the accounts again a second later and look like it did
        // nothing at all.
        if panelVisible, !lockedByUser { await open() }
    }

    private func didDisconnect(_ error: Error?) async {
        connection = nil
        accounts = []
        revealed = [:]
        pending = nil
        phase = .waiting
        authenticating = false
        passwordPrompt = false
        lastConfirmedAt = nil
        if let error {
            errorMessage = OATHFailure.map(error).userMessage
        }

        // Locking closes the connection on purpose; the key is still plugged in and
        // the watcher reconnects immediately, so keep showing the locked state.
        status = await connector.hasConnectedDevice() ? .locked(KeyInfo(firmware: lastFirmware)) : .searching
    }

    private func didFail(_ failure: OATHFailure) async {
        Log.key.debug("key failure \(String(describing: failure))")
        connection = nil
        accounts = []
        revealed = [:]
        pending = nil

        // Nothing attached is the resting state, not an error: the watcher keeps polling
        // and the panel invites the user to plug the key in.
        guard failure != .readerUnavailable else {
            status = .searching
            errorMessage = nil
            return
        }

        errorMessage = failure.userMessage
        status = .unavailable(failure.userMessage)
    }

    // MARK: - Session

    /// Opens the OATH session so the panel can list what is on the key.
    ///
    /// Nothing secret happens here: opening the applet only buys the credential names.
    /// The codes stay on the key until a gesture asks for one.
    private func open() async {
        guard let connection, case .locked = status, !opening, !lockedByUser else { return }
        opening = true
        defer { opening = false }
        do {
            try await list(connection)
        } catch let failure as OATHFailure {
            errorMessage = failure.userMessage
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Lists the credentials, opening the applet with the stored password when it needs one.
    private func list(_ connection: any YubiKeyConnection) async throws {
        do {
            accounts = try await connection.session.accounts()
        } catch let failure as OATHFailure where failure == .passwordRequired || failure == .wrongPassword {
            guard settings.rememberOATHPassword, let password = try? passwords.password() else {
                Log.key.notice("OATH applet wants a password; none stored")
                passwordPrompt = true
                throw failure
            }
            do {
                Log.key.notice("trying the stored OATH password")
                try await connection.session.unlock(password: password)
            } catch let unlockFailure as OATHFailure {
                // The stored password no longer opens the applet: forget it instead of
                // failing on it forever, and ask the user.
                try? passwords.removePassword()
                passwordPrompt = true
                throw unlockFailure
            }
            accounts = try await connection.session.accounts()
        }

        accounts.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        lastFirmware = await connection.session.keyVersion()
        status = .ready(KeyInfo(firmware: lastFirmware))
        errorMessage = nil
        passwordPrompt = false
        Log.key.notice("accounts listed: \(self.accounts.count, privacy: .public)")
    }

    /// Opens the OATH applet with a password typed by the user.
    public func submitPassword(_ password: String, remember: Bool) async {
        guard let connection else { return }
        do {
            try await connection.session.unlock(password: password)
            try await list(connection)
            settings.rememberOATHPassword = remember
            if remember {
                try? passwords.setPassword(password)
            } else {
                try? passwords.removePassword()
            }
        } catch let failure as OATHFailure {
            errorMessage = failure.userMessage
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Drops everything: the revealed codes, the listing, and the OATH session itself,
    /// which relocks the applet on the key.
    ///
    /// Hiding happens even if the connection is momentarily gone: a lock that silently
    /// does nothing is worse than a lock that leaves the applet open for a moment.
    public func lock() {
        guard status.isReady else { return }
        let info = status.keyInfo ?? KeyInfo(firmware: lastFirmware)
        let connection = self.connection

        accounts = []
        revealed = [:]
        pending = nil
        phase = .waiting
        authenticating = false
        passwordPrompt = false
        lastConfirmedAt = nil
        lockedByUser = true
        lastFirmware = info.firmware
        status = .locked(info)
        confirmationGeneration += 1
        dismissConfirmation()
        clipboard.clearIfStillOurs()
        clipboard.cancelPendingClear()
        Log.auth.notice("locked by user")

        if let connection {
            Task { await connection.close() }
        }
    }

    // MARK: - Confirmation

    /// What a click on a credential does.
    ///
    /// A code already handed over goes back to the pasteboard: the gesture that authorised
    /// it still covers it, and nothing new is disclosed. Anything else opens the sheet,
    /// because the rule here is Apple Pay's — nothing leaves without a gesture.
    public func requestCode(for account: OATHAccount) {
        guard status.isReady, !adding else { return }
        if let code = revealed[account.id] {
            copy(code)
            return
        }
        guard pending == nil else { return }
        // Armed before the sheet exists, so the embedded view is bound to the context this
        // code will be confirmed with — and to none of the ones before it.
        if settings.confirmationMethod == .touchID {
            gate.prepareForConfirmation()
        }
        pending = account
        phase = .waiting
        errorMessage = nil
    }

    /// Confirms the code the sheet is showing: the gesture, then the key.
    ///
    /// Called by the sheet once the embedded biometric view really is in a window —
    /// evaluating before that makes macOS show its own authentication alert — or by the
    /// hold ring when the user picked that method.
    public func performConfirmation() async {
        guard let account = pending, let connection, phase == .waiting, !authenticating else { return }

        if settings.confirmationMethod == .touchID {
            guard await authenticate() else { return }
        }

        guard pending?.id == account.id else { return }
        phase = .reading
        do {
            let code = try await connection.session.code(for: account.id, now: Date())
            guard pending?.id == account.id else { return }
            revealed[account.id] = code
            lastConfirmedAt = Date()
            copy(code)
            phase = .copied
            Log.auth.notice("code handed over for « \(account.label, privacy: .public) »")
            closeSheet(account, after: .milliseconds(900))
        } catch let failure as OATHFailure {
            phase = .waiting
            errorMessage = failure.userMessage
        } catch {
            phase = .waiting
            errorMessage = error.localizedDescription
        }
    }

    /// Runs the biometric check for the sheet that is up. Hands back whether it passed.
    ///
    /// The outcome is dropped when a newer confirmation has started, so a late answer never
    /// validates a sheet the user has moved on from.
    private func authenticate() async -> Bool {
        confirmationGeneration += 1
        let generation = confirmationGeneration
        let label = pending?.label ?? String(localized: "ta YubiKey")
        authenticating = true
        Log.auth.notice("confirmation requested for « \(label, privacy: .public) »")

        let outcome = await gate.authenticate(reason: String(localized: "Copier le code de « \(label) »"))

        guard generation == confirmationGeneration else {
            Log.auth.notice("ignoring stale confirmation outcome \(String(describing: outcome), privacy: .public)")
            return false
        }
        authenticating = false

        switch outcome {
        case .success:
            return true
        case .cancelled:
            return false
        case .unavailable(let message), .failed(let message):
            errorMessage = message
            return false
        }
    }

    /// Closes the sheet, leaving the tick on screen long enough to be seen.
    ///
    /// Detached from the caller on purpose: a confirmation is over once the code is in the
    /// pasteboard, whatever the sheet does next.
    private func closeSheet(_ account: OATHAccount, after delay: Duration) {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, self.pending?.id == account.id, self.phase == .copied else { return }
            self.pending = nil
            self.phase = .waiting
        }
    }

    /// Closes the sheet without a code. A gesture in flight is abandoned: its outcome is
    /// dropped rather than handed to a sheet the user already dismissed.
    public func cancelConfirmation() {
        guard pending != nil || authenticating else { return }
        confirmationGeneration += 1
        authenticating = false
        pending = nil
        phase = .waiting
    }

    /// Copies a code to the pasteboard, arming the auto-clear delay.
    private func copy(_ code: OATHCode) {
        let delay = settings.clipboardClear.seconds
        clipboard.clearAfter = delay > 0 ? delay : nil
        clipboard.copy(code.code)
    }

    public func dismissError() {
        errorMessage = nil
    }

    // MARK: - Writing

    /// Writes a new credential to the key and refreshes the list.
    @discardableResult
    public func addCredential(_ credential: NewCredential) async -> Bool {
        await write { connection in
            let account = try await connection.session.addCredential(credential)
            try await self.list(connection)
            return String(localized: "« \(account.label) » ajouté sur la YubiKey.")
        }
    }

    /// Removes a credential from the key and refreshes the list.
    @discardableResult
    public func deleteAccount(_ account: OATHAccount) async -> Bool {
        await write { connection in
            try await connection.session.deleteCredential(account)
            try await self.list(connection)
            return String(localized: "Compte supprimé.")
        }
    }

    /// Renames a credential on the key and refreshes the list.
    @discardableResult
    public func renameAccount(_ account: OATHAccount, name: String, issuer: String?) async -> Bool {
        await write { connection in
            try await connection.session.renameCredential(account, name: name, issuer: issuer)
            try await self.list(connection)
            return String(localized: "Compte renommé.")
        }
    }

    /// Runs a write against the key: refused while the session is closed or while another
    /// write is in flight, the list is refreshed on success, and any failure becomes a
    /// banner message.
    private func write(_ operation: (any YubiKeyConnection) async throws -> String) async -> Bool {
        guard let connection, status.isReady, !adding else { return false }
        adding = true
        defer { adding = false }

        do {
            showConfirmation(try await operation(connection))
            return true
        } catch let failure as OATHFailure {
            errorMessage = failure.userMessage
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func dismissConfirmation() {
        confirmationTask?.cancel()
        confirmationTask = nil
        confirmation = nil
    }

    private func showConfirmation(_ message: String) {
        confirmationTask?.cancel()
        confirmation = message
        confirmationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.confirmation = nil
        }
    }

    public func dismissPasswordPrompt() {
        passwordPrompt = false
    }

    // MARK: - Ticking

    /// Periodic work: countdown publication, and hiding what has run out.
    /// Takes the current date so tests can drive it without waiting.
    func tick(now: Date) async {
        self.now = now

        guard status.isReady else { return }

        // A confirmed code only lives as long as its own window. Nothing is re-read from
        // the key behind the user's back: the next gesture is what produces the next code.
        for (id, code) in revealed where CodeClock.isExpired(code, now: now) {
            revealed[id] = nil
        }

        guard let lastConfirmedAt, settings.revealTimeout.seconds > 0,
            now.timeIntervalSince(lastConfirmedAt) >= settings.revealTimeout.seconds
        else { return }
        revealed = [:]
        self.lastConfirmedAt = nil
    }
}
