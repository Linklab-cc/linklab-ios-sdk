import Foundation

public struct Configuration {
    /// URL of the attribution service
    public let attributionServiceURL: URL
    
    /// Timeout interval for network requests (in seconds)
    public let networkTimeout: TimeInterval
    
    /// Number of retry attempts for network requests
    public let networkRetryCount: Int
    
    /// Enable debug logging
    public let debugLoggingEnabled: Bool
    
    public init(
        attributionServiceURL: URL,
        networkTimeout: TimeInterval = 30.0,
        networkRetryCount: Int = 3,
        debugLoggingEnabled: Bool = false
    ) {
        self.attributionServiceURL = attributionServiceURL
        self.networkTimeout = networkTimeout
        self.networkRetryCount = networkRetryCount
        self.debugLoggingEnabled = debugLoggingEnabled
        
        Logger.isDebugEnabled = debugLoggingEnabled
    }
}
