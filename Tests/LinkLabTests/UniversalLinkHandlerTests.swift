import XCTest
@testable import LinkLabSDK

final class UniversalLinkHandlerTests: XCTestCase {
    private var universalLinkHandler: UniversalLinkHandler!
    
    override func setUp() {
        super.setUp()
        universalLinkHandler = UniversalLinkHandler()
    }
    
    override func tearDown() {
        universalLinkHandler = nil
        super.tearDown()
    }
    
    func testParseUniversalLink() throws {
        // Test with path and query parameters
        let url = URL(string: "https://example.com/products/123?utm_source=email&utm_campaign=summer")!
        let params = try universalLinkHandler.parseUniversalLink(url)
        
        XCTAssertEqual(params["route"], "products/123")
        XCTAssertEqual(params["utm_source"], "email")
        XCTAssertEqual(params["utm_campaign"], "summer")
    }
    
    func testParseUniversalLinkWithoutPath() throws {
        // Test with only query parameters
        let url = URL(string: "https://example.com?utm_source=email&utm_campaign=summer")!
        let params = try universalLinkHandler.parseUniversalLink(url)
        
        XCTAssertNil(params["route"])
        XCTAssertEqual(params["utm_source"], "email")
        XCTAssertEqual(params["utm_campaign"], "summer")
    }
    
    func testParseUniversalLinkWithoutQueryParams() throws {
        // Test with only path
        let url = URL(string: "https://example.com/products/123")!
        let params = try universalLinkHandler.parseUniversalLink(url)
        
        XCTAssertEqual(params["route"], "products/123")
    }
    
    func testInvalidLinkFormat() {
        // Test with empty URL
        let url = URL(string: "https://example.com")!
        
        XCTAssertThrowsError(try universalLinkHandler.parseUniversalLink(url)) { error in
            XCTAssertEqual(error as? LinkError, .invalidLinkFormat)
        }
    }
}
