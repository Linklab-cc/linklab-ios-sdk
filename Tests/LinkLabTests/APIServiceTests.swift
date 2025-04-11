import XCTest
@testable import Linklab

final class APIServiceTests: XCTestCase {
    var apiService: APIService!
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
        
        // Create the API service with the mock session
        apiService = APIService(urlSession: urlSession)
    }
    
    override func tearDown() {
        apiService = nil
        urlSession = nil
        MockURLProtocol.mockResponses = [:]
        super.tearDown()
    }
    
    func testFetchLinkDetails() {
        // Setup mock response data
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
        
        do {
            let mockResponseData = try JSONSerialization.data(withJSONObject: jsonDict)
            
            // Configure the mock to respond to the link details endpoint
            let linkId = "abc123"
            let domain = "linklab.cc"
            let expectedURL = URL(string: "https://linklab.cc/links/\(linkId)?domain=\(domain)")!
            
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
            let expectation = XCTestExpectation(description: "Fetch link details")
            
            // Call the method under test
            var resultLinkData: LinkData?
            var resultError: Error?
            
            apiService.fetchLinkDetails(linkId: linkId, domain: domain) { result in
                switch result {
                case .success(let linkData):
                    resultLinkData = linkData
                case .failure(let error):
                    resultError = error
                }
                expectation.fulfill()
            }
            
            // Wait for the expectation to be fulfilled
            wait(for: [expectation], timeout: 1.0)
            
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
            XCTAssertEqual(linkData.userId, "user123")
            XCTAssertNil(linkData.packageName)
            XCTAssertEqual(linkData.bundleId, "com.example.app")
            XCTAssertEqual(linkData.appStoreId, "987654321")
            XCTAssertEqual(linkData.domainType, "rootDomain")
            XCTAssertEqual(linkData.domain, "linklab.cc")
            
            // Verify the request was made correctly
            XCTAssertTrue(MockURLProtocol.requestMade(to: expectedURL))
        } catch {
            XCTFail("Failed to create mock data: \(error)")
        }
    }
    
    func testFetchLinkDetailsWithError() {
        // Test with an error response
        let linkId = "abc123"
        let domain = "linklab.cc"
        let expectedURL = URL(string: "https://linklab.cc/links/\(linkId)?domain=\(domain)")!
        
        // Create an error for testing
        let mockError = NSError(domain: "TestDomain", code: 404, userInfo: [NSLocalizedDescriptionKey: "Not found"])
        
        MockURLProtocol.mockResponses[expectedURL] = (
            data: Data(),
            response: HTTPURLResponse(
                url: expectedURL,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!,
            error: mockError
        )
        
        // Create an expectation for the async call
        let expectation = XCTestExpectation(description: "Fetch link details with error")
        
        // Call the method under test
        var resultLinkData: LinkData?
        var resultError: Error?
        
        apiService.fetchLinkDetails(linkId: linkId, domain: domain) { result in
            switch result {
            case .success(let linkData):
                resultLinkData = linkData
            case .failure(let error):
                resultError = error
            }
            expectation.fulfill()
        }
        
        // Wait for the expectation to be fulfilled
        wait(for: [expectation], timeout: 1.0)
        
        // Verify results
        XCTAssertNotNil(resultError, "Should have an error")
        XCTAssertNil(resultLinkData, "Should not have link data")
        
        // Verify the request was made correctly
        XCTAssertTrue(MockURLProtocol.requestMade(to: expectedURL))
    }
    
    func testFetchLinkDetailsWithEmptyLinkId() {
        // Test with empty linkId
        let expectation = XCTestExpectation(description: "Fetch link details with empty linkId")
        
        var resultLinkData: LinkData?
        var resultError: Error?
        
        apiService.fetchLinkDetails(linkId: "", domain: "linklab.cc") { result in
            switch result {
            case .success(let linkData):
                resultLinkData = linkData
            case .failure(let error):
                resultError = error
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        // Should have error with empty linkId
        XCTAssertNotNil(resultError, "Should have an error with empty linkId")
        XCTAssertNil(resultLinkData, "Should not have link data")
        
        // Check for the specific error type
        if let linkError = resultError as? LinkError, case .invalidParameters(let message) = linkError {
            XCTAssertTrue(message.contains("Link ID cannot be empty"), "Error message should mention empty link ID")
        } else {
            XCTFail("Expected LinkError.invalidParameters error")
        }
    }
}