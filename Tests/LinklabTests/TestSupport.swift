import Foundation
import XCTest
@testable import Linklab

// MARK: - MockURLProtocol

/// Thread-safe URL stubbing keyed by request path (query string ignored).
final class MockURLProtocol: URLProtocol {
    struct Stub {
        var statusCode: Int = 200
        var body: Data = Data()
        var error: Error? = nil
        var delay: TimeInterval = 0
    }

    private static let lock = NSLock()
    private static var queues: [String: [Stub]] = [:]
    private static var recorded: [URLRequest] = []
    private static var recordedBodies: [Data?] = []

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        queues = [:]
        recorded = []
        recordedBodies = []
    }

    /// Queue a response for `path`. Multiple stubs for the same path are consumed in order; the last one repeats.
    static func stub(_ path: String, status: Int = 200, json: String = "{}", delay: TimeInterval = 0) {
        lock.lock(); defer { lock.unlock() }
        queues[path, default: []].append(Stub(statusCode: status, body: Data(json.utf8), delay: delay))
    }

    static func stubError(_ path: String, _ error: Error) {
        lock.lock(); defer { lock.unlock() }
        queues[path, default: []].append(Stub(error: error))
    }

    static var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    static func requests(forPath path: String) -> [URLRequest] {
        requests.filter { $0.url?.path == path }
    }

    static var bodies: [Data?] {
        lock.lock(); defer { lock.unlock() }
        return recordedBodies
    }

    private static func dequeue(for path: String) -> Stub? {
        lock.lock(); defer { lock.unlock() }
        guard var queue = queues[path], !queue.isEmpty else { return nil }
        let stub = queue.count > 1 ? queue.removeFirst() : queue[0]
        queues[path] = queue
        return stub
    }

    private static func record(_ request: URLRequest, body: Data?) {
        lock.lock(); defer { lock.unlock() }
        recorded.append(request)
        recordedBodies.append(body)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.record(request, body: Self.readBody(of: request))
        guard let stub = Self.dequeue(for: url.path) else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "MockURLProtocol", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unstubbed path \(url.path)"]))
            return
        }
        let deliver = { [self] in
            if let error = stub.error {
                client?.urlProtocol(self, didFailWithError: error)
                return
            }
            let response = HTTPURLResponse(url: url, statusCode: stub.statusCode, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.body)
            client?.urlProtocolDidFinishLoading(self)
        }
        if stub.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + stub.delay, execute: deliver)
        } else {
            deliver()
        }
    }

    private static func readBody(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

// MARK: - Fake pasteboard

final class FakePasteboard: PasteboardReading, @unchecked Sendable {
    private let lock = NSLock()
    private var _string: String?
    private var _detects: Bool?
    private var _hasStringsCalls = 0
    private var _detectCalls = 0
    private var _readCalls = 0

    init(string: String? = nil, detectsURL: Bool? = nil) {
        _string = string
        _detects = detectsURL
    }

    private func synchronized<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    var hasStringsCalls: Int { synchronized { _hasStringsCalls } }
    var detectCalls: Int { synchronized { _detectCalls } }
    var readCalls: Int { synchronized { _readCalls } }

    func hasStrings() async -> Bool {
        synchronized { _hasStringsCalls += 1; return _string != nil }
    }

    func detectsWebURL() async -> Bool? {
        synchronized { _detectCalls += 1; return _detects }
    }

    func string() async -> String? {
        synchronized { _readCalls += 1; return _string }
    }
}

/// Records values from `@Sendable` closures.
final class Recorder<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [T] = []
    var values: [T] { lock.lock(); defer { lock.unlock() }; return _values }
    func append(_ value: T) { lock.lock(); _values.append(value); lock.unlock() }
}

// MARK: - Helpers

func isolatedDefaults() -> UserDefaults {
    let name = "cc.linklab.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

func markDeferredDone(_ defaults: UserDefaults) {
    defaults.set("done", forKey: DeferredLinkStore.Keys.state)
}

func mockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

@MainActor
func makeSDK(pasteboard: PasteboardReading = FakePasteboard(), defaults: UserDefaults) -> Linklab {
    Linklab(urlSession: mockSession(), userDefaults: defaults, pasteboard: pasteboard, sleeper: { _ in })
}

/// Polls `condition` on the main actor until it holds or `timeout` elapses.
@MainActor
func waitUntil(timeout: TimeInterval = 3, _ condition: @MainActor () -> Bool) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}

@MainActor
func settle(_ seconds: TimeInterval = 0.15) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}

let resolvedJSON = """
{"id":"abc123","fullLink":"https://example.com/product?id=123&campaign=test&enc=a%20b","createdAt":"2025-03-24T12:00:00.250Z","updatedAt":"2025-03-24T12:00:00Z","userId":"user123","packageName":null,"bundleId":"com.example.app","appStoreId":"987654321","domainType":"default","domain":"linklab.cc","parameters":{"campaign":"server","extra":"1"}}
"""

let notFoundJSON = #"{"error":"Link not found"}"#
