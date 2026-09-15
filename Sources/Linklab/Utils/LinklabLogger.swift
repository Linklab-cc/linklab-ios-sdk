import Foundation
import os

/// Internal logger. Emits through `os.Logger` only when `LinklabConfiguration.debugLoggingEnabled` is set.
/// Never logs query strings; use `describe(_:)` for URLs.
enum LinklabLogger {
    private static let lock = NSLock()
    private static var enabled = false
    private static let logger = os.Logger(subsystem: "cc.linklab.sdk", category: "Linklab")

    static var isEnabled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return enabled }
        set { lock.lock(); enabled = newValue; lock.unlock() }
    }

    static func debug(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let text = message()
        logger.debug("\(text, privacy: .public)")
    }

    static func info(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let text = message()
        logger.info("\(text, privacy: .public)")
    }

    static func error(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let text = message()
        logger.error("\(text, privacy: .public)")
    }

    /// `scheme://host/path` without query or fragment.
    static func describe(_ url: URL) -> String {
        let scheme = url.scheme ?? ""
        let host = url.host ?? ""
        return "\(scheme)://\(host)\(url.path)"
    }
}
