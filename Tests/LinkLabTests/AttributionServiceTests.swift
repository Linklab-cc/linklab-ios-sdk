import XCTest
@testable import Linklab

final class AttributionServiceTests: XCTestCase {
    
    var attributionService: AttributionService!
    var mockURLProtocol: MockURLProtocol!
    var urlSession: URLSession!
    
    override func setUp() {
        super.setUp()
        
        // Register the mock URL protocol
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        urlSession = URLSession(configuration: config)
        
        // Reset the mock data for each test
        MockURLProtocol.mockResponses = [:]
        
        // Create the attribution service with the mock session
        attributionService = AttributionService(urlSession: urlSession)
    }
    
    override func tearDown() {
        attributionService = nil
        urlSession = nil
        MockURLProtocol.mockResponses = [:]
        super.tearDown()
    }
    
    func testFetchDeferredDeepLink() async throws {
        // Create a date formatter for converting strings to dates
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // Setup mock response data - using date objects now
        let createdDate = dateFormatter.date(from: "2025-03-24T12:00:00Z")
        let updatedDate = dateFormatter.date(from: "2025-03-24T12:00:00Z")
        
        // Create JSON data for response
        let jsonDict: [String: Any] = [
            "id": "abc123",
            "fullLink": "https://example.com/product?id=123&campaign=test",
            "createdAt": "2025-03-24T12:00:00Z",
            "updatedAt": "2025-03-24T12:00:00Z",
            "userId": "user123",
            "packageName": NSNull(),
            "bundleId": "com.example.app",
            "appStoreId": "987654321",
            "domainType": "rootDomain",
            "domain": "linklab.cc"
        ]
        
        let mockResponseData = try JSONSerialization.data(withJSONObject: jsonDict)
        
        // Configure the mock to respond to the attribution endpoint
        let expectedURL = URL(string: "https://linklab.cc/apple-attribution")!
        
        // Add Content-Type header to mock response
        let headers = ["Content-Type": "application/json"]
        
        MockURLProtocol.mockResponses[expectedURL] = (
            data: mockResponseData,
            response: HTTPURLResponse(
                url: expectedURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: headers
            )!,
            error: nil
        )
        
        // Create an expectation for the async call
        let expectation = XCTestExpectation(description: "Fetch deferred deep link")
        
        // Call the method under test
        var resultLinkData: LinkData?
        var resultError: Error?
        
        do {
            try await attributionService.fetchDeferredDeepLink(token: "test-token") { result in
                switch result {
                case .success(let linkData):
                    resultLinkData = linkData
                case .failure(let error):
                    resultError = error
                }
                expectation.fulfill()
            }
        } catch {
            resultError = error
            expectation.fulfill()
        }
        
        // Wait for the expectation to be fulfilled
        await fulfillment(of: [expectation], timeout: 1.0)
        
        // Verify results
        XCTAssertNil(resultError, "Should not have an error")
        XCTAssertNotNil(resultLinkData, "Should have link data")
        
        // Verify link data fields
        guard let linkData = resultLinkData else {
            XCTFail("LinkData should not be nil")
            return
        }
        
        XCTAssertEqual(linkData.id, "abc123")
        XCTAssertEqual(linkData.fullLink, "https://example.com/product?id=123&campaign=test")
        XCTAssertEqual(linkData.createdAt?.timeIntervalSince1970, createdDate?.timeIntervalSince1970)
        XCTAssertEqual(linkData.updatedAt?.timeIntervalSince1970, updatedDate?.timeIntervalSince1970)
        XCTAssertEqual(linkData.userId, "user123")
        XCTAssertNil(linkData.packageName)
        XCTAssertEqual(linkData.bundleId, "com.example.app")
        XCTAssertEqual(linkData.appStoreId, "987654321")
        XCTAssertEqual(linkData.domainType, "rootDomain")
        XCTAssertEqual(linkData.domain, "linklab.cc")
        
        // Verify the request was made correctly
        XCTAssertTrue(MockURLProtocol.requestMade(to: expectedURL))
    }
}

// Mock URLProtocol for testing network requests
class MockURLProtocol: URLProtocol {
    
    // Mock response storage
    static var mockResponses: [URL: (data: Data, response: HTTPURLResponse, error: Error?)] = [:]
    
    // Request tracking
    private static var requests: [URL: [URLRequest]] = [:]
    
    // MARK: - URLProtocol methods
    
    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        
        // Track this request
        Self.track(request: request, for: url)
        
        // Check if we have a mock response for this URL
        if let mockData = Self.mockResponses[url] {
            // Return the mock data
            client?.urlProtocol(self, didReceive: mockData.response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: mockData.data)
            
            if let error = mockData.error {
                client?.urlProtocol(self, didFailWithError: error)
            }
        } else {
            // No mock data found for this URL
            let error = NSError(domain: "MockURLProtocol", code: 404, userInfo: [NSLocalizedDescriptionKey: "URL not mocked: \(url)"])
            client?.urlProtocol(self, didFailWithError: error)
        }
        
        client?.urlProtocolDidFinishLoading(self)
    }
    
    override func stopLoading() {
        // No-op
    }
    
    // MARK: - Request tracking methods
    
    static func track(request: URLRequest, for url: URL) {
        var requestsForURL = requests[url] ?? []
        requestsForURL.append(request)
        requests[url] = requestsForURL
    }
    
    static func requestMade(to url: URL) -> Bool {
        return (requests[url]?.isEmpty ?? true) == false
    }
    
    static func lastRequest(for url: URL) -> URLRequest? {
        return requests[url]?.last
    }
    
    static func clearRequests() {
        requests.removeAll()
    }
}
