import Foundation

/// How the SDK is allowed to read the system pasteboard for deferred deep linking.
public enum PasteboardMode: Sendable {
    /// Read at most once per install, during the first-launch deferred check (may show the iOS paste banner once).
    case automatic
    /// Never read automatically; the app calls `Linklab.shared.checkPasteboard()` after a user action.
    case manual
    /// Never read the pasteboard.
    case disabled
}

/// Configuration for the Linklab SDK.
public struct LinklabConfiguration: Sendable {
    /// Per-request timeout in seconds.
    public var networkTimeout: TimeInterval
    /// Number of retries (after the first attempt) for network errors and 5xx responses.
    public var networkRetryCount: Int
    /// Enables SDK logging through `os.Logger` (subsystem `cc.linklab.sdk`). Query strings are never logged.
    public var debugLoggingEnabled: Bool
    /// Custom domains registered with Linklab (e.g. `"go.example.com"`). Compared case-insensitively.
    public var customDomains: [String]
    /// Backend base URL.
    public var baseURL: URL
    /// Pasteboard policy for deferred deep linking.
    public var pasteboardMode: PasteboardMode

    public init(
        networkTimeout: TimeInterval = 10,
        networkRetryCount: Int = 3,
        debugLoggingEnabled: Bool = false,
        customDomains: [String] = [],
        baseURL: URL = URL(string: "https://linklab.cc")!,
        pasteboardMode: PasteboardMode = .automatic
    ) {
        self.networkTimeout = networkTimeout
        self.networkRetryCount = max(0, networkRetryCount)
        self.debugLoggingEnabled = debugLoggingEnabled
        self.customDomains = customDomains.map { $0.lowercased() }
        self.baseURL = baseURL
        self.pasteboardMode = pasteboardMode
    }
}

/// Backwards-compatible name for `LinklabConfiguration`.
public typealias Configuration = LinklabConfiguration
