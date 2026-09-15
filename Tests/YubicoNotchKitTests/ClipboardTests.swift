import Foundation
import Testing

@testable import YubicoNotchKit

@MainActor
@Test func copyWipesThePasteboardAfterTheDelay() async {
    let pasteboard = FakePasteboard()
    let clipboard = Clipboard(pasteboard: pasteboard)
    clipboard.clearAfter = 0.15

    clipboard.copy("123456")
    #expect(pasteboard.string == "123456")

    try? await Task.sleep(for: .milliseconds(350))
    #expect(pasteboard.string == nil)
}

@MainActor
@Test func copyDoesNotWipeSomethingTheUserCopiedLater() async {
    let pasteboard = FakePasteboard()
    let clipboard = Clipboard(pasteboard: pasteboard)
    clipboard.clearAfter = 0.15

    clipboard.copy("123456")
    pasteboard.setString("un autre contenu")

    try? await Task.sleep(for: .milliseconds(350))
    #expect(pasteboard.string == "un autre contenu")
}

@MainActor
@Test func copyIsKeptWhenAutoClearIsDisabled() async {
    let pasteboard = FakePasteboard()
    let clipboard = Clipboard(pasteboard: pasteboard)

    clipboard.clearAfter = nil
    #expect(clipboard.copy("123456") == nil)

    try? await Task.sleep(for: .milliseconds(120))
    #expect(pasteboard.string == "123456")
}

@MainActor
@Test func lockWipesTheCopiedCodeImmediately() {
    let pasteboard = FakePasteboard()
    let clipboard = Clipboard(pasteboard: pasteboard)
    clipboard.clearAfter = nil
    clipboard.copy("123456")

    clipboard.clearIfStillOurs()
    #expect(pasteboard.string == nil)
}
