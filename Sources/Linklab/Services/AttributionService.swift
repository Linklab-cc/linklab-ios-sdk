import Foundation
import UIKit

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
    ///   - completion: Completion handler with result containing LinkData
    /// - Returns: Void
    func fetchDeferredDeepLink(
        completion: @escaping (Result<LinkData, Error>) -> Void
    ) async throws {
        // 1. Try to get link info from clipboard
        if let clipboardString = UIPasteboard.general.string,
           let (linkId, domainType, domain) = AttributionService.parseClipboardLink(clipboardString) {
            Logger.debug("Found Linklab link in clipboard: linkId=\(linkId), domainType=\(domainType), domain=\(domain)")
            let apiService = APIService(urlSession: urlSession)
            apiService.fetchLinkDetails(linkId: linkId, domain: domain) { result in
                completion(result)
            }
            return
        } else {
            Logger.debug("No valid Linklab link found in clipboard.")
        }
        // 2. Fallback: Call /apple-attribution endpoint (can be removed in future)
        do {
            let url = baseURL.appendingPathComponent("apple-attribution")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [:]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            Logger.debug("Fetching deferred deep link based on IP address...")
            let (data, response) = try await urlSession.data(for: request)
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
            let decoder = JSONDecoder()
            guard let linkData = try? decoder.decode(LinkData.self, from: data) else {
                Logger.error("Failed to decode LinkData from attribution endpoint.")
                if let jsonString = String(data: data, encoding: .utf8) {
                    Logger.error("Raw JSON response from attribution: \(jsonString)")
                }
                throw LinkError.decodingError(NSError(domain: "LinklabSDK", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to decode LinkData from attribution endpoint."]))
            }
            Logger.debug("Successfully fetched and decoded deferred LinkData.")
            completion(.success(linkData))
        } catch {
            Logger.error("Error during fetchDeferredDeepLink: \(error.localizedDescription)")
            completion(.failure(error))
            throw error
        }
    }
    
    /// Parses a clipboard string for a Linklab link in the format 'linklab_<linkId>_<domainType>_<domain>'
    /// - Returns: (linkId, domainType, domain) if found, else nil
    static func parseClipboardLink(_ string: String) -> (String, String, String)? {
        let pattern = "^linklab_([^_]+)_([^_]+)_(.+)$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(location: 0, length: string.utf16.count)
        if let match = regex.firstMatch(in: string, options: [], range: range), match.numberOfRanges == 4 {
            let linkId = (string as NSString).substring(with: match.range(at: 1))
            let domainType = (string as NSString).substring(with: match.range(at: 2))
            let domain = (string as NSString).substring(with: match.range(at: 3))
            return (linkId, domainType, domain)
        }
        return nil
    }
}
