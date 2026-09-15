import Foundation
import ScreenCaptureKit
import Testing

@testable import NotchOTPKit

@Test func aDeclinedScreenRecordingPromptIsReportedAsAPermissionProblem() {
    let declined = NSError(
        domain: SCStreamErrorDomain,
        code: SCStreamError.Code.userDeclined.rawValue
    )
    #expect(ScreenRegionPicker.failure(from: declined) == .permissionDenied)

    let silent = NSError(
        domain: "com.apple.ScreenCaptureKit.SCStreamErrorDomain",
        code: -3801,
        userInfo: [NSLocalizedDescriptionKey: "The user declined TCCs for application"]
    )
    #expect(ScreenRegionPicker.failure(from: silent) == .permissionDenied)
}

@Test func otherCaptureErrorsKeepTheirMessage() {
    let broken = NSError(
        domain: SCStreamErrorDomain,
        code: SCStreamError.Code.failedToStart.rawValue,
        userInfo: [NSLocalizedDescriptionKey: "le flux n'a pas démarré"]
    )
    #expect(ScreenRegionPicker.failure(from: broken) == .captureFailed("le flux n'a pas démarré"))
}

@MainActor
@Test func probeScreenRecordingState() async {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        print("SCREENCAP allowed, displays=\(content.displays.count)")
    } catch {
        print("SCREENCAP denied: \(error.localizedDescription) -> \(ScreenRegionPicker.failure(from: error))")
    }
}
