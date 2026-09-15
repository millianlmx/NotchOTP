import Foundation
import Testing

@testable import NotchOTPKit

/// `JBSWY3DPEHPK3PXP` is the RFC 4648 §10 vector: "Hello!" followed by 0xDEADBEEF.
private let helloSecret = Data([0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x21, 0xde, 0xad, 0xbe, 0xef])

// MARK: - Base32

@Test func base32DecodesTheRFC4648Vectors() {
    #expect(Base32.decode("MZXW6===") == Data("foo".utf8))
    #expect(Base32.decode("MZXW6") == Data("foo".utf8))
    #expect(Base32.decode("mzxw6") == Data("foo".utf8))
    #expect(Base32.decode("JBSWY3DPEHPK3PXP") == helloSecret)
}

@Test func base32IgnoresWhitespaceAndDashes() {
    #expect(Base32.decode("JBSW-Y3DP EHPK-3PXP") == helloSecret)
    #expect(Base32.decode("  jbsw y3dp ehpk 3pxp  ") == helloSecret)
}

@Test func base32RejectsCharactersOutsideTheAlphabet() {
    #expect(Base32.decode("MZXW6!") == nil)
    #expect(Base32.decode("1") == nil)
    #expect(Base32.decode("MZXW0") == nil)
}

@Test func base32RejectsTruncatedBitStreams() {
    #expect(Base32.decode("M") == nil)          // five bits: not even one byte
    #expect(Base32.decode("MZXW6=") == nil)     // padding that does not close the group
    #expect(Base32.decode("MZXW6====") == nil)
    #expect(Base32.decode("MZXW7") == nil)      // leftover bits are not zero
    #expect(Base32.decode("MZXW6===Z") == nil)  // payload after the padding
}

// MARK: - otpauth:// parsing

@Test func parseReadsACompleteTOTPLinkWithTheIssuerInTheLabel() throws {
    let credential = try #require(
        try? NewCredential.parse(
            otpauthURI: "otpauth://totp/ACME%20Co:john.doe@example.com"
                + "?secret=JBSWY3DPEHPK3PXP&issuer=Autre%20Editeur&algorithm=SHA256&digits=8&period=60"
        ).get()
    )

    // The label wins over the query parameter.
    #expect(credential.issuer == "ACME Co")
    #expect(credential.name == "john.doe@example.com")
    #expect(credential.secret == helloSecret)
    #expect(credential.kind == .totp(period: 60, digits: 8))
    #expect(credential.algorithm == .sha256)
    #expect(credential.requiresTouch == false)
}

@Test func parseFallsBackToTheIssuerParameterAndTheDefaults() throws {
    let credential = try #require(
        try? NewCredential.parse(
            otpauthURI: "otpauth://totp/alice%40example.com?secret=JBSWY3DPEHPK3PXP&issuer=ACME"
        ).get()
    )

    #expect(credential.issuer == "ACME")
    #expect(credential.name == "alice@example.com")
    #expect(credential.kind == .totp(period: 30, digits: 6))
    #expect(credential.algorithm == .sha1)
}

@Test func parseReadsTheHOTPCounter() throws {
    let credential = try #require(
        try? NewCredential.parse(
            otpauthURI: "otpauth://hotp/ACME:alice?secret=JBSWY3DPEHPK3PXP&counter=7&digits=8"
        ).get()
    )

    #expect(credential.issuer == "ACME")
    #expect(credential.name == "alice")
    #expect(credential.kind == .hotp(counter: 7, digits: 8))
}

@Test func parseReadsASecretEncodedLikeAFormValue() throws {
    // A literal '+' is never valid base32, so it can only mean the space it stands for.
    let credential = try #require(
        try? NewCredential.parse(
            otpauthURI: "otpauth://totp/alice?secret=JBSWY3DP+EHPK3PXP"
        ).get()
    )

    #expect(credential.secret == helloSecret)
}

@Test func parseRejectsMalformedLinks() {
    func error(_ uri: String) -> NewCredential.ParsingError? {
        guard case .failure(let error) = NewCredential.parse(otpauthURI: uri) else { return nil }
        return error
    }

    #expect(error("https://totp/alice?secret=JBSWY3DPEHPK3PXP") == .unsupportedScheme)
    #expect(error("otpauth:/totp/alice?secret=JBSWY3DPEHPK3PXP") == .unsupportedScheme)
    #expect(error("otpauth://steam/alice?secret=JBSWY3DPEHPK3PXP") == .unsupportedType)
    #expect(error("otpauth:///alice?secret=JBSWY3DPEHPK3PXP") == .unsupportedType)
    #expect(error("otpauth://totp/alice") == .missingSecret)
    #expect(error("otpauth://totp/alice?secret=1") == .invalidSecret)
    #expect(error("otpauth://totp/alice?secret=") == .invalidSecret)
    #expect(error("otpauth://hotp/alice?secret=JBSWY3DPEHPK3PXP") == .missingCounter)
    #expect(error("otpauth://totp/?secret=JBSWY3DPEHPK3PXP") == .missingName)
    #expect(error("otpauth://totp/ACME:%20?secret=JBSWY3DPEHPK3PXP") == .missingName)
    #expect(error("otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP&algorithm=SHA3") == .invalidValue)
    #expect(error("otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP&digits=5") == .invalidValue)
    #expect(error("otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP&period=0") == .invalidValue)
    #expect(error("otpauth://hotp/alice?secret=JBSWY3DPEHPK3PXP&counter=abc") == .invalidValue)
}

// MARK: - Typed form

@Test func fromFormBuildsACredentialFromTypedFields() throws {
    let credential = try #require(
        try? NewCredential.fromForm(
            issuer: "  ACME  ",
            name: " alice ",
            secretText: "JBSWY3DP EHPK3PXP",
            kind: .totp(period: 60, digits: 8),
            requiresTouch: true
        ).get()
    )

    #expect(credential.issuer == "ACME")
    #expect(credential.name == "alice")
    #expect(credential.secret == helloSecret)
    #expect(credential.kind == .totp(period: 60, digits: 8))
    #expect(credential.algorithm == .sha1)
    #expect(credential.requiresTouch)
}

@Test func fromFormKeepsABlankIssuerAsAbsent() throws {
    let credential = try #require(
        try? NewCredential.fromForm(
            issuer: "   ",
            name: "alice",
            secretText: "JBSWY3DPEHPK3PXP",
            kind: .hotp(counter: 0, digits: 6),
            requiresTouch: false
        ).get()
    )

    #expect(credential.issuer == nil)
}

@Test func fromFormRejectsABlankNameAndAnUnusableSecret() {
    func error(name: String, secret: String) -> NewCredential.ParsingError? {
        let result = NewCredential.fromForm(
            issuer: nil,
            name: name,
            secretText: secret,
            kind: .totp(period: 30, digits: 6),
            requiresTouch: false
        )
        guard case .failure(let error) = result else { return nil }
        return error
    }

    #expect(error(name: "   ", secret: "JBSWY3DPEHPK3PXP") == .missingName)
    #expect(error(name: "alice", secret: "") == .missingSecret)
    #expect(error(name: "alice", secret: "1") == .invalidSecret)
    #expect(error(name: "alice", secret: "MZXW6===") == .invalidSecret)  // three bytes only
}

// MARK: - Messages

@Test func parsingErrorsCarryAMessageForThePanel() {
    #expect(NewCredential.ParsingError.unsupportedScheme.userMessage == "Lien otpauth:// attendu.")
    #expect(NewCredential.ParsingError.missingSecret.userMessage == "Clé secrète manquante.")
    #expect(
        NewCredential.ParsingError.invalidSecret.userMessage
            == "Clé secrète invalide (base32, 10 octets minimum)."
    )
}
