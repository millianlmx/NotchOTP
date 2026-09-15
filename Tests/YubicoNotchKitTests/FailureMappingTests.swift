import Foundation
import Testing
import YubiKit

@testable import YubicoNotchKit

@Test func aBusyKeyIsReportedAsBusyAndNotAsAFailure() {
    #expect(OATHFailure.map(SmartCardConnectionError.busy) == .keyBusy)
}

@Test func anUnreachableSmartCardServiceIsNotAKeyModelProblem() {
    #expect(OATHFailure.map(SmartCardConnectionError.unsupported) == .readerUnavailable)
}

@Test func missingAndLostKeysReportAsUnavailable() {
    #expect(OATHFailure.map(SmartCardConnectionError.noDevicesFound).isUnavailable)
    #expect(OATHFailure.map(SmartCardConnectionError.connectionLost).isUnavailable)
    #expect(OATHFailure.map(SmartCardConnectionError.cancelled).isUnavailable)
}

@Test func unknownErrorsKeepTheirDescription() {
    struct Custom: LocalizedError {
        var errorDescription: String? { "boum" }
    }
    #expect(OATHFailure.map(Custom()) == .device("boum"))
}

@Test func mappingIsIdempotent() {
    #expect(OATHFailure.map(OATHFailure.passwordRequired) == .passwordRequired)
    #expect(OATHFailure.map(OATHFailure.wrongPassword) == .wrongPassword)
}

extension OATHFailure {
    var isUnavailable: Bool {
        if case .keyUnavailable = self { return true }
        return false
    }
}
