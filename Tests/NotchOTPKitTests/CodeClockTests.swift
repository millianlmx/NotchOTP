import Foundation
import Testing

@testable import NotchOTPKit

private let start = Date(timeIntervalSince1970: 1_700_000_000)

@Test func remainingNeverGoesNegative() {
    let code = code("123456", from: start)
    #expect(CodeClock.remaining(until: code.validTo, now: start) == 30)
    #expect(CodeClock.remaining(until: code.validTo, now: start.addingTimeInterval(45)) == 0)
}

@Test func codeExpiresExactlyAtItsEnd() {
    let code = code("123456", from: start)
    #expect(!CodeClock.isExpired(code, now: start.addingTimeInterval(29.999)))
    #expect(CodeClock.isExpired(code, now: code.validTo))
}

@Test func progressIsClampedToTheValidityWindow() {
    let code = code("123456", from: start)
    #expect(CodeClock.progress(from: code.validFrom, to: code.validTo, now: start) == 0)
    #expect(CodeClock.progress(from: code.validFrom, to: code.validTo, now: start.addingTimeInterval(15)) == 0.5)
    #expect(CodeClock.progress(from: code.validFrom, to: code.validTo, now: start.addingTimeInterval(90)) == 1)
    #expect(CodeClock.progress(from: start, to: start, now: start) == 1)
}

@Test func countdownLabelSwitchesToMinutes() {
    #expect(CodeClock.label(remaining: 45) == "45s")
    #expect(CodeClock.label(remaining: 60) == "1 min")
    #expect(CodeClock.label(remaining: 75) == "1m15")
}

@Test func theWindowFollowsTheClockRatherThanTheHour() {
    // What a masked row shows: the key is handed the Mac's date, so a code computed now
    // falls in the epoch-aligned window, not in one starting at some arbitrary moment.
    let moment = Date(timeIntervalSince1970: 1_700_000_020)

    let half = CodeClock.window(period: 30, now: moment)
    #expect(half.validFrom == Date(timeIntervalSince1970: 1_700_000_010))
    #expect(half.validTo == Date(timeIntervalSince1970: 1_700_000_040))

    // A 60-second credential has its own grid, and only its end lines up with the half one.
    let minute = CodeClock.window(period: 60, now: moment)
    #expect(minute.validFrom == Date(timeIntervalSince1970: 1_699_999_980))
    #expect(minute.validTo == half.validTo)
    #expect(CodeClock.remaining(until: minute.validTo, now: moment) == 20)
}
