import Foundation

public struct Configuration {
    /// Timeout interval for network requests (in seconds)
    public let networkTimeout: TimeInterval
    
    /// Number of retry attempts for network requests
    public let networkRetryCount: Int
    
    /// Enable debug logging
    public let debugLoggingEnabled: Bool
    
    /// Optional list of custom domains registered with LinkLab.
    public let customDomains: [String]

    public init(
        networkTimeout: TimeInterval = 30.0,
        networkRetryCount: Int = 3,
        debugLoggingEnabled: Bool = false,
        customDomains: [String] = []
    ) {
        self.networkTimeout = networkTimeout
        self.networkRetryCount = networkRetryCount
        self.debugLoggingEnabled = debugLoggingEnabled
        self.customDomains = customDomains
        
        Logger.isDebugEnabled = debugLoggingEnabled
    }
}
