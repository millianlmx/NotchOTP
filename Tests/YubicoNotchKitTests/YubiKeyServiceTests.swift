import Foundation
import Testing

@testable import YubicoNotchKit

private let now = Date()

// MARK: - Opening the panel

@MainActor
@Test func connectingListsNothingUntilThePanelOpens() async {
    let github = account(issuer: "GitHub", name: "me")
    let harness = await Harness.make(
        accounts: [github],
        codes: [github.id: code("123456", from: now)]
    )
    defer { harness.stop() }

    #expect(harness.service.status == .locked(.init(firmware: "5.7.4")))
    #expect(harness.service.accounts.isEmpty)
}

@MainActor
@Test func openingThePanelListsEveryAccountWithoutComputingASingleCode() async {
    let github = account(issuer: "GitHub", name: "me")
    let proton = account(issuer: "Proton", name: "me", period: 60)
    let alpha = account(issuer: "alpha", name: "me")
    let harness = await Harness.make(
        accounts: [proton, github, alpha],
        codes: [
            github.id: code("111111", from: now),
            proton.id: code("22222222", from: now, period: 60),
        ]
    )
    defer { harness.stop() }

    #expect(await harness.openPanel())

    #expect(harness.service.status == .ready(.init(firmware: "5.7.4")))
    #expect(harness.service.accounts.map(\.issuer) == ["alpha", "GitHub", "Proton"])
    #expect(harness.service.revealed.isEmpty)
    // The whole model in one assertion: a listing is names only, never codes.
    #expect(await harness.session.codeRequests == 0)
}

@MainActor
@Test func aListingFailureIsReportedAndLeavesThePanelClosed() async {
    let harness = await Harness.make(listFailure: .device("applet muette"))
    defer { harness.stop() }

    await harness.service.setPanelVisible(true)
    #expect(await harness.waitUntil { harness.service.errorMessage != nil })

    #expect(harness.service.status == .locked(.init(firmware: "5.7.4")))
    #expect(harness.service.errorMessage == "applet muette")
}

// MARK: - One gesture, one code

@MainActor
@Test func askingForACodeHandsNothingOverByItself() async {
    let github = account(issuer: "GitHub", name: "me")
    let harness = await Harness.make(
        accounts: [github],
        codes: [github.id: code("123456", from: now)]
    )
    defer { harness.stop() }
    await harness.openPanel()

    harness.service.requestCode(for: github)

    #expect(harness.service.pending?.id == github.id)
    #expect(harness.service.phase == .waiting)
    #expect(harness.pasteboard.string == nil)
    #expect(harness.service.revealed.isEmpty)
    #expect(await harness.session.codeRequests == 0)
}

@MainActor
@Test func confirmingHandsOverExactlyOneCode() async {
    let github = account(issuer: "GitHub", name: "me")
    let proton = account(issuer: "Proton", name: "me")
    let harness = await Harness.make(
        accounts: [github, proton],
        codes: [
            github.id: code("111111", from: now),
            proton.id: code("222222", from: now),
        ],
        configure: { $0.clipboardClear = .thirty }
    )
    defer { harness.stop() }
    await harness.openPanel()

    harness.service.requestCode(for: github)
    await harness.service.performConfirmation()

    #expect(harness.service.revealed[github.id]?.code == "111111")
    #expect(harness.service.revealed[proton.id] == nil, "one gesture must not reveal the whole key")
    #expect(harness.pasteboard.string == "111111")
    #expect(harness.clipboard.clearAfter == 30)
    #expect(harness.service.phase == .copied)
    #expect(await harness.waitUntil { harness.service.pending == nil }, "the sheet closes itself")
    #expect(await harness.session.codeRequests == 1)
}

@MainActor
@Test func aSecondAccountNeedsItsOwnGesture() async {
    let github = account(issuer: "GitHub", name: "me")
    let proton = account(issuer: "Proton", name: "me")
    let gate = RecordingGate(outcome: .success)
    let harness = await Harness.make(
        accounts: [github, proton],
        codes: [
            github.id: code("111111", from: now),
            proton.id: code("222222", from: now),
        ],
        customGate: gate
    )
    defer { harness.stop() }
    await harness.openPanel()

    await harness.confirm(github)
    #expect(gate.calls == 1)

    harness.service.requestCode(for: proton)
    #expect(harness.pasteboard.string == "111111", "the sheet alone must not hand over anything")
    await harness.service.performConfirmation()

    #expect(gate.calls == 2)
    #expect(harness.pasteboard.string == "222222")
    #expect(harness.service.revealed.count == 2)
}

@MainActor
@Test func aCodeAlreadyRevealedGoesBackToThePasteboardWithoutANewGesture() async {
    let github = account(issuer: "GitHub", name: "me")
    let gate = RecordingGate(outcome: .success)
    let harness = await Harness.make(
        accounts: [github],
        codes: [github.id: code("123456", from: now)],
        customGate: gate
    )
    defer { harness.stop() }
    await harness.openPanel()
    await harness.confirm(github)

    harness.pasteboard.clear()
    harness.service.requestCode(for: github)

    #expect(harness.pasteboard.string == "123456")
    #expect(harness.service.pending == nil, "nothing left to confirm")
    #expect(gate.calls == 1)
    #expect(await harness.session.codeRequests == 1)
}

@MainActor
@Test func openingThePanelStartsTheCountdownAtOnce() async {
    // The ticker sleeps five seconds while the panel is hidden. Without re-arming it on the
    // way in, the tick already in progress finishes its nap first, and the rings sit frozen
    // for the rest of it — six seconds of nothing after the notch is opened.
    let github = account(issuer: "GitHub", name: "me")
    let harness = await Harness.make(accounts: [github])
    defer { harness.stop() }
    await harness.openPanel()

    harness.service.setPanelVisible(false)
    try? await Task.sleep(for: .seconds(2))
    let before = harness.service.now

    harness.service.setPanelVisible(true)
    try? await Task.sleep(for: .milliseconds(150))

    #expect(harness.service.now > before, "the countdown waited out the idle interval")
}

@MainActor
@Test func lockingStaysLockedWhileThePanelIsOpen() async {
    let github = account(issuer: "GitHub", name: "me")
    let harness = await Harness.make(accounts: [github])
    defer { harness.stop() }
    await harness.openPanel()

    harness.service.lock()

    #expect(harness.service.lockedByUser)
    #expect(harness.service.status == .locked(.init(firmware: "5.7.4")))
    #expect(harness.service.accounts.isEmpty)

    // The watcher reconnects the instant the lock closes the connection. Listing again here
    // is exactly what made the button look like it did nothing.
    #expect(await harness.waitFor { await harness.connector.connectCount >= 2 })
    try? await Task.sleep(for: .milliseconds(100))
    #expect(harness.service.accounts.isEmpty, "the lock undid itself while the panel stayed open")
    #expect(!harness.service.status.isReady)

    // Leaving the notch and coming back is the fresh intent that lists again.
    harness.service.setPanelVisible(false)
    harness.service.setPanelVisible(true)

    #expect(await harness.waitUntil { harness.service.status.isReady })
    #expect(harness.service.accounts.map(\.label) == ["GitHub · me"])
}

@MainActor
@Test func aCancelledGestureHandsNothingOverAndLeavesTheSheetUp() async {
    let github = account(issuer: "GitHub", name: "me")
    let harness = await Harness.make(
        accounts: [github],
        codes: [github.id: code("123456", from: now)],
        gate: .cancelled
    )
    defer { harness.stop() }
    await harness.openPanel()

    harness.service.requestCode(for: github)
    await harness.service.performConfirmation()

    #expect(harness.pasteboard.string == nil)
    #expect(harness.service.revealed.isEmpty)
    #expect(harness.service.pending?.id == github.id, "the user can try again")
    #expect(harness.service.phase == .waiting)
    #expect(harness.service.errorMessage == nil)
}

@MainActor
@Test func aRefusedGestureExplainsItself() async {
    let github = account(issuer: "GitHub", name: "me")
    let harness = await Harness.make(
        accounts: [github],
        codes: [github.id: code("123456", from: now)],
        gate: .unavailable("Aucune empreinte enregistrée sur ce Mac.")
    )
    defer { harness.stop() }
    await harness.openPanel()

    harness.service.requestCode(for: github)
    await harness.service.performConfirmation()

    #expect(harness.service.errorMessage == "Aucune empreinte enregistrée sur ce Mac.")
    #expect(harness.pasteboard.string == nil)
}

@MainActor
@Test func holdMethodConfirmsWithoutEverAskingTheGate() async {
    let github = account(issuer: "GitHub", name: "me")
    let gate = RecordingGate(outcome: .cancelled)
    let harness = await Harness.make(
        accounts: [github],
        codes: [github.id: code("123456", from: now)],
        customGate: gate,
        configure: { $0.confirmationMethod = .hold }
    )
    defer { harness.stop() }
    await harness.openPanel()

    await harness.confirm(github)

    #expect(harness.pasteboard.string == "123456")
    #expect(gate.calls == 0)
}

@MainActor
@Test func closingThePanelAbandonsTheConfirmation() async {
    let github = account(issuer: "GitHub", name: "me")
    let harness = await Harness.make(
        accounts: [github],
        codes: [github.id: code("123456", from: now)]
    )
    defer { harness.stop() }
    await harness.openPanel()
    harness.service.requestCode(for: github)

    harness.service.setPanelVisible(false)

    #expect(harness.service.pending == nil)
    // A gesture that arrives after the sheet is gone must not hand anything over.
    await harness.service.performConfirmation()
    #expect(harness.pasteboard.string == nil)
}

// MARK: - Hiding again

@MainActor
@Test func aRevealedCodeDisappearsWithItsOwnWindow() async {
    let github = account(issuer: "GitHub", name: "me")
    let harness = await Harness.make(
        accounts: [github],
        codes: [github.id: code("123456", from: now)]
    )
    defer { harness.stop() }
    await harness.openPanel()
    await harness.confirm(github)

    await harness.service.tick(now: now.addingTimeInterval(30))

    #expect(harness.service.revealed.isEmpty)
}

@MainActor
@Test func revealedCodesAreHiddenAfterTheConfiguredDelay() async {
    // A code with no expiry of its own: this is about the delay, not about the window.
    let github = account(issuer: "GitHub", name: "me", kind: .hotp(counter: 0))
    let harness = await Harness.make(
        accounts: [github],
        codes: [github.id: code("123456", from: now, period: 3600)],
        configure: { $0.revealTimeout = .oneMinute }
    )
    defer { harness.stop() }
    await harness.openPanel()
    await harness.confirm(github)
    #expect(harness.service.revealed[github.id] != nil)

    await harness.service.tick(now: Date().addingTimeInterval(61))

    #expect(harness.service.revealed.isEmpty)
}

@MainActor
@Test func lockingHidesEverythingAndRelocksTheApplet() async {
    let github = account(issuer: "GitHub", name: "me")
    let harness = await Harness.make(
        accounts: [github],
        codes: [github.id: code("123456", from: now)]
    )
    defer { harness.stop() }
    await harness.openPanel()
    await harness.confirm(github)

    harness.service.lock()

    #expect(harness.service.status == .locked(.init(firmware: "5.7.4")))
    #expect(harness.service.accounts.isEmpty)
    #expect(harness.service.revealed.isEmpty)
    #expect(harness.pasteboard.string == nil)
    #expect(await harness.waitFor { await harness.state.closeCount == 1 })
}

// MARK: - Password-protected applet

@MainActor
@Test func aStoredPasswordOpensTheAppletOnItsOwn() async {
    let github = account(issuer: "GitHub", name: "me")
    let harness = await Harness.make(
        accounts: [github],
        password: "s3cret",
        configure: { $0.rememberOATHPassword = true }
    )
    defer { harness.stop() }
    try? harness.passwords.setPassword("s3cret")

    #expect(await harness.openPanel())

    #expect(await harness.session.unlockCount == 1)
    #expect(harness.service.accounts.map(\.label) == ["GitHub · me"])
    #expect(harness.service.passwordPrompt == false)
}

@MainActor
@Test func aStoredPasswordTheKeyRejectsIsForgotten() async throws {
    let github = account(issuer: "GitHub", name: "me")
    let harness = await Harness.make(
        accounts: [github],
        password: "s3cret",
        configure: { $0.rememberOATHPassword = true }
    )
    defer { harness.stop() }
    try? harness.passwords.setPassword("périmé")

    await harness.service.setPanelVisible(true)
    #expect(await harness.waitUntil { harness.service.passwordPrompt })

    #expect(!harness.service.status.isReady)
    let remaining = try harness.passwords.password()
    #expect(remaining == nil)
}

@MainActor
@Test func withoutAStoredPasswordThePanelAsksForOne() async {
    let harness = await Harness.make(password: "s3cret")
    defer { harness.stop() }

    await harness.service.setPanelVisible(true)
    #expect(await harness.waitUntil { harness.service.passwordPrompt })

    #expect(harness.service.errorMessage == OATHFailure.passwordRequired.userMessage)
}

@MainActor
@Test func submittingThePasswordOpensTheAppletAndRemembersIt() async throws {
    let github = account(issuer: "GitHub", name: "me")
    let harness = await Harness.make(
        accounts: [github],
        password: "s3cret"
    )
    defer { harness.stop() }

    await harness.service.submitPassword("s3cret", remember: true)

    #expect(harness.service.status.isReady)
    #expect(harness.service.accounts.map(\.label) == ["GitHub · me"])
    #expect(harness.settings.rememberOATHPassword)
    let stored = try harness.passwords.password()
    #expect(stored == "s3cret")
}

// MARK: - Writing to the key

@MainActor
@Test func addingACredentialWritesItAndShowsItInTheList() async {
    let github = account(issuer: "GitHub", name: "me")
    let harness = await Harness.make(accounts: [github])
    defer { harness.stop() }
    await harness.openPanel()

    let added = NewCredential(
        issuer: "Proton",
        name: "me",
        secret: Data(repeating: 0x42, count: 20),
        kind: .totp(period: 30, digits: 6),
        algorithm: .sha1,
        requiresTouch: false
    )

    #expect(await harness.service.addCredential(added))

    let written = await harness.session.added
    #expect(written.count == 1)
    #expect(written.first?.issuer == "Proton")
    #expect(harness.service.accounts.map(\.issuer) == ["GitHub", "Proton"])
    #expect(harness.service.confirmation != nil)
}

@MainActor
@Test func aRejectedCredentialKeepsTheFormOpenAndReportsWhy() async {
    let harness = await Harness.make()
    defer { harness.stop() }
    await harness.openPanel()
    await harness.session.failNextAdd(with: .device("plus de place"))

    let added = NewCredential(
        issuer: nil,
        name: "me",
        secret: Data(repeating: 0x42, count: 20),
        kind: .totp(period: 30, digits: 6),
        algorithm: .sha1,
        requiresTouch: false
    )

    #expect(await harness.service.addCredential(added) == false)
    #expect(harness.service.errorMessage == "plus de place")
    #expect(await harness.session.added.isEmpty)
}

@MainActor
@Test func writingIsRefusedWhileTheKeyIsNotOpen() async {
    let harness = await Harness.make()
    defer { harness.stop() }

    let added = NewCredential(
        issuer: nil,
        name: "me",
        secret: Data(repeating: 0x42, count: 20),
        kind: .totp(period: 30, digits: 6),
        algorithm: .sha1,
        requiresTouch: false
    )

    #expect(await harness.service.addCredential(added) == false)
    #expect(await harness.session.added.isEmpty)
}

@MainActor
@Test func unpluggingTheKeyReturnsToSearching() async {
    let github = account(issuer: "GitHub", name: "me")
    let harness = await Harness.make(accounts: [github])
    defer { harness.stop() }
    await harness.openPanel()

    await harness.connector.setDevicePresent(false)
    await harness.state.close()

    #expect(await harness.waitFor { harness.service.status == .searching })
    #expect(harness.service.accounts.isEmpty)
}

@MainActor
@Test func deletingAnAccountRemovesItFromTheKeyAndTheList() async {
    let github = account(issuer: "GitHub", name: "me")
    let proton = account(issuer: "Proton", name: "me")
    let harness = await Harness.make(accounts: [github, proton])
    defer { harness.stop() }
    await harness.openPanel()

    #expect(await harness.service.deleteAccount(github))

    #expect(harness.service.accounts.map(\.label) == ["Proton · me"])
    #expect(harness.service.confirmation != nil)
}

@MainActor
@Test func aRejectedDeletionKeepsTheAccountAndReportsWhy() async {
    let github = account(issuer: "GitHub", name: "me")
    let harness = await Harness.make(accounts: [github])
    defer { harness.stop() }
    await harness.openPanel()
    await harness.session.failNextDelete(with: .device("applet verrouillée"))

    #expect(await harness.service.deleteAccount(github) == false)

    #expect(harness.service.accounts.map(\.label) == ["GitHub · me"])
    #expect(harness.service.errorMessage == "applet verrouillée")
    #expect(harness.service.confirmation == nil)
}

@MainActor
@Test func renamingAnAccountRelabelsIt() async {
    let github = account(issuer: "GitHub", name: "me")
    let harness = await Harness.make(accounts: [github])
    defer { harness.stop() }
    await harness.openPanel()

    #expect(await harness.service.renameAccount(github, name: "perso", issuer: "GitHub"))

    #expect(harness.service.accounts.map(\.label) == ["GitHub · perso"])
    #expect(harness.service.confirmation != nil)
}

@MainActor
@Test func aRejectedRenameKeepsTheOldLabelAndReportsWhy() async {
    let github = account(issuer: "GitHub", name: "me")
    let harness = await Harness.make(accounts: [github])
    defer { harness.stop() }
    await harness.openPanel()
    await harness.session.failNextRename(with: .device("cette YubiKey ne sait pas renommer un compte."))

    #expect(await harness.service.renameAccount(github, name: "perso", issuer: "GitHub") == false)

    #expect(harness.service.accounts.map(\.label) == ["GitHub · me"])
    #expect(harness.service.errorMessage == "cette YubiKey ne sait pas renommer un compte.")
}

// MARK: - No key

@MainActor
@Test func runningWithoutAKeyStaysIdleInsteadOfShowingAnError() async {
    let defaults = UserDefaults(suiteName: "app.yubiconotch.tests.\(UUID().uuidString)")!
    let connector = FailingConnector(failure: .readerUnavailable)
    let service = YubiKeyService(
        connector: connector,
        gate: FixedGate(outcome: .success),
        passwords: OATHPasswordStore(service: "app.yubiconotch.tests", account: UUID().uuidString),
        settings: Settings(defaults: defaults),
        clipboard: Clipboard(pasteboard: FakePasteboard())
    )
    service.start()
    defer { service.stop() }

    #expect(await waitForAttempts(connector))
    #expect(service.status == .searching)
    #expect(service.errorMessage == nil)
}

@MainActor
private func waitForAttempts(_ connector: FailingConnector) async -> Bool {
    for _ in 0..<200 {
        if await connector.connectAttempts >= 1 { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return false
}
