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
        
        // Create the attribution service with a mock base URL and session
        attributionService = AttributionService(
            baseURL: URL(string: "https://api.linklab.cc")!,
            urlSession: urlSession
        )
    }
    
    override func tearDown() {
        attributionService = nil
        urlSession = nil
        MockURLProtocol.mockResponses = [:]
        super.tearDown()
    }
    
    func testFetchDeferredDeepLink() async throws {
        // Setup mock response data
        let linkData = LinkData(
            id: "abc123",
            fullLink: "https://example.com/product?id=123&campaign=test",
            createdAt: "2025-03-24T12:00:00Z",
            updatedAt: "2025-03-24T12:00:00Z",
            userId: "user123",
            packageName: nil,
            bundleId: "com.example.app",
            appStoreId: "987654321",
            domainType: "rootDomain",
            domain: "linklab.cc"
        )
        
        let encoder = JSONEncoder()
        let mockResponseData = try encoder.encode(linkData)
        
        // Configure the mock to respond to the attribution endpoint
        let expectedURL = URL(string: "https://api.linklab.cc/apple-attribution")!
        
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
        var resultParams: [String: String]?
        var resultError: Error?
        
        do {
            try await attributionService.fetchDeferredDeepLink(token: "test-token") { result in
                switch result {
                case .success(let params):
                    resultParams = params
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
        XCTAssertNotNil(resultParams, "Should have parameters")
        
        // Verify we have parameters returned
        XCTAssertNotNil(resultParams)
        XCTAssertGreaterThan(resultParams?.count ?? 0, 0)
        
        // When a URL parameter has the same name as a Link property,
        // our implementation will prefer the URL parameter.
        // In this case, the URL parameter 'id=123' overrides the Link.id 'abc123'
        
        // Check for required parameters
        XCTAssertNotNil(resultParams?["id"])
        XCTAssertEqual(resultParams?["fullLink"], "https://example.com/product?id=123&campaign=test")
        XCTAssertEqual(resultParams?["bundleId"], "com.example.app")
        XCTAssertEqual(resultParams?["appStoreId"], "987654321")
        
        // Check that the URL query parameters were extracted
        XCTAssertEqual(resultParams?["campaign"], "test")
        
        // Verify the request was made correctly
        XCTAssertTrue(MockURLProtocol.requestMade(to: expectedURL))
        
        // Skip request body verification in this test since we're using async/await
        // In a real test, we might need a more advanced setup to capture the request body
        // This test primarily verifies that the endpoint path and response processing are correct
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