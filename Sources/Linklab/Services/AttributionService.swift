import Foundation

/// Model representing the Link response from the API
struct LinkData: Codable {
    let id: String
    let fullLink: String
    let createdAt: String
    let updatedAt: String
    let userId: String
    let packageName: String?
    let bundleId: String?
    let appStoreId: String?
    let domainType: String
    let domain: String
}

@available(iOS 14.0, macOS 12.0, *)
class AttributionService {
    private let baseURL: URL
    private let urlSession: URLSession
    
    init(baseURL: URL, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.urlSession = urlSession
    }
    
    /// Fetches deferred deep link information from the attribution service
    /// - Parameters:
    ///   - token: Attribution token from StoreKit
    ///   - completion: Completion handler with result
    /// - Returns: Void
    func fetchDeferredDeepLink(
        token: String,
        completion: @escaping (Result<[String: String], Error>) -> Void
    ) async throws {
        // Build the URL with path for Apple attribution endpoint
        let url = baseURL.appendingPathComponent("apple-attribution")
        
        // Create URL request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Create request body according to API spec
        let body: [String: Any] = [
            "attributionToken": token
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        do {
            // Make the request
            let (data, response) = try await urlSession.data(for: request)
            
            // Check response status code
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LinkError.invalidResponse
            }
            
            guard 200..<300 ~= httpResponse.statusCode else {
                throw LinkError.serverError(httpResponse.statusCode)
            }
            
            // Parse the response according to Link schema from API spec
            guard let linkData = try? JSONDecoder().decode(LinkData.self, from: data) else {
                throw LinkError.invalidResponseData
            }
            
            // Convert Link data to parameters
            let params = self.convertLinkDataToParams(linkData)
            
            // Return the deep link parameters
            completion(.success(params))
        } catch {
            completion(.failure(error))
            throw error
        }
    }
    
    /// Converts LinkData to a dictionary of parameters for deep linking
    /// - Parameter linkData: The Link data from the API
    /// - Returns: Dictionary of parameters for deep linking
    private func convertLinkDataToParams(_ linkData: LinkData) -> [String: String] {
        var params: [String: String] = [:]
        
        // Add all required fields from link data
        params["id"] = linkData.id
        params["fullLink"] = linkData.fullLink
        params["domainType"] = linkData.domainType
        params["domain"] = linkData.domain
        
        // Add optional fields if present
        if let packageName = linkData.packageName {
            params["packageName"] = packageName
        }
        
        if let bundleId = linkData.bundleId {
            params["bundleId"] = bundleId
        }
        
        if let appStoreId = linkData.appStoreId {
            params["appStoreId"] = appStoreId
        }
        
        // Extract any additional parameters from the fullLink
        if let components = URLComponents(string: linkData.fullLink),
           let queryItems = components.queryItems {
            for item in queryItems {
                if let value = item.value {
                    params[item.name] = value
                }
            }
        }
        
        return params
    }
}
