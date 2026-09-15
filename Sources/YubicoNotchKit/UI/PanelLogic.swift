import Foundation

/// The panel's small decision rules, kept pure so they can be tested without a window,
/// a keyboard focus or a running event loop.
enum PanelLogic {

    /// Which credential ↑ and ↓ land on. `nil` starts from the first one.
    static func movedSelection(
        in accounts: [OATHAccount],
        from current: Data?,
        by offset: Int
    ) -> Data? {
        guard !accounts.isEmpty else { return nil }
        let index = accounts.firstIndex { $0.id == current } ?? -1
        let next = min(max(index + offset, 0), accounts.count - 1)
        return accounts[next].id
    }

    /// What Escape does, most specific state first.
    enum EscapeAction: Equatable {
        case clearSearch
        case closeForm
        case collapse
    }

    static func escapeAction(
        isConfirming: Bool,
        isSearching: Bool,
        isAddingAccount: Bool,
        isRenaming: Bool,
        isDeleting: Bool
    ) -> EscapeAction {
        // The confirmation sheet sits above everything else the panel can show.
        if isConfirming { return .closeForm }
        if isSearching { return .clearSearch }
        if isAddingAccount || isRenaming || isDeleting { return .closeForm }
        return .collapse
    }
}
