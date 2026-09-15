import Foundation

/// Time arithmetic for TOTP validity windows. Pure so it can be tested at the
/// boundaries, where display bugs actually live.
public enum CodeClock {

    /// Seconds left before `end`, never negative.
    public static func remaining(until end: Date, now: Date) -> TimeInterval {
        max(0, end.timeIntervalSince(now))
    }

    public static func isExpired(_ code: OATHCode, now: Date) -> Bool {
        remaining(until: code.validTo, now: now) <= 0
    }

    /// The window a TOTP code computed right now would fall in: the key has no clock of
    /// its own and is handed the Mac's date, so the windows line up with the epoch.
    ///
    /// This is what lets a masked row still show how long the *next* code has to live,
    /// which is what you look at before deciding to confirm.
    public static func window(period: TimeInterval, now: Date) -> (validFrom: Date, validTo: Date) {
        guard period > 0 else { return (now, now) }
        let seconds = now.timeIntervalSince1970
        let start = Date(timeIntervalSince1970: seconds - seconds.truncatingRemainder(dividingBy: period))
        return (start, start.addingTimeInterval(period))
    }

    /// Fraction of the window already elapsed, clamped to `0...1`.
    public static func progress(from start: Date, to end: Date, now: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 1 }
        let elapsed = now.timeIntervalSince(start) / total
        return min(max(elapsed, 0), 1)
    }

    /// Compact countdown shown next to a code.
    public static func label(remaining seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.up))
        if whole >= 60 {
            let minutes = whole / 60
            let rest = whole % 60
            return rest == 0 ? "\(minutes) min" : "\(minutes)m\(String(format: "%02d", rest))"
        }
        return "\(whole)s"
    }
}
