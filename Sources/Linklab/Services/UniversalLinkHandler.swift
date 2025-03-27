import Foundation

class UniversalLinkHandler {
    /// Parse a Universal Link into deep link parameters
    /// - Parameter url: The Universal Link URL
    /// - Returns: Dictionary of parameters
    /// - Throws: LinkError if URL cannot be parsed
    func parseUniversalLink(_ url: URL) throws -> [String: String] {
        // Extract path components
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        
        // Extract query parameters
        var parameters: [String: String] = [:]
        if let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: true)?.queryItems {
            for item in queryItems {
                if let value = item.value {
                    parameters[item.name] = value
                }
            }
        }
        
        // Add the path as a parameter
        if !pathComponents.isEmpty {
            parameters["route"] = pathComponents.joined(separator: "/")
        }
        
        // Check if we parsed any useful data
        if parameters.isEmpty && pathComponents.isEmpty {
            throw LinkError.invalidLinkFormat
        }
        
        return parameters
    }
}
