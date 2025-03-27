import XCTest
@testable import Linklab

final class DeepLinkProcessorTests: XCTestCase {
    private var deepLinkProcessor: DeepLinkProcessor!
    
    override func setUp() {
        super.setUp()
        deepLinkProcessor = DeepLinkProcessor()
    }
    
    override func tearDown() {
        deepLinkProcessor = nil
        super.tearDown()
    }
    
    func testProcessDeepLink() {
        // Test with route and parameters
        let params: [String: String] = [
            "route": "products/123",
            "utm_source": "email",
            "utm_campaign": "summer"
        ]
        
        let destination = deepLinkProcessor.processDeepLink(params: params)
        
        XCTAssertEqual(destination.route, "products/123")
        XCTAssertEqual(destination.parameters.count, 2)
        XCTAssertEqual(destination.parameters["utm_source"], "email")
        XCTAssertEqual(destination.parameters["utm_campaign"], "summer")
    }
    
    func testProcessDeepLinkWithoutRoute() {
        // Test without route
        let params: [String: String] = [
            "utm_source": "email",
            "utm_campaign": "summer"
        ]
        
        let destination = deepLinkProcessor.processDeepLink(params: params)
        
        XCTAssertEqual(destination.route, "")
        XCTAssertEqual(destination.parameters.count, 2)
        XCTAssertEqual(destination.parameters["utm_source"], "email")
        XCTAssertEqual(destination.parameters["utm_campaign"], "summer")
    }
    
    func testProcessDeepLinkWithoutParameters() {
        // Test with only route
        let params: [String: String] = ["route": "products/123"]
        
        let destination = deepLinkProcessor.processDeepLink(params: params)
        
        XCTAssertEqual(destination.route, "products/123")
        XCTAssertEqual(destination.parameters.count, 0)
    }
}
