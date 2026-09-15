import XCTest
@testable import Linklab

@MainActor
final class LinklabDirectLinkTests: XCTestCase {
    private var defaults: UserDefaults!
    private var sdk: Linklab!
    private var links: [LinkData] = []
    private var errors: [LinkError] = []

    override func setUp() async throws {
        try await super.setUp()
        MockURLProtocol.reset()
        links = []
        errors = []
        defaults = isolatedDefaults()
        markDeferredDone(defaults)
        sdk = makeSDK(defaults: defaults)
    }

    override func tearDown() async throws {
        MockURLProtocol.reset()
        sdk = nil
        try await super.tearDown()
    }

    private func initialize(customDomains: [String] = [], retryCount: Int = 3) {
        sdk.initialize(
            with: LinklabConfiguration(networkRetryCount: retryCount, customDomains: customDomains, pasteboardMode: .disabled),
            onLink: { [weak self] in self?.links.append($0) },
            onError: { [weak self] in self?.errors.append($0) }
        )
    }

    // MARK: Host filtering

    func testForeignURLIsIgnored() async {
        initialize(customDomains: ["go.example.com"])
        XCTAssertFalse(sdk.handleIncomingURL(URL(string: "https://example.com/abc123")!))
        XCTAssertFalse(sdk.handleIncomingURL(URL(string: "https://notlinklab.cc/abc123")!))
        XCTAssertFalse(sdk.handleIncomingURL(URL(string: "https://linklab.cc.evil.com/abc123")!))
        await settle()
        XCTAssertTrue(links.isEmpty)
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
        XCTAssertNil(sdk.getLinkData())
    }

    func testCustomSchemeIsIgnored() async {
        initialize()
        XCTAssertFalse(sdk.handleIncomingURL(URL(string: "myapp://linklab.cc/abc123")!))
        XCTAssertFalse(sdk.handleIncomingURL(URL(string: "example-only")!))
        await settle()
        XCTAssertTrue(links.isEmpty)
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
    }

    func testSubdomainOfLinklabIsAccepted() async throws {
        initialize()
        MockURLProtocol.stub("/links/abc123", json: resolvedJSON)
        XCTAssertTrue(sdk.handleIncomingURL(URL(string: "https://myapp.linklab.cc/abc123")!))
        await waitUntil { self.links.count == 1 }
        XCTAssertEqual(try XCTUnwrap(MockURLProtocol.requests.first).url?.query, "domain=myapp.linklab.cc")
        XCTAssertEqual(links.first?.id, "abc123")
    }

    func testCustomDomainIsAcceptedCaseInsensitively() async throws {
        initialize(customDomains: ["Go.Example.com"])
        MockURLProtocol.stub("/links/abc123", json: resolvedJSON)
        XCTAssertTrue(sdk.handleIncomingURL(URL(string: "HTTPS://GO.EXAMPLE.COM/abc123")!))
        await waitUntil { self.links.count == 1 }
        XCTAssertEqual(try XCTUnwrap(MockURLProtocol.requests.first).url?.query, "domain=go.example.com")
    }

    func testIsLinklabLink() {
        XCTAssertTrue(sdk.isLinklabLink(URL(string: "https://linklab.cc/x")!), "works before initialize for built-in hosts")
        XCTAssertFalse(sdk.isLinklabLink(URL(string: "https://go.example.com/x")!))
        initialize(customDomains: ["go.example.com"])
        XCTAssertTrue(sdk.isLinklabLink(URL(string: "https://go.example.com/x")!))
        XCTAssertFalse(sdk.isLinklabLink(URL(string: "myapp://go.example.com/x")!))
    }

    // MARK: Resolution outcomes

    func testRootPathDeliversUnrecognizedWithoutNetwork() async {
        initialize(customDomains: ["go.example.com"])
        let url = URL(string: "https://go.example.com/?promo=ABC")!
        XCTAssertTrue(sdk.handleIncomingURL(url))
        XCTAssertTrue(sdk.handleIncomingURL(URL(string: "https://linklab.cc")!))
        await settle()
        XCTAssertEqual(links.count, 2)
        XCTAssertEqual(links[0].resolutionStatus, "unrecognized")
        XCTAssertEqual(links[0].fullLink, url.absoluteString)
        XCTAssertEqual(links[0].parameters, ["promo": "ABC"])
        XCTAssertEqual(links[0].matchType, "direct")
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
    }

    func testSuccessDeliversResolvedLink() async throws {
        initialize()
        MockURLProtocol.stub("/links/abc123", json: resolvedJSON)
        let url = URL(string: "https://linklab.cc/abc123?utm=x")!
        XCTAssertTrue(sdk.handleIncomingURL(url))
        await waitUntil { self.links.count == 1 }
        let link = try XCTUnwrap(links.first)
        XCTAssertEqual(link.resolutionStatus, "resolved")
        XCTAssertEqual(link.id, "abc123")
        XCTAssertEqual(link.shortLink, url.absoluteString)
        XCTAssertEqual(link.domainType, "linklab")
        XCTAssertEqual(link.matchType, "direct")
        XCTAssertFalse(link.isDeferred)
        XCTAssertEqual(link.parameters, ["id": "123", "campaign": "server", "enc": "a b", "extra": "1"])
        XCTAssertEqual(sdk.getLinkData(), link)
        XCTAssertEqual(sdk.getLinkData(), link, "getLinkData is non-destructive")
        XCTAssertTrue(errors.isEmpty)
    }

    func testNotFoundDeliversUnrecognized() async throws {
        initialize()
        MockURLProtocol.stub("/links/gone", status: 404, json: notFoundJSON)
        let url = URL(string: "https://linklab.cc/gone?a=1")!
        sdk.handleIncomingURL(url)
        await waitUntil { self.links.count == 1 }
        let link = try XCTUnwrap(links.first)
        XCTAssertEqual(link.resolutionStatus, "unrecognized")
        XCTAssertEqual(link.fullLink, url.absoluteString)
        XCTAssertEqual(link.parameters, ["a": "1"])
        XCTAssertEqual(MockURLProtocol.requests.count, 1)
    }

    func testServerErrorThenSuccessResolves() async throws {
        initialize()
        MockURLProtocol.stub("/links/abc123", status: 500)
        MockURLProtocol.stub("/links/abc123", json: resolvedJSON)
        sdk.handleIncomingURL(URL(string: "https://linklab.cc/abc123")!)
        await waitUntil { self.links.count == 1 }
        XCTAssertEqual(links.first?.resolutionStatus, "resolved")
        XCTAssertEqual(MockURLProtocol.requests.count, 2)
    }

    func testTimeoutDeliversFailed() async throws {
        initialize(retryCount: 1)
        MockURLProtocol.stubError("/links/slow", URLError(.timedOut))
        let url = URL(string: "https://linklab.cc/slow?k=v")!
        sdk.handleIncomingURL(url)
        await waitUntil { self.links.count == 1 }
        let link = try XCTUnwrap(links.first)
        XCTAssertEqual(link.resolutionStatus, "failed")
        XCTAssertEqual(link.fullLink, url.absoluteString)
        XCTAssertEqual(link.parameters, ["k": "v"])
        XCTAssertNotNil(link.errorMessage)
        XCTAssertEqual(MockURLProtocol.requests.count, 2)
    }

    // MARK: Delivery semantics

    func testInFlightDuplicateIsIgnoredButReopenIsProcessed() async {
        initialize()
        MockURLProtocol.stub("/links/abc123", json: resolvedJSON, delay: 0.2)
        let url = URL(string: "https://linklab.cc/abc123")!
        XCTAssertTrue(sdk.handleIncomingURL(url))
        XCTAssertTrue(sdk.handleIncomingURL(url))
        await waitUntil { self.links.count == 1 }
        await settle()
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(MockURLProtocol.requests.count, 1)

        sdk.handleIncomingURL(url)
        await waitUntil { self.links.count == 2 }
        XCTAssertEqual(MockURLProtocol.requests.count, 2)
    }

    func testLateOnLinkReplaysOnce() async {
        sdk.initialize(with: LinklabConfiguration(pasteboardMode: .disabled))
        MockURLProtocol.stub("/links/abc123", json: resolvedJSON)
        sdk.handleIncomingURL(URL(string: "https://linklab.cc/abc123")!)
        await waitUntil { self.sdk.lastLink != nil }

        var first: [LinkData] = []
        sdk.onLink = { first.append($0) }
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first.first?.id, "abc123")

        var second: [LinkData] = []
        sdk.onLink = { second.append($0) }
        XCTAssertTrue(second.isEmpty, "already delivered links are not replayed again")
    }

    func testURLsBeforeInitializeAreQueuedFilteredAndProcessedInOrder() async {
        MockURLProtocol.stub("/links/one", json: resolvedJSON.replacingOccurrences(of: "abc123", with: "one"))
        MockURLProtocol.stub("/links/two", json: resolvedJSON.replacingOccurrences(of: "abc123", with: "two"))
        XCTAssertTrue(sdk.handleIncomingURL(URL(string: "https://linklab.cc/one")!))
        XCTAssertFalse(sdk.handleIncomingURL(URL(string: "https://example.com/foreign")!))
        XCTAssertFalse(sdk.handleIncomingURL(URL(string: "myapp://linklab.cc/scheme")!))
        sdk.handleIncomingURL(URL(string: "https://go.example.com/two")!)
        initialize(customDomains: ["go.example.com"])
        await waitUntil { self.links.count == 2 }
        await settle()
        // Processing starts in order; the two fetches run concurrently, so completion order is not guaranteed.
        XCTAssertEqual(Set(links.compactMap(\.id)), ["one", "two"])
        XCTAssertEqual(Set(MockURLProtocol.requests.compactMap { $0.url?.path }), ["/links/one", "/links/two"])
    }

    func testGetInitialLinkWaitsForInitializeAndInFlightFetch() async {
        MockURLProtocol.stub("/links/abc123", json: resolvedJSON, delay: 0.1)
        let initial = Task { await sdk.getInitialLink() }
        await settle(0.05)
        sdk.handleIncomingURL(URL(string: "https://linklab.cc/abc123")!)
        initialize()
        let link = await initial.value
        XCTAssertEqual(link?.id, "abc123")
        XCTAssertEqual(links.count, 1)
    }

    func testGetInitialLinkReturnsFirstLinkAndDoesNotDoubleDeliver() async {
        initialize()
        MockURLProtocol.stub("/links/first", json: resolvedJSON.replacingOccurrences(of: "abc123", with: "first"))
        MockURLProtocol.stub("/links/second", json: resolvedJSON.replacingOccurrences(of: "abc123", with: "second"))
        sdk.handleIncomingURL(URL(string: "https://linklab.cc/first")!)
        let initial = await sdk.getInitialLink()
        XCTAssertEqual(initial?.id, "first")
        sdk.handleIncomingURL(URL(string: "https://linklab.cc/second")!)
        await waitUntil { self.links.count == 2 }
        let again = await sdk.getInitialLink()
        XCTAssertEqual(again?.id, "first")
        XCTAssertEqual(sdk.getLinkData()?.id, "second")
        await settle()
        XCTAssertEqual(links.count, 2, "getInitialLink must not trigger callbacks")
    }

    func testGetInitialLinkTimesOutWithoutInitialize() async {
        let start = Date()
        let link = await sdk.getInitialLink()
        XCTAssertNil(link)
        XCTAssertGreaterThan(Date().timeIntervalSince(start), 4.5)
    }

    @available(*, deprecated)
    func testDeprecatedInitializeBridgesToOnLink() async {
        MockURLProtocol.stub("/links/abc123", json: resolvedJSON)
        var received: [LinkData?] = []
        sdk.initialize(with: Configuration(customDomains: [])) { received.append($0) }
        sdk.handleUniversalLink(URL(string: "https://linklab.cc/abc123")!)
        await waitUntil { !received.isEmpty }
        XCTAssertEqual(received.first??.id, "abc123")
    }

    func testConfigurationDefaults() {
        let config = LinklabConfiguration()
        XCTAssertEqual(config.networkTimeout, 10)
        XCTAssertEqual(config.networkRetryCount, 3)
        XCTAssertFalse(config.debugLoggingEnabled)
        XCTAssertEqual(config.customDomains, [])
        XCTAssertEqual(config.baseURL.absoluteString, "https://linklab.cc")
        XCTAssertEqual(config.pasteboardMode, .automatic)
        XCTAssertEqual(Linklab.version, "0.3.0")
    }
}

@MainActor
final class LinklabDeferredTests: XCTestCase {
    private var defaults: UserDefaults!
    private var links: [LinkData] = []
    private var errors: [LinkError] = []

    override func setUp() async throws {
        try await super.setUp()
        MockURLProtocol.reset()
        links = []
        errors = []
        defaults = isolatedDefaults()
    }

    override func tearDown() async throws {
        MockURLProtocol.reset()
        try await super.tearDown()
    }

    @discardableResult
    private func launch(mode: PasteboardMode, pasteboard: FakePasteboard, customDomains: [String] = []) async -> Linklab {
        let sdk = makeSDK(pasteboard: pasteboard, defaults: defaults)
        sdk.initialize(
            with: LinklabConfiguration(customDomains: customDomains, pasteboardMode: mode),
            onLink: { [weak self] in self?.links.append($0) },
            onError: { [weak self] in self?.errors.append($0) }
        )
        _ = await sdk.getInitialLink()
        return sdk
    }

    private var store: DeferredLinkStore { DeferredLinkStore(userDefaults: defaults) }

    // MARK: Pasteboard

    func testPasteboardURLIsResolvedAsClipboardMatch() async throws {
        let pasteboard = FakePasteboard(string: "https://linklab.cc/abc123", detectsURL: true)
        MockURLProtocol.stub("/links/abc123", json: resolvedJSON)
        await launch(mode: .automatic, pasteboard: pasteboard)

        let link = try XCTUnwrap(links.first)
        XCTAssertEqual(link.id, "abc123")
        XCTAssertEqual(link.matchType, "clipboard")
        XCTAssertTrue(link.isDeferred)
        XCTAssertEqual(link.shortLink, "https://linklab.cc/abc123")
        XCTAssertEqual(MockURLProtocol.requests(forPath: "/links/abc123").first?.url?.query, "domain=linklab.cc")
        XCTAssertTrue(MockURLProtocol.requests(forPath: "/apple-attribution").isEmpty, "ip fallback only when pasteboard found nothing")
        XCTAssertEqual(pasteboard.readCalls, 1)
        XCTAssertTrue(defaults.bool(forKey: DeferredLinkStore.Keys.pasteboardChecked))
        XCTAssertEqual(store.state, .done)
        XCTAssertTrue(errors.isEmpty)
    }

    func testLegacyTokenIsAccepted() async throws {
        let pasteboard = FakePasteboard(string: "linklab_6IbTF_customDomain_app.potje.tech", detectsURL: false)
        MockURLProtocol.stub("/links/6IbTF", json: resolvedJSON.replacingOccurrences(of: "abc123", with: "6IbTF"))
        await launch(mode: .automatic, pasteboard: pasteboard)

        let link = try XCTUnwrap(links.first)
        XCTAssertEqual(link.id, "6IbTF")
        XCTAssertEqual(link.matchType, "clipboard")
        XCTAssertNil(link.shortLink)
        XCTAssertEqual(MockURLProtocol.requests(forPath: "/links/6IbTF").first?.url?.query, "domain=app.potje.tech")
        XCTAssertEqual(pasteboard.detectCalls, 1)
        XCTAssertEqual(pasteboard.readCalls, 1)
    }

    func testForeignPasteboardURLIsRejectedAndFallsBackToIP() async {
        let pasteboard = FakePasteboard(string: "https://example.com/abc123", detectsURL: true)
        MockURLProtocol.stub("/apple-attribution", status: 404, json: notFoundJSON)
        await launch(mode: .automatic, pasteboard: pasteboard)

        XCTAssertTrue(links.isEmpty)
        XCTAssertTrue(MockURLProtocol.requests(forPath: "/links/abc123").isEmpty)
        XCTAssertEqual(MockURLProtocol.requests(forPath: "/apple-attribution").count, 1)
        XCTAssertEqual(store.state, .done)
        XCTAssertTrue(errors.isEmpty, "no deferred link is a normal outcome, not an error")
    }

    func testEmptyPasteboardIsNotRead() async {
        let pasteboard = FakePasteboard(string: nil)
        MockURLProtocol.stub("/apple-attribution", status: 404, json: notFoundJSON)
        await launch(mode: .automatic, pasteboard: pasteboard)
        XCTAssertEqual(pasteboard.hasStringsCalls, 1)
        XCTAssertEqual(pasteboard.detectCalls, 0)
        XCTAssertEqual(pasteboard.readCalls, 0)
        XCTAssertTrue(defaults.bool(forKey: DeferredLinkStore.Keys.pasteboardChecked))
    }

    func testAutomaticReadsOncePerInstall() async {
        let pasteboard = FakePasteboard(string: "not a link", detectsURL: false)
        MockURLProtocol.stub("/apple-attribution", status: 500)
        await launch(mode: .automatic, pasteboard: pasteboard)
        XCTAssertEqual(pasteboard.readCalls, 1)
        XCTAssertEqual(store.state, .pending)
        XCTAssertEqual(store.attempts, 1)

        MockURLProtocol.reset()
        MockURLProtocol.stub("/apple-attribution", json: resolvedJSON)
        await launch(mode: .automatic, pasteboard: pasteboard)
        XCTAssertEqual(pasteboard.readCalls, 1, "second launch must not read the pasteboard again")
        XCTAssertEqual(pasteboard.hasStringsCalls, 1)
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.matchType, "ipAddress")
        XCTAssertNil(links.first?.shortLink)
        XCTAssertEqual(store.state, .done)
    }

    func testPasteboardCandidateSurvivesTransientFailureWithoutRereading() async {
        let pasteboard = FakePasteboard(string: "https://linklab.cc/abc123", detectsURL: true)
        MockURLProtocol.stub("/links/abc123", status: 503)
        await launch(mode: .automatic, pasteboard: pasteboard)
        XCTAssertEqual(store.state, .pending)
        XCTAssertEqual(errors.count, 1)

        MockURLProtocol.reset()
        MockURLProtocol.stub("/links/abc123", json: resolvedJSON)
        await launch(mode: .automatic, pasteboard: pasteboard)
        XCTAssertEqual(pasteboard.readCalls, 1)
        XCTAssertEqual(links.first?.matchType, "clipboard")
        XCTAssertEqual(store.state, .done)
    }

    func testManualModeNeverReadsAutomatically() async throws {
        let pasteboard = FakePasteboard(string: "https://linklab.cc/abc123", detectsURL: true)
        MockURLProtocol.stub("/apple-attribution", status: 404, json: notFoundJSON)
        MockURLProtocol.stub("/links/abc123", json: resolvedJSON)
        let sdk = await launch(mode: .manual, pasteboard: pasteboard)
        XCTAssertEqual(pasteboard.hasStringsCalls, 0)
        XCTAssertEqual(pasteboard.detectCalls, 0)
        XCTAssertEqual(pasteboard.readCalls, 0)
        XCTAssertTrue(links.isEmpty)
        XCTAssertEqual(MockURLProtocol.requests(forPath: "/apple-attribution").count, 1)

        // Explicit check after a user action: returned AND delivered.
        let checked = await sdk.checkPasteboard()
        let link = try XCTUnwrap(checked)
        XCTAssertEqual(link.matchType, "clipboard")
        XCTAssertEqual(links, [link])
        XCTAssertEqual(pasteboard.readCalls, 1)

        // deliver: false returns the value only.
        let again = await sdk.checkPasteboard(deliver: false)
        XCTAssertEqual(again, link)
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(pasteboard.readCalls, 2, "manual mode has no once-per-install restriction")
        XCTAssertFalse(defaults.bool(forKey: DeferredLinkStore.Keys.pasteboardChecked))
    }

    func testDisabledModeNeverReads() async {
        let pasteboard = FakePasteboard(string: "https://linklab.cc/abc123", detectsURL: true)
        MockURLProtocol.stub("/apple-attribution", status: 404, json: notFoundJSON)
        let sdk = await launch(mode: .disabled, pasteboard: pasteboard)
        let manual = await sdk.checkPasteboard()
        XCTAssertNil(manual)
        XCTAssertEqual(pasteboard.hasStringsCalls, 0)
        XCTAssertEqual(pasteboard.readCalls, 0)
        XCTAssertTrue(links.isEmpty)
        XCTAssertEqual(store.state, .done, "disabled pasteboard + ip 404 is definitive")
    }

    func testCheckPasteboardBeforeInitializeReportsError() async {
        let sdk = makeSDK(defaults: defaults)
        var reported: [LinkError] = []
        sdk.onError = { reported.append($0) }
        let link = await sdk.checkPasteboard()
        XCTAssertNil(link)
        XCTAssertEqual(reported, [.notInitialized])
    }

    // MARK: State machine

    func testTransientFailureIncrementsAttemptsAndReportsError() async {
        MockURLProtocol.stub("/apple-attribution", status: 500)
        await launch(mode: .disabled, pasteboard: FakePasteboard())
        XCTAssertEqual(store.state, .pending)
        XCTAssertEqual(store.attempts, 1)
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors.first?.statusCode, 500)
        XCTAssertTrue(links.isEmpty)
    }

    func testNotFoundMarksDoneWithoutError() async {
        MockURLProtocol.stub("/apple-attribution", status: 404, json: notFoundJSON)
        await launch(mode: .disabled, pasteboard: FakePasteboard())
        XCTAssertEqual(store.state, .done)
        XCTAssertTrue(errors.isEmpty)
        XCTAssertTrue(links.isEmpty)

        MockURLProtocol.reset()
        await launch(mode: .disabled, pasteboard: FakePasteboard())
        XCTAssertTrue(MockURLProtocol.requests.isEmpty, "done state never re-runs the check")
    }

    func testThreeTransientFailuresMarkDone() async {
        MockURLProtocol.stub("/apple-attribution", status: 503)
        for attempt in 1...3 {
            await launch(mode: .disabled, pasteboard: FakePasteboard())
            XCTAssertEqual(store.attempts, attempt)
        }
        XCTAssertEqual(store.state, .done)
        XCTAssertEqual(MockURLProtocol.requests.count, 3 * 4, "each launch = 1 attempt + 3 retries")

        MockURLProtocol.reset()
        await launch(mode: .disabled, pasteboard: FakePasteboard())
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
    }

    func testOtherClientErrorIsDefinitive() async {
        MockURLProtocol.stub("/apple-attribution", status: 400)
        await launch(mode: .disabled, pasteboard: FakePasteboard())
        XCTAssertEqual(store.state, .done)
        XCTAssertEqual(errors.first?.statusCode, 400)
    }

    func testLegacyFirstLaunchKeyMeansDone() async {
        defaults.set(false, forKey: DeferredLinkStore.Keys.legacyFirstLaunch)
        await launch(mode: .automatic, pasteboard: FakePasteboard(string: "https://linklab.cc/abc123", detectsURL: true))
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
        XCTAssertEqual(store.state, .done)
    }

    func testSuccessfulIPAttributionDeliversAndCompletes() async throws {
        MockURLProtocol.stub("/apple-attribution", json: resolvedJSON)
        let sdk = await launch(mode: .disabled, pasteboard: FakePasteboard())
        let link = try XCTUnwrap(links.first)
        XCTAssertEqual(link.matchType, "ipAddress")
        XCTAssertTrue(link.isDeferred)
        XCTAssertNil(link.shortLink)
        XCTAssertEqual(store.state, .done)
        let initial = await sdk.getInitialLink()
        XCTAssertEqual(initial, link)

        let body = try XCTUnwrap(MockURLProtocol.bodies.first ?? nil)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(Set(json.keys), ["osVersion", "deviceModel", "locale", "timeZone", "bundleId"])
    }

    func testOnlyOneDeferredTaskAtATime() async {
        MockURLProtocol.stub("/apple-attribution", status: 404, json: notFoundJSON, delay: 0.1)
        let sdk = makeSDK(defaults: defaults)
        sdk.initialize(with: LinklabConfiguration(pasteboardMode: .disabled))
        sdk.processDeferredDeepLink()
        sdk.processDeferredDeepLink()
        _ = await sdk.getInitialLink()
        XCTAssertEqual(MockURLProtocol.requests.count, 1)
    }
}
