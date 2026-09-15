import OSLog

/// Unified-log channels. Read with:
/// `log show --last 5m --predicate 'subsystem == "app.notchotp"' --info`
enum Log {
    private static let subsystem = "app.notchotp"

    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let panel = Logger(subsystem: subsystem, category: "panel")
    static let key = Logger(subsystem: subsystem, category: "key")
}
