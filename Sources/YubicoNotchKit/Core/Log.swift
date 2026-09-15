import OSLog

/// Unified-log channels. Read with:
/// `log show --last 5m --predicate 'subsystem == "app.yubiconotch"' --info`
enum Log {
    private static let subsystem = "app.yubiconotch"

    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let panel = Logger(subsystem: subsystem, category: "panel")
    static let key = Logger(subsystem: subsystem, category: "key")
}
