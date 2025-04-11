import Foundation

/// Errors that can occur in the Linklab SDK
public enum LinkError: Error {
    /// SDK was not initialized before being used.
    case notInitialized
    
    /// An internal SDK error occurred.
    case internalError(_ message: String)
    
    /// Incoming URL is invalid or malformed.
    case invalidURL(_ reason: String)

    /// Invalid parameters were provided to a function.
    case invalidParameters(_ message: String)
    
    /// Decoding the API response failed.
    case decodingError(_ underlyingError: Error)

    /// Error fetching attribution data.
    case attributionError(_ underlyingError: Error)

    /// Required feature (like AdServices) is not available.
    case featureNotAvailable(_ featureName: String)
    
    /// Universal link has invalid format
    case invalidLinkFormat
    
    /// Network response is invalid
    case invalidResponse
    
    /// Response data could not be parsed
    case invalidResponseData
    
    /// Server returned an error
    case serverError(_ statusCode: Int)
    
    /// API Error (covers non-2xx status codes or invalid responses)
    case apiError(statusCode: Int, message: String)
    
    /// Network request timed out
    case timeout
    
    /// Network request failed
    case networkError(_ underlyingError: Error)
}

extension LinkError: LocalizedError, Equatable {
    public static func == (lhs: LinkError, rhs: LinkError) -> Bool {
        switch (lhs, rhs) {
        case (.notInitialized, .notInitialized):
            return true
        case (.internalError(let lhsMsg), .internalError(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.invalidURL(let lhsReason), .invalidURL(let rhsReason)):
            return lhsReason == rhsReason
        case (.invalidParameters(let lhsMsg), .invalidParameters(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.decodingError(let lhsErr), .decodingError(let rhsErr)):
            return lhsErr.localizedDescription == rhsErr.localizedDescription
        case (.attributionError(let lhsErr), .attributionError(let rhsErr)):
            return lhsErr.localizedDescription == rhsErr.localizedDescription
        case (.featureNotAvailable(let lhsFeat), .featureNotAvailable(let rhsFeat)):
            return lhsFeat == rhsFeat
        case (.invalidLinkFormat, .invalidLinkFormat):
            return true
        case (.invalidResponse, .invalidResponse):
            return true
        case (.invalidResponseData, .invalidResponseData):
            return true
        case (.serverError(let lhsCode), .serverError(let rhsCode)):
            return lhsCode == rhsCode
        case (.apiError(let lhsCode, let lhsMsg), .apiError(let rhsCode, let rhsMsg)):
            return lhsCode == rhsCode && lhsMsg == rhsMsg
        case (.timeout, .timeout):
            return true
        case (.networkError(let lhsError), .networkError(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Linklab SDK has not been initialized."
        case .internalError(let message):
            return "Internal SDK error: \(message)"
        case .invalidURL(let reason):
            return "Invalid URL provided: \(reason)"
        case .invalidParameters(let message):
            return "Invalid parameters: \(message)"
        case .decodingError(let error):
            return "Failed to decode API response: \(error.localizedDescription)"
        case .attributionError(let error):
            return "Failed to get attribution data: \(error.localizedDescription)"
        case .featureNotAvailable(let featureName):
            return "Required feature '\(featureName)' is not available on this device/OS."
        case .invalidLinkFormat:
            return "Universal link has invalid format"
        case .invalidResponse:
            return "Invalid network response"
        case .invalidResponseData:
            return "Invalid response data"
        case .serverError(let statusCode):
            return "Server error with status code: \(statusCode)"
        case .apiError(let statusCode, let message):
            return "API Error (Status code: \(statusCode)): \(message)"
        case .timeout:
            return "Network request timed out"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
