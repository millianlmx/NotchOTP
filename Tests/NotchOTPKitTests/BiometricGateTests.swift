import LocalAuthentication
import Testing

@testable import NotchOTPKit

@MainActor
@Test func aFreshMatchIsNeverReused() {
    // Reuse would let an evaluation succeed with no finger at all, which silently defeats
    // "one fingerprint per code".
    let gate = BiometricGate()
    gate.prepareForConfirmation()
    #expect(gate.context?.touchIDAuthenticationAllowableReuseDuration == 0)
}

@MainActor
@Test func eachConfirmationGetsItsOwnContext() throws {
    // Reuse is a property of the context, and it is the whole reason a fingerprint used to
    // open every code after it: measured on macOS 26, a context that has already matched
    // answers the next evaluation in ten milliseconds, with no new touch. So each
    // confirmation arms a context that has never authenticated anything, and retires the
    // one before it.
    let gate = BiometricGate()
    #expect(gate.context == nil, "no context is armed before a confirmation asks for one")

    gate.prepareForConfirmation()
    let first = try #require(gate.context)
    #expect(first.localizedCancelTitle == "Annuler")

    gate.prepareForConfirmation()
    let second = try #require(gate.context)

    #expect(first !== second)
    var error: NSError?
    #expect(
        !first.canEvaluatePolicy(BiometricGate.policy, error: &error),
        "a retired context must not be able to answer for the next code"
    )
}

@MainActor
@Test func confirmingWithoutAPreparedContextIsRefused() async {
    // Not a state the app reaches — the panel arms a context before it shows the sheet —
    // but an evaluation with nothing armed must fail rather than answer from a leftover.
    let gate = BiometricGate()
    #expect(await gate.authenticate(reason: "test") == .unavailable("Aucune confirmation en cours."))
}
