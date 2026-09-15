import Foundation
import Testing

@testable import YubicoNotchKit

@MainActor
@Test func settingsRoundTripThroughUserDefaults() {
    let defaults = UserDefaults(suiteName: "app.yubiconotch.tests.\(UUID().uuidString)")!
    let settings = Settings(defaults: defaults)
    settings.clipboardClear = .twoMinutes
    settings.revealTimeout = .oneMinute
    settings.rememberOATHPassword = true
    settings.confirmationMethod = .touchID

    let reloaded = Settings(defaults: defaults)
    #expect(reloaded.clipboardClear == .twoMinutes)
    #expect(reloaded.revealTimeout == .oneMinute)
    #expect(reloaded.rememberOATHPassword)
    #expect(reloaded.confirmationMethod == .touchID)
}

@MainActor
@Test func defaultsApplyForFreshAndUnknownStoredValues() {
    let fresh = UserDefaults(suiteName: "app.yubiconotch.tests.\(UUID().uuidString)")!
    let settings = Settings(defaults: fresh)
    #expect(settings.clipboardClear == .fortyFive)
    #expect(settings.revealTimeout == .fiveMinutes)
    #expect(!settings.rememberOATHPassword)
    #expect(settings.confirmationMethod == .touchID)

    fresh.set(9999, forKey: "clipboardClearSeconds")
    #expect(Settings(defaults: fresh).clipboardClear == .fortyFive)
}
