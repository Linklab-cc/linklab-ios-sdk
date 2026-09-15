import Foundation

/// Errors reported through `Linklab.onError`.
public enum LinkError: Error {
    /// `initialize(with:)` has not been called.
    case notInitialized
    /// The URL is not on linklab.cc, a subdomain of it, or a configured custom domain.
    case notLinklabLink
    /// The URL could not be used.
    case invalidURL(String)
    /// The request failed before a response was received.
    case networkError(Error)
    /// The request timed out (after retries).
    case timeout
    /// The backend returned a non-2xx status.
    case apiError(statusCode: Int, message: String)
    /// The backend payload could not be decoded.
    case decodingError(Error)
    /// Unexpected SDK state.
    case internalError(String)

    /// Stable machine-readable code (used by the Flutter plugin).
    public var code: String {
        switch self {
        case .notInitialized: return "NOT_INITIALIZED"
        case .notLinklabLink: return "NOT_LINKLAB_LINK"
        case .invalidURL: return "INVALID_URL"
        case .networkError: return "NETWORK"
        case .timeout: return "TIMEOUT"
        case .apiError: return "API"
        case .decodingError: return "DECODING"
        case .internalError: return "INTERNAL"
        }
    }

    /// HTTP status for `.apiError`, otherwise nil.
    public var statusCode: Int? {
        if case .apiError(let status, _) = self { return status }
        return nil
    }

    /// `true` for failures that may succeed on a later attempt (network errors, timeouts, 5xx).
    var isTransient: Bool {
        switch self {
        case .networkError, .timeout: return true
        case .apiError(let status, _): return status >= 500
        default: return false
        }
    }
}

extension LinkError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notInitialized: return "Linklab SDK has not been initialized."
        case .notLinklabLink: return "URL is not a Linklab link."
        case .invalidURL(let reason): return "Invalid URL: \(reason)"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .timeout: return "Network request timed out."
        case .apiError(let status, let message): return "API error (\(status)): \(message)"
        case .decodingError(let error): return "Failed to decode response: \(error.localizedDescription)"
        case .internalError(let message): return "Internal error: \(message)"
        }
    }
}

extension LinkError: Equatable {
    public static func == (lhs: LinkError, rhs: LinkError) -> Bool {
        switch (lhs, rhs) {
        case (.notInitialized, .notInitialized), (.notLinklabLink, .notLinklabLink), (.timeout, .timeout):
            return true
        case (.invalidURL(let l), .invalidURL(let r)), (.internalError(let l), .internalError(let r)):
            return l == r
        case (.networkError(let l), .networkError(let r)), (.decodingError(let l), .decodingError(let r)):
            return l.localizedDescription == r.localizedDescription
        case (.apiError(let ls, let lm), .apiError(let rs, let rm)):
            return ls == rs && lm == rm
        default:
            return false
        }
    }
}
