import XCTest
@testable import Linklab

/// Simple integration test for Linklab's public API
@available(iOS 14.3, macOS 12.0, *)
@MainActor
final class LinkLabIntegrationTests: XCTestCase {
    private var deepLinkCallbackCalled = false
    private var receivedLinkData: LinkData?
    private var sdk: Linklab!
    private var session: URLSession!
    private var callbackExpectation: XCTestExpectation!
    
    @MainActor
    override func setUp() {
        super.setUp()
        deepLinkCallbackCalled = false
        receivedLinkData = nil
        UserDefaults.standard.set(false, forKey: "linklab_first_launch_key")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        sdk = Linklab(
            apiService: APIService(urlSession: session),
            attributionService: AttributionService(urlSession: session, clipboardReader: { nil }),
            installationTracker: InstallationTracker()
        )
        callbackExpectation = expectation(description: "Link callback received")
    }
    
    @MainActor
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "linklab_first_launch_key")
        session.invalidateAndCancel()
        sdk = nil
        session = nil
        super.tearDown()
    }
    
    @MainActor
    func testHandleUniversalLink() async throws {
        // Since we can't easily mock the network requests without extending the class,
        // we'll just test the public API and behavior
        let linklab = sdk!
        
        // Initialize with our callback
        linklab.initialize(with: Configuration(customDomains: ["example.com"]), deepLinkCallback: { [weak self] linkData in
            self?.deepLinkCallbackCalled = true
            self?.receivedLinkData = linkData
            self?.callbackExpectation.fulfill()
        })
        
        // Test URL - note this won't actually make network requests as we're just 
        // testing the URL processing logic
        let testURL = URL(string: "https://example.com/abc123")!
        
        // Call the method under test - should return true even if it can't process due to network
        let handled = linklab.handleIncomingURL(testURL)
        await fulfillment(of: [callbackExpectation], timeout: 1)
        XCTAssertTrue(deepLinkCallbackCalled)
        XCTAssertEqual(receivedLinkData, LinkData.unrecognized(url: testURL))
        
        // Basic assertions
        XCTAssertTrue(handled, "URL should be marked as handled")
        
        // The callback might not be called immediately (or at all in this test environment),
        // but the URL should be recognized as something the SDK handles.
        // In a real integration, the SDK would attempt to fetch link details from the API.
    }
    
    @MainActor
    func testMalformedURL() async throws {
        let linklab = sdk!
        
        // Initialize with our callback
        linklab.initialize(with: Configuration(customDomains: ["example.com"]), deepLinkCallback: { [weak self] linkData in
            self?.deepLinkCallbackCalled = true
            self?.receivedLinkData = linkData
            self?.callbackExpectation.fulfill()
        })
        
        // Test with a URL missing host
        let malformedURL = URL(string: "example-only")!
        
        // Call the method under test
        let handled = linklab.handleIncomingURL(malformedURL)
        
        // Should be handled using the unrecognized-link fallback
        XCTAssertTrue(handled, "Malformed URL should be handled as unrecognized")
        await fulfillment(of: [callbackExpectation], timeout: 1)
        XCTAssertTrue(deepLinkCallbackCalled)
        XCTAssertEqual(receivedLinkData, LinkData.unrecognized(url: malformedURL))
    }
    
    @MainActor
    func testDeprecatedHandleUniversalLink() async throws {
        let linklab = sdk!
        
        // Initialize with our callback
        linklab.initialize(with: Configuration(customDomains: ["example.com"]), deepLinkCallback: { [weak self] linkData in
            self?.deepLinkCallbackCalled = true
            self?.receivedLinkData = linkData
            self?.callbackExpectation.fulfill()
        })
        
        // Test URL
        let testURL = URL(string: "https://example.com/abc123")!
        
        // Call the deprecated method - should call through to handleIncomingURL
        let handled = linklab.handleIncomingURL(testURL)
        await fulfillment(of: [callbackExpectation], timeout: 1)
        XCTAssertTrue(deepLinkCallbackCalled)
        XCTAssertEqual(receivedLinkData, LinkData.unrecognized(url: testURL))
        
        // Should be handled
        XCTAssertTrue(handled, "URL should be handled by deprecated method")
    }
}

@available(iOS 14.3, macOS 12.0, *)
@MainActor
final class DeferredDeepLinkTests: XCTestCase {
    func testInitialLinkWaitsForAttributionAndPreservesPromoParameters() async throws {
        let service = ControlledAttributionService()
        let tracker = InstallationTracker(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        let sdk = Linklab(apiService: APIService(), attributionService: service, installationTracker: tracker)
        var callbacks: [LinkData] = []
        sdk.initialize(with: Configuration()) { if let data = $0 { callbacks.append(data) } }
        let initialLink = Task { await sdk.getInitialLink() }
        await fulfillment(of: [service.started], timeout: 1)

        XCTAssertTrue(tracker.isFirstLaunch())
        XCTAssertTrue(callbacks.isEmpty)
        sdk.processDeferredDeepLink()
        XCTAssertEqual(service.requestCount, 1)

        let expected = try promoLink()
        service.resolve(.success(expected))
        let received = await initialLink.value
        XCTAssertEqual(received, expected)
        XCTAssertEqual(callbacks, [expected])
        XCTAssertFalse(tracker.isFirstLaunch())
        XCTAssertNil(sdk.getLinkData())
        let nextLink = await sdk.getInitialLink()
        XCTAssertNil(nextLink)
        XCTAssertEqual(service.requestCount, 1)
    }

    func testFailedFirstLaunchCanRetryWithoutDuplicateCallbacks() async throws {
        let service = ControlledAttributionService()
        let tracker = InstallationTracker(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        let sdk = Linklab(apiService: APIService(), attributionService: service, installationTracker: tracker)
        var callbackCount = 0
        sdk.initialize(with: Configuration()) { _ in callbackCount += 1 }
        let firstAttempt = Task { await sdk.getInitialLink() }
        await fulfillment(of: [service.started], timeout: 1)
        service.resolve(.failure(URLError(.notConnectedToInternet)))
        let firstLink = await firstAttempt.value
        XCTAssertNil(firstLink)
        XCTAssertTrue(tracker.isFirstLaunch())
        XCTAssertEqual(callbackCount, 1)

        service.started = expectation(description: "Retry starts")
        let retry = Task { await sdk.getInitialLink() }
        await fulfillment(of: [service.started], timeout: 1)
        let expected = try promoLink()
        service.resolve(.success(expected))
        let received = await retry.value
        XCTAssertEqual(received, expected)
        XCTAssertEqual(callbackCount, 2)
        XCTAssertEqual(service.requestCount, 2)
        XCTAssertFalse(tracker.isFirstLaunch())
    }

    func testNoAttributionCompletesFirstLaunchWithoutRetrying() async {
        let service = ControlledAttributionService()
        let tracker = InstallationTracker(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        let sdk = Linklab(apiService: APIService(), attributionService: service, installationTracker: tracker)
        sdk.initialize(with: Configuration()) { _ in }
        let initialLink = Task { await sdk.getInitialLink() }
        await fulfillment(of: [service.started], timeout: 1)
        service.resolve(.failure(LinkError.apiError(statusCode: 404, message: "No matching session")))
        let received = await initialLink.value
        XCTAssertNil(received)
        XCTAssertFalse(tracker.isFirstLaunch())
        let nextLink = await sdk.getInitialLink()
        XCTAssertNil(nextLink)
        XCTAssertEqual(service.requestCount, 1)
    }

    private func promoLink() throws -> LinkData {
        let json = #"{"id":"6IbTF","fullLink":"https://potje.tech/en/?promoId=75iOS8HDjnRcPNS00qor\u0026type=getPromoCode","domainType":"customDomain","domain":"app.potje.tech"}"#
        return try JSONDecoder().decode(LinkData.self, from: Data(json.utf8))
    }
}

@available(iOS 14.0, macOS 12.0, *)
private final class ControlledAttributionService: AttributionService {
    var started = XCTestExpectation(description: "Attribution starts")
    var requestCount = 0
    private var continuation: CheckedContinuation<LinkData, Error>?

    override func fetchDeferredDeepLink() async throws -> LinkData {
        requestCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
    }

    func resolve(_ result: Result<LinkData, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
