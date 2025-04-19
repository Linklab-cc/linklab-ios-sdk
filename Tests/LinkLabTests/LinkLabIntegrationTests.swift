import XCTest
@testable import Linklab

/// Simple integration test for Linklab's public API
@available(iOS 14.3, macOS 11.1, *)
@MainActor
final class LinkLabIntegrationTests: XCTestCase {
    private var deepLinkCallbackCalled = false
    private var receivedLinkData: LinkData?
    
    @MainActor
    override func setUp() {
        super.setUp()
        deepLinkCallbackCalled = false
        receivedLinkData = nil
    }
    
    @MainActor
    override func tearDown() {
        super.tearDown()
    }
    
    @MainActor
    func testHandleUniversalLink() async throws {
        // Since we can't easily mock the network requests without extending the class,
        // we'll just test the public API and behavior
        let linklab = Linklab.shared
        
        // Initialize with our callback
        linklab.initialize(with: Configuration(customDomains: ["example.com"]), deepLinkCallback: { [weak self] linkData in
            self?.deepLinkCallbackCalled = true
            self?.receivedLinkData = linkData
        })
        
        // Test URL - note this won't actually make network requests as we're just 
        // testing the URL processing logic
        let testURL = URL(string: "https://example.com/abc123")!
        
        // Call the method under test - should return true even if it can't process due to network
        let handled = linklab.handleIncomingURL(testURL)
        
        // Basic assertions
        XCTAssertTrue(handled, "URL should be marked as handled")
        
        // The callback might not be called immediately (or at all in this test environment),
        // but the URL should be recognized as something the SDK handles.
        // In a real integration, the SDK would attempt to fetch link details from the API.
    }
    
    @MainActor
    func testMalformedURL() async throws {
        let linklab = Linklab.shared
        
        // Initialize with our callback
        linklab.initialize(with: Configuration(customDomains: ["example.com"]), deepLinkCallback: { [weak self] linkData in
            self?.deepLinkCallbackCalled = true
            self?.receivedLinkData = linkData
        })
        
        // Test with a URL missing host
        let malformedURL = URL(string: "example-only")!
        
        // Call the method under test
        let handled = linklab.handleIncomingURL(malformedURL)
        
        // Should not be handled
        XCTAssertFalse(handled, "Malformed URL should not be handled")
        XCTAssertFalse(deepLinkCallbackCalled, "Callback should not be called for malformed URL")
    }
    
    @MainActor
    func testDeprecatedHandleUniversalLink() async throws {
        let linklab = Linklab.shared
        
        // Initialize with our callback
        linklab.initialize(with: Configuration(customDomains: ["example.com"]), deepLinkCallback: { [weak self] linkData in
            self?.deepLinkCallbackCalled = true
            self?.receivedLinkData = linkData
        })
        
        // Test URL
        let testURL = URL(string: "https://example.com/abc123")!
        
        // Call the deprecated method - should call through to handleIncomingURL
        let handled = linklab.handleUniversalLink(testURL)
        
        // Should be handled
        XCTAssertTrue(handled, "URL should be handled by deprecated method")
    }
}