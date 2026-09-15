import XCTest
@testable import Linklab

final class APIServiceTests: XCTestCase {
    private var recorder = Recorder<TimeInterval>()
    private var delays: [TimeInterval] { recorder.values }
    private var service: APIService!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        let recorder = Recorder<TimeInterval>()
        self.recorder = recorder
        service = APIService(
            configuration: LinklabConfiguration(networkTimeout: 3, networkRetryCount: 3),
            urlSession: mockSession(),
            sleeper: { seconds in recorder.append(seconds) },
            bundleIdentifier: "com.example.app"
        )
    }

    override func tearDown() {
        MockURLProtocol.reset()
        service = nil
        super.tearDown()
    }

    func testFetchLinkSendsContractHeadersAndQuery() async throws {
        MockURLProtocol.stub("/links/abc123", json: resolvedJSON)
        let link = try await service.fetchLink(id: "abc123", domain: "sub.linklab.cc")
        XCTAssertEqual(link.id, "abc123")

        let request = try XCTUnwrap(MockURLProtocol.requests(forPath: "/links/abc123").first)
        XCTAssertEqual(request.url?.query, "domain=sub.linklab.cc")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Linklab-Sdk"), "ios/\(Linklab.version)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Linklab-App"), "com.example.app")
        let userAgent = try XCTUnwrap(request.value(forHTTPHeaderField: "User-Agent"))
        XCTAssertTrue(userAgent.hasPrefix("Linklab-iOS-SDK/\(Linklab.version) ("), userAgent)
        XCTAssertTrue(userAgent.hasSuffix("; com.example.app)"), userAgent)
        XCTAssertEqual(request.timeoutInterval, 3)
    }

    func test404IsNotRetried() async {
        MockURLProtocol.stub("/links/missing", status: 404, json: notFoundJSON)
        do {
            _ = try await service.fetchLink(id: "missing", domain: "linklab.cc")
            XCTFail("expected 404")
        } catch let error as LinkError {
            XCTAssertEqual(error.statusCode, 404)
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertEqual(MockURLProtocol.requests(forPath: "/links/missing").count, 1)
        XCTAssertEqual(delays, [])
    }

    func test500ThenSuccessRetriesWithBackoff() async throws {
        MockURLProtocol.stub("/links/abc123", status: 503)
        MockURLProtocol.stub("/links/abc123", status: 200, json: resolvedJSON)
        let link = try await service.fetchLink(id: "abc123", domain: "linklab.cc")
        XCTAssertEqual(link.id, "abc123")
        XCTAssertEqual(MockURLProtocol.requests(forPath: "/links/abc123").count, 2)
        XCTAssertEqual(delays, [0.5])
    }

    func testTimeoutExhaustsRetries() async {
        MockURLProtocol.stubError("/links/slow", URLError(.timedOut))
        do {
            _ = try await service.fetchLink(id: "slow", domain: "linklab.cc")
            XCTFail("expected timeout")
        } catch let error as LinkError {
            XCTAssertEqual(error, .timeout)
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertEqual(MockURLProtocol.requests(forPath: "/links/slow").count, 4, "initial attempt + 3 retries")
        XCTAssertEqual(delays, [0.5, 1, 2])
    }

    func testDecodingErrorIsNotRetried() async {
        MockURLProtocol.stub("/links/bad", json: #"{"nope":true}"#)
        do {
            _ = try await service.fetchLink(id: "bad", domain: "linklab.cc")
            XCTFail("expected decoding error")
        } catch let error as LinkError {
            XCTAssertEqual(error.code, "DECODING")
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertEqual(MockURLProtocol.requests(forPath: "/links/bad").count, 1)
    }

    func testIPAttributionReturnsNilOn404AndDecodesOn200() async throws {
        MockURLProtocol.stub("/apple-attribution", status: 404, json: notFoundJSON)
        let none = try await service.fetchIPAttribution(body: ["bundleId": "com.example.app"])
        XCTAssertNil(none)

        MockURLProtocol.reset()
        MockURLProtocol.stub("/apple-attribution", json: resolvedJSON)
        let link = try await service.fetchIPAttribution(body: ["bundleId": "com.example.app", "osVersion": "17.0"])
        XCTAssertEqual(link?.id, "abc123")
        let request = try XCTUnwrap(MockURLProtocol.requests(forPath: "/apple-attribution").first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(MockURLProtocol.bodies.first ?? nil)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json["bundleId"], "com.example.app")
        XCTAssertEqual(json["osVersion"], "17.0")
    }

    func testRespectsRetryCountZero() async {
        let noRetry = APIService(configuration: LinklabConfiguration(networkRetryCount: 0), urlSession: mockSession(), sleeper: { _ in })
        MockURLProtocol.stub("/links/x", status: 500)
        _ = try? await noRetry.fetchLink(id: "x", domain: "linklab.cc")
        XCTAssertEqual(MockURLProtocol.requests(forPath: "/links/x").count, 1)
    }
}
