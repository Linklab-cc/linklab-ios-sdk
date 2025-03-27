import Foundation

/// Errors that can occur in the Linklab SDK
public enum LinkError: Error {
    /// Universal link has invalid format
    case invalidLinkFormat
    
    /// Network response is invalid
    case invalidResponse
    
    /// Response data could not be parsed
    case invalidResponseData
    
    /// Server returned an error
    case serverError(_ statusCode: Int)
    
    /// Network request timed out
    case timeout
    
    /// Network request failed
    case networkError(_ underlyingError: Error)
}

extension LinkError: LocalizedError, Equatable {
    public static func == (lhs: LinkError, rhs: LinkError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidLinkFormat, .invalidLinkFormat):
            return true
        case (.invalidResponse, .invalidResponse):
            return true
        case (.invalidResponseData, .invalidResponseData):
            return true
        case (.timeout, .timeout):
            return true
        case (.serverError(let lhsCode), .serverError(let rhsCode)):
            return lhsCode == rhsCode
        case (.networkError(let lhsError), .networkError(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
    public var errorDescription: String? {
        switch self {
        case .invalidLinkFormat:
            return "Universal link has invalid format"
        case .invalidResponse:
            return "Invalid network response"
        case .invalidResponseData:
            return "Invalid response data"
        case .serverError(let statusCode):
            return "Server error with status code: \(statusCode)"
        case .timeout:
            return "Network request timed out"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
