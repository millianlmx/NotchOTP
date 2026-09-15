import Foundation
import Testing
import YubiKit

@testable import NotchOTPKit

@Test func credentialsAreTranslatedToTheSdkTemplate() {
    let credential = NewCredential(
        issuer: "GitHub",
        name: "me",
        secret: Data(repeating: 0x42, count: 20),
        kind: .totp(period: 60, digits: 8),
        algorithm: .sha256,
        requiresTouch: true
    )

    let template = credential.template
    #expect(template.type.period == 60)
    #expect(template.digits == 8)
    #expect(template.algorithm == .sha256)
    #expect(template.issuer == "GitHub")
    #expect(template.name == "me")
    #expect(template.requiresTouch)
    // The SDK keys a credential as "period/issuer:name" whenever the period is not 30 s.
    #expect(template.identifier == "60/GitHub:me")
}

@Test func hotpCredentialsKeepTheirCounter() {
    let credential = NewCredential(
        issuer: nil,
        name: "aws",
        secret: Data(repeating: 0x01, count: 20),
        kind: .hotp(counter: 7, digits: 6),
        algorithm: .sha1,
        requiresTouch: false
    )

    let template = credential.template
    #expect(template.type.counter == 7)
    #expect(template.type.period == nil)
    #expect(template.identifier == "aws")
}
