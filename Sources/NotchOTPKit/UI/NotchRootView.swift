import AppKit
import SwiftUI

/// Everything drawn inside the notch panel.
///
/// Collapsed, the panel is exactly the notch and draws nothing: the physical notch hides
/// it entirely. Hovering the notch opens it and lists what is stored on the key — and any
/// code behind that list is only handed over after a confirmation gesture.
public struct NotchRootView: View {

    @Bindable var service: YubiKeyService
    @Bindable var settings: Settings
    var window: NotchWindowController
    var onOpenSettings: () -> Void

    @State private var password = ""
    @State private var rememberPassword = false
    @State private var isAddingAccount = false
    @State private var draft = CredentialDraft()
    @State private var isSearching = false
    @State private var query = ""
    @State private var selection: Data?
    @State private var deletion: OATHAccount?
    @State private var renaming: OATHAccount?
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case password
        case query
    }

    public init(
        service: YubiKeyService,
        settings: Settings,
        window: NotchWindowController,
        onOpenSettings: @escaping () -> Void
    ) {
        self.service = service
        self.settings = settings
        self.window = window
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        Group {
            if window.isExpanded {
                expanded
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Without this the view never joins SwiftUI's focus system, and `onKeyPress`
        // below would never fire.
        .focusable(window.isExpanded)
        .focusEffectDisabled()
        .background(window.isExpanded ? PanelStyle.surface : .clear)
        .clipShape(
            NotchShape(
                topCornerRadius: PanelStyle.topCornerRadius,
                bottomCornerRadius: PanelStyle.bottomCornerRadius
            )
        )
        .onChange(of: window.isExpanded) { _, expanded in
            if expanded {
                onPanelOpened()
            } else {
                onPanelClosed()
            }
        }
        .onChange(of: service.pending) { _, pending in
            // The embedded prompt must be able to take focus while it is up, otherwise the
            // sensor press never reaches the evaluation. No app activation: the panel takes
            // key status on its own.
            pinPanel()
            if pending != nil {
                window.makeKeyForPrompt()
            }
        }
        .onChange(of: service.authenticating) { _, busy in
            pinPanel()
            if busy {
                window.makeKeyForPrompt()
            }
        }
        .onChange(of: service.phase) { _, phase in
            if phase == .copied {
                PanelFeedback.confirmed()
            }
        }
        .onChange(of: service.passwordPrompt) { _, _ in
            pinPanel()
            applyKeyInput()
            focus = service.passwordPrompt ? .password : nil
        }
        .onChange(of: service.status) { _, status in
            if !status.isReady {
                isAddingAccount = false
                deletion = nil
                renaming = nil
                isSearching = false
                query = ""
                selection = nil
            }
        }
        .onChange(of: isSearching) { _, searching in
            applyKeyInput()
            focus = searching ? .query : nil
        }
        .onChange(of: isAddingAccount) { _, _ in applyKeyInput() }
        .onAppear {
            window.onEscapeKey = { handleEscape() }
        }
        .modifier(
            PanelShortcuts(
                onUp: { moveSelection(by: -1) },
                onDown: { moveSelection(by: 1) },
                onCopy: { confirmSelection() },
                onEscape: { handleEscape() }
            )
        )
    }

    // MARK: - Behaviour

    private func onPanelOpened() {
        window.allowKeyStatus(true)
    }

    private func onPanelClosed() {
        window.setKeyInput(false)
        window.allowKeyStatus(false)
        window.keepsPanelOpen = false
        password = ""
        isSearching = false
        query = ""
        selection = nil
    }

    /// Fields, forms and confirmations take the keyboard; the plain list only *can*.
    private var hasTextEntry: Bool {
        isAddingAccount || isSearching || renaming != nil || deletion != nil || service.passwordPrompt
    }

    /// Keeps the panel on screen while something is being asked of the user: a gesture in
    /// progress, or a half-typed password, must not be yanked away by a stray pointer.
    private func pinPanel() {
        window.keepsPanelOpen = service.pending != nil || service.authenticating || hasTextEntry
    }

    private func applyKeyInput() {
        window.setKeyInput(isAddingAccount || isSearching || renaming != nil || deletion != nil || service.passwordPrompt)
    }

    // MARK: - Keyboard

    private func moveSelection(by offset: Int) {
        selection = PanelLogic.movedSelection(in: filteredAccounts, from: selection, by: offset)
    }

    private func confirmSelection() {
        guard let account = filteredAccounts.first(where: { $0.id == selection }) ?? filteredAccounts.first else {
            return
        }
        selection = account.id
        request(account)
    }

    /// Both the row and the keyboard land here: a code already handed over goes back to the
    /// pasteboard, anything else opens the sheet that asks for the gesture.
    private func request(_ account: OATHAccount) {
        withAnimation(PanelStyle.reducesMotion ? nil : PanelStyle.spring) {
            service.requestCode(for: account)
        }
    }

    private func handleEscape() {
        switch PanelLogic.escapeAction(
            isConfirming: service.pending != nil,
            isSearching: isSearching,
            isAddingAccount: isAddingAccount,
            isRenaming: renaming != nil,
            isDeleting: deletion != nil
        ) {
        case .clearSearch:
            isSearching = false
            query = ""
        case .closeForm:
            if service.pending != nil {
                service.cancelConfirmation()
            } else {
                isAddingAccount = false
                renaming = nil
                deletion = nil
            }
        case .collapse:
            window.collapse()
        }
    }

    private var filteredAccounts: [OATHAccount] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return service.accounts }
        return service.accounts.filter { $0.label.localizedCaseInsensitiveContains(needle) }
    }

    // MARK: - Chrome

    private var expanded: some View {
        VStack(spacing: 0) {
            commandShortcuts
            Color.clear.frame(height: window.notchHeight)
            header
            Divider().overlay(PanelStyle.hairline)
            if isSearching, service.status.isReady {
                searchField
            }
            body(for: service.status)
            if let confirmation = service.confirmation {
                banner(confirmation, tone: .success) { service.dismissConfirmation() }
            } else if let error = service.errorMessage {
                banner(error, tone: .error) { service.dismissError() }
            } else {
                footer
            }
        }
    }

    /// Command-key shortcuts: `onKeyPress` only handles unmodified keys on macOS 14.
    private var commandShortcuts: some View {
        Group {
            Button("Copier le code") { confirmSelection() }
                .keyboardShortcut("c", modifiers: .command)
            Button("Rechercher un compte") { isSearching = true }
                .keyboardShortcut("f", modifiers: .command)
            Button("Fermer") { handleEscape() }
                .keyboardShortcut("w", modifiers: .command)
        }
        .buttonStyle(.plain)
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "key.horizontal.fill")
                .font(.system(size: 14))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(statusColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            // A confirmation sheet is modal: nothing else in the panel is offered while it
            // is up, only the way out of it.
            if service.status.isReady, service.pending == nil {
                if isAddingAccount {
                    PanelIconButton(symbol: "chevron.backward", help: String(localized: "Retour à la liste")) {
                        isAddingAccount = false
                    }
                } else {
                    PanelIconButton(symbol: isSearching ? "xmark" : "magnifyingglass", help: String(localized: "Rechercher")) {
                        isSearching.toggle()
                        if !isSearching { query = "" }
                    }
                    PanelIconButton(symbol: "plus", help: String(localized: "Ajouter un compte")) {
                        draft = CredentialDraft()
                        isAddingAccount = true
                    }
                    PanelIconButton(symbol: "lock.fill", help: String(localized: "Verrouiller")) {
                        service.lock()
                    }
                }
            }
            PanelIconButton(symbol: "gearshape", help: String(localized: "Réglages")) { onOpenSettings() }
        }
        .padding(.horizontal, PanelStyle.horizontalPadding)
        .frame(height: PanelStyle.headerHeight)
    }

    private var title: String {
        switch service.status {
        case .searching, .unavailable:
            return String(localized: "NotchOTP")
        case .locked(let info), .ready(let info):
            return String(localized: "YubiKey \(info.firmware)")
        }
    }

    private var subtitle: String? {
        if isAddingAccount { return String(localized: "Nouveau compte") }
        if renaming != nil { return String(localized: "Renommer") }
        if deletion != nil { return String(localized: "Supprimer") }
        switch service.status {
        case .searching:
            return String(localized: "Aucune clé détectée")
        case .unavailable(let message):
            return message
        case .locked:
            if service.lockedByUser { return String(localized: "Verrouillée") }
            return service.passwordPrompt ? String(localized: "Mot de passe OATH") : String(localized: "Lecture de la clé…")
        case .ready:
            let count = service.accounts.count
            if count == 0 { return String(localized: "Aucun compte OATH") }
            return count == 1 ? String(localized: "1 compte") : String(localized: "\(count) comptes")
        }
    }

    private var statusColor: Color {
        switch service.status {
        case .searching: return .secondary
        case .locked: return Color(nsColor: .systemOrange)
        case .ready: return Color(nsColor: .systemGreen)
        case .unavailable: return Color(nsColor: .systemRed)
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Rechercher un compte", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($focus, equals: .query)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Effacer la recherche")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(PanelStyle.controlFill, in: Capsule())
        .padding(.horizontal, PanelStyle.horizontalPadding)
        .padding(.top, 8)
    }

    // MARK: - Body states

    @ViewBuilder
    private func body(for status: YubiKeyService.Status) -> some View {
        switch status {
        case .searching:
            placeholder(
                symbol: "cable.connector",
                title: String(localized: "Branche ta YubiKey"),
                detail: String(localized: "En USB-C. Le panneau se met à jour dès qu'elle est détectée.")
            )
        case .unavailable(let message):
            placeholder(symbol: "exclamationmark.triangle", title: String(localized: "YubiKey indisponible"), detail: message)
        case .locked:
            if service.passwordPrompt {
                passwordPrompt
            } else if service.lockedByUser {
                placeholder(
                    symbol: "lock.fill",
                    title: String(localized: "Verrouillé"),
                    detail: String(localized: "Quitte l'encoche et reviens pour réafficher tes comptes : chaque code demandera son empreinte.")
                )
            } else {
                placeholder(
                    symbol: "key.horizontal",
                    title: String(localized: "Lecture de la clé…"),
                    detail: String(localized: "Les comptes apparaissent dès que l'applet OATH répond.")
                )
            }
        case .ready:
            if let account = service.pending {
                confirmationSheet(for: account)
            } else if isAddingAccount {
                AddAccountForm(
                    draft: $draft,
                    service: service,
                    onCancel: { isAddingAccount = false },
                    onSubmitted: {
                        isAddingAccount = false
                        draft = CredentialDraft()
                    },
                    onScanScreen: { scanScreenForQRCode() },
                    onOpenScreenRecordingSettings: {
                        NSWorkspace.shared.open(Self.screenRecordingSettingsURL)
                    }
                )
            } else if let account = deletion {
                DeleteAccountConfirmation(
                    account: account,
                    isWorking: service.adding,
                    onCancel: { deletion = nil },
                    onConfirm: {
                        Task {
                            if await service.deleteAccount(account) { deletion = nil }
                        }
                    }
                )
            } else if let account = renaming {
                RenameAccountForm(
                    account: account,
                    isWorking: service.adding,
                    onCancel: { renaming = nil },
                    onSubmit: { name, issuer in
                        Task {
                            if await service.renameAccount(account, name: name, issuer: issuer) { renaming = nil }
                        }
                    }
                )
            } else {
                accountList
            }
        }
    }

    /// The gesture that hands the code over starts as soon as the embedded control is
    /// really in a window — that is what keeps the prompt inside the panel — and starts
    /// again when the user clicks it after an attempt that did not go through.
    private func confirmationSheet(for account: OATHAccount) -> some View {
        CodeConfirmationView(
            account: account,
            code: service.revealed[account.id],
            phase: service.phase,
            context: service.biometricContext,
            method: settings.confirmationMethod,
            onConfirm: { Task { await service.performConfirmation() } },
            onCancel: { service.cancelConfirmation() }
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func placeholder(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 2)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(1)
                .padding(.horizontal, 52)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var passwordPrompt: some View {
        VStack(spacing: 10) {
            Text("Mot de passe OATH")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Text("La YubiKey demande le mot de passe de l'applet OATH.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 50)

            SecureField("Mot de passe", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .focused($focus, equals: .password)
                .onSubmit { submitPassword() }

            Toggle("Mémoriser dans le trousseau", isOn: $rememberPassword)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Spacer()
                Button("Annuler") {
                    service.dismissPasswordPrompt()
                    password = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)

                Button("Déverrouiller") { submitPassword() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, PanelStyle.horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            rememberPassword = settings.rememberOATHPassword
            focus = .password
        }
    }

    private func submitPassword() {
        guard !password.isEmpty else { return }
        let value = password
        password = ""
        Task { await service.submitPassword(value, remember: rememberPassword) }
    }

    private var accountList: some View {
        AccountListView(
            accounts: filteredAccounts,
            revealed: service.revealed,
            now: service.now,
            selection: selection,
            isAnimatingAppearance: !PanelStyle.reducesMotion,
            onConfirm: { account in
                selection = account.id
                request(account)
            },
            onRename: { account in renaming = account },
            onDelete: { account in deletion = account }
        )
        .overlay {
            if service.accounts.isEmpty {
                placeholder(
                    symbol: "person.badge.key",
                    title: String(localized: "Aucun compte OATH"),
                    detail: String(localized: "Clique sur + pour enregistrer un compte depuis un lien otpauth:// ou un QR code.")
                )
            } else if filteredAccounts.isEmpty {
                placeholder(
                    symbol: "magnifyingglass",
                    title: String(localized: "Aucun résultat"),
                    detail: String(localized: "Aucun compte ne correspond à « \(query) ».")
                )
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if let hint = footerHint {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PanelStyle.horizontalPadding)
        .padding(.bottom, 8)
        .padding(.top, 2)
    }

    private var footerHint: String? {
        guard service.status.isReady, service.pending == nil, !hasTextEntry else { return nil }
        if let clearAt = service.clipboard.clearAt, clearAt > service.now {
            return String(localized: "Presse-papiers vidé dans \(CodeClock.label(remaining: clearAt.timeIntervalSince(service.now)))")
        }
        guard !service.accounts.isEmpty else { return nil }
        return window.hasKeyboardFocus
            ? String(localized: "↑↓ naviguer · ⏎ confirmer · ⌘F rechercher")
            : String(localized: "Cliquer un compte demande une confirmation")
    }

    // MARK: - Screen scanning

    /// Gets the panel out of the way, lets the user drag a region over any screen, and
    /// fills the form with the `otpauth://` payload found in it.
    private func scanScreenForQRCode() {
        Task {
            window.setKeyInput(false)
            window.collapse()

            do {
                let payload = try await ScreenRegionPicker().pickOTPAuthRegion()
                draft.apply(otpauthURI: payload)
            } catch ScreenRegionPicker.Failure.cancelled {
                // Nothing to report: the user pressed Escape.
            } catch ScreenRegionPicker.Failure.permissionDenied {
                draft.report(
                    String(localized: "Autorise l'enregistrement de l'écran, puis réessaie."),
                    permissionHelp: true
                )
            } catch ScreenRegionPicker.Failure.noCodeFound {
                draft.report(String(localized: "Aucun QR code otpauth:// trouvé dans la sélection."))
            } catch ScreenRegionPicker.Failure.captureFailed(let message) {
                draft.report(message)
            } catch {
                draft.report(error.localizedDescription)
            }

            window.expand()
            applyKeyInput()
        }
    }

    private static let screenRecordingSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )!

    // MARK: - Banner

    private enum Tone {
        case error
        case success
    }

    private func banner(_ message: String, tone: Tone, dismiss: @escaping () -> Void) -> some View {
        let tint: Color = tone == .error ? Color(nsColor: .systemRed) : Color(nsColor: .systemGreen)
        let symbol = tone == .error ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
        return HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .symbolRenderingMode(.hierarchical)
            Text(message)
                .font(.system(size: 11))
                .lineLimit(2)
            Spacer(minLength: 4)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fermer le message")
        }
        .foregroundStyle(tint)
        .padding(.horizontal, PanelStyle.horizontalPadding)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().overlay(PanelStyle.hairline) }
    }
}

/// Keyboard shortcuts for the panel. Split out so the root view stays readable.
private struct PanelShortcuts: ViewModifier {

    let onUp: () -> Void
    let onDown: () -> Void
    let onCopy: () -> Void
    let onEscape: () -> Void

    func body(content: Content) -> some View {
        content
            .onKeyPress(.upArrow) {
                onUp()
                return .handled
            }
            .onKeyPress(.downArrow) {
                onDown()
                return .handled
            }
            .onKeyPress(.return) {
                onCopy()
                return .handled
            }
            .onKeyPress(.escape) {
                onEscape()
                return .handled
            }
    }
}
