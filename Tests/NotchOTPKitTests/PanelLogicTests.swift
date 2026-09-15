import Foundation
import Testing

@testable import NotchOTPKit

private let accounts = [
    account(issuer: "GitHub", name: "me"),
    account(issuer: "Proton", name: "me", period: 60),
    account(issuer: "AWS", name: "root"),
]

@Test func arrowKeysMoveThroughTheListAndStopAtTheEnds() {
    #expect(PanelLogic.movedSelection(in: accounts, from: nil, by: 1) == accounts[0].id)
    #expect(PanelLogic.movedSelection(in: accounts, from: accounts[0].id, by: 1) == accounts[1].id)
    #expect(PanelLogic.movedSelection(in: accounts, from: accounts[2].id, by: 1) == accounts[2].id)
    #expect(PanelLogic.movedSelection(in: accounts, from: accounts[0].id, by: -1) == accounts[0].id)
    #expect(PanelLogic.movedSelection(in: accounts, from: accounts[1].id, by: -1) == accounts[0].id)
    #expect(PanelLogic.movedSelection(in: [], from: nil, by: 1) == nil)
}

@Test func escapeClosesTheMostSpecificThingFirst() {
    // The confirmation sheet sits above everything else the panel can show.
    #expect(
        PanelLogic.escapeAction(
            isConfirming: true,
            isSearching: true,
            isAddingAccount: true,
            isRenaming: false,
            isDeleting: false
        ) == .closeForm
    )
    #expect(
        PanelLogic.escapeAction(
            isConfirming: false,
            isSearching: true,
            isAddingAccount: true,
            isRenaming: false,
            isDeleting: false
        ) == .clearSearch
    )
    #expect(
        PanelLogic.escapeAction(
            isConfirming: false,
            isSearching: false,
            isAddingAccount: false,
            isRenaming: true,
            isDeleting: false
        ) == .closeForm
    )
    #expect(
        PanelLogic.escapeAction(
            isConfirming: false,
            isSearching: false,
            isAddingAccount: false,
            isRenaming: false,
            isDeleting: true
        ) == .closeForm
    )
    #expect(
        PanelLogic.escapeAction(
            isConfirming: false,
            isSearching: false,
            isAddingAccount: false,
            isRenaming: false,
            isDeleting: false
        ) == .collapse
    )
}
