import Foundation

public enum Logger {
    /// Whether debug logging is enabled
    public static var isDebugEnabled = false
    
    /// Log debug message
    /// - Parameter message: Debug message
    public static func debug(_ message: String) {
        if isDebugEnabled {
            log(level: "DEBUG", message: message)
        }
    }
    
    /// Log information message
    /// - Parameter message: Info message
    public static func info(_ message: String) {
        log(level: "INFO", message: message)
    }
    
    /// Log error message
    /// - Parameter message: Error message
    public static func error(_ message: String) {
        log(level: "ERROR", message: message)
    }
    
    private static func log(level: String, message: String) {
        NSLog("[Linklab] \(level): \(message)")
    }
}
