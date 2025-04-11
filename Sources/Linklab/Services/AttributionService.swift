import Foundation

@available(iOS 14.0, macOS 12.0, *)
class AttributionService {
    private let baseURL: URL
    private let urlSession: URLSession
    
    init(urlSession: URLSession = .shared) {
        self.baseURL = URL(string: "https://linklab.cc")!
        self.urlSession = urlSession
    }
    
    /// Fetches deferred deep link information from the attribution service
    /// - Parameters:
    ///   - token: Attribution token from StoreKit
    ///   - completion: Completion handler with result containing LinkData
    /// - Returns: Void
    func fetchDeferredDeepLink(
        token: String,
        completion: @escaping (Result<LinkData, Error>) -> Void
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
            Logger.debug("Fetching deferred deep link with token...")
            // Make the request
            let (data, response) = try await urlSession.data(for: request)
            
            // Check response status code
            guard let httpResponse = response as? HTTPURLResponse else {
                Logger.error("Invalid response type received from attribution endpoint.")
                throw LinkError.invalidResponse
            }
            
            guard 200..<300 ~= httpResponse.statusCode else {
                var errorMessage = "Attribution endpoint returned error: Status code \(httpResponse.statusCode)"
                if let body = String(data: data, encoding: .utf8) {
                     errorMessage += " Body: \(body)"
                }
                Logger.error(errorMessage)
                throw LinkError.apiError(statusCode: httpResponse.statusCode, message: "Attribution endpoint error.")
            }
            
            // Parse the response using the main LinkData model
            let decoder = JSONDecoder()
            // Use the custom decoder with the specific date format from LinkData
             guard let linkData = try? decoder.decode(LinkData.self, from: data) else {
                Logger.error("Failed to decode LinkData from attribution endpoint.")
                if let jsonString = String(data: data, encoding: .utf8) {
                    Logger.error("Raw JSON response from attribution: \(jsonString)")
                }
                 throw LinkError.decodingError(NSError(domain: "LinklabSDK", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to decode LinkData from attribution endpoint."])) // Provide a specific error
             }
            
            // Return the decoded LinkData object directly
            Logger.debug("Successfully fetched and decoded deferred LinkData.")
            completion(.success(linkData))
        } catch {
            Logger.error("Error during fetchDeferredDeepLink: \(error.localizedDescription)")
            completion(.failure(error))
            throw error // Re-throw to signal failure to the caller if needed
        }
    }
}
