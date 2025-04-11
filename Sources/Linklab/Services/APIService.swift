import Foundation

/// Service responsible for interacting with the LinkLab backend API.
internal class APIService {
    private let baseURL = URL(string: "https://linklab.cc")!
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    /// Fetches the details for a specific LinkLab link.
    /// - Parameters:
    ///   - linkId: The unique identifier of the link.
    ///   - domainType: The type of domain ("rootDomain" or "subDomain").
    ///   - domain: The specific domain associated with the link.
    ///   - completion: A closure called with the result of the API call.
    func fetchLinkDetails(linkId: String,
                          domainType: String?,
                          domain: String?,
                          completion: @escaping (Result<LinkData, Error>) -> Void) {
        
        guard !linkId.isEmpty else {
            completion(.failure(LinkError.invalidParameters("Link ID cannot be empty.")))
            return
        }
        
        var components = URLComponents(url: baseURL.appendingPathComponent("links").appendingPathComponent(linkId), resolvingAgainstBaseURL: false)
        
        var queryItems = [URLQueryItem]()
        if let domainType = domainType, !domainType.isEmpty {
            queryItems.append(URLQueryItem(name: "domain_type", value: domainType))
        }
        if let domain = domain, !domain.isEmpty {
            queryItems.append(URLQueryItem(name: "domain", value: domain))
        }
        
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        
        guard let url = components?.url else {
            completion(.failure(LinkError.internalError("Failed to construct API URL.")))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        Logger.debug("Requesting LinkLab link details from: \(url.absoluteString)")

        let task = urlSession.dataTask(with: request) { data, response, error in
            if let error = error {
                Logger.error("API request failed: \(error.localizedDescription)")
                completion(.failure(LinkError.networkError(error)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                Logger.error("Invalid API response received.")
                completion(.failure(LinkError.apiError(statusCode: 0, message: "Invalid response type.")))
                return
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                var errorMessage = "API error: Status code \(httpResponse.statusCode)"
                if let data = data, let body = String(data: data, encoding: .utf8) {
                     errorMessage += " Body: \(body)"
                }
                 Logger.error(errorMessage)
                completion(.failure(LinkError.apiError(statusCode: httpResponse.statusCode, message: "Server returned status code \(httpResponse.statusCode).")))
                return
            }
            
            guard let data = data else {
                Logger.error("API response contained no data.")
                completion(.failure(LinkError.apiError(statusCode: httpResponse.statusCode, message: "Empty response body.")))
                return
            }
            
            do {
                // Use the custom decoder with the specific date format
                let decoder = JSONDecoder()
                let linkData = try decoder.decode(LinkData.self, from: data)
                Logger.debug("Successfully decoded LinkData: \(linkData)")
                completion(.success(linkData))
            } catch let decodingError {
                Logger.error("Failed to decode LinkData: \(decodingError.localizedDescription)")
                 if let jsonString = String(data: data, encoding: .utf8) {
                     Logger.error("Raw JSON response: \(jsonString)")
                 }
                completion(.failure(LinkError.decodingError(decodingError)))
            }
        }
        
        task.resume()
    }
} 