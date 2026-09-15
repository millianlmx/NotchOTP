import AppKit
import Observation

/// The slice of `NSPasteboard` the clipboard logic needs, so the "don't wipe a
/// newer copy" rule can be tested without touching the user's real clipboard.
@MainActor
public protocol Pasteboard: AnyObject {
    var changeCount: Int { get }
    var string: String? { get }
    func setString(_ value: String)
    func clear()
}

@MainActor
public final class SystemPasteboard: Pasteboard {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public var changeCount: Int { pasteboard.changeCount }
    public var string: String? { pasteboard.string(forType: .string) }

    public func setString(_ value: String) {
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    public func clear() {
        pasteboard.clearContents()
    }
}

/// Copies a code and wipes it again after a delay — but only while our copy is
/// still the one on the pasteboard.
@MainActor
@Observable
public final class Clipboard {

    private let pasteboard: any Pasteboard
    private var pendingClear: Task<Void, Never>?
    private var ownedChangeCount: Int?

    /// Delay before the copy is wiped. `nil` keeps it forever.
    public var clearAfter: TimeInterval?

    public private(set) var lastCopy: (code: String, at: Date)?
    /// When the current copy will be wiped, if auto-clear is armed.
    public private(set) var clearAt: Date?

    public init(pasteboard: any Pasteboard = SystemPasteboard()) {
        self.pasteboard = pasteboard
    }

    /// - Returns: the date at which the copy will be wiped, if any.
    @discardableResult
    public func copy(_ code: String, now: Date = Date()) -> Date? {
        pasteboard.setString(code)
        ownedChangeCount = pasteboard.changeCount
        lastCopy = (code, now)
        pendingClear?.cancel()
        pendingClear = nil

        guard let delay = clearAfter, delay > 0 else {
            clearAt = nil
            return nil
        }
        let deadline = now.addingTimeInterval(delay)
        clearAt = deadline
        pendingClear = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.clearIfStillOurs()
        }
        return deadline
    }

    /// Wipes the pasteboard only if nothing else was copied in the meantime.
    public func clearIfStillOurs() {
        defer {
            pendingClear = nil
            ownedChangeCount = nil
            clearAt = nil
        }
        guard let ownedChangeCount, pasteboard.changeCount == ownedChangeCount else { return }
        pasteboard.clear()
    }

    public func cancelPendingClear() {
        pendingClear?.cancel()
        pendingClear = nil
        ownedChangeCount = nil
        clearAt = nil
    }
}
