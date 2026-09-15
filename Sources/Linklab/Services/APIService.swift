import Foundation

/// Async sleeper, injectable so tests can skip retry backoff.
typealias Sleeper = @Sendable (TimeInterval) async -> Void

/// Talks to the Linklab backend with timeout, retries and the contract headers.
final class APIService: @unchecked Sendable {
    /// Backoff between retries (contract rule 4).
    static let retryDelays: [TimeInterval] = [0.5, 1, 2]

    private let configuration: LinklabConfiguration
    private let urlSession: URLSession
    private let sleeper: Sleeper
    private let bundleIdentifier: String

    init(
        configuration: LinklabConfiguration,
        urlSession: URLSession = .shared,
        sleeper: @escaping Sleeper = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        },
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "unknown"
    ) {
        self.configuration = configuration
        self.urlSession = urlSession
        self.sleeper = sleeper
        self.bundleIdentifier = bundleIdentifier
    }

    // MARK: - Endpoints

    /// `GET {baseURL}/links/{id}?domain={host}`. Throws `LinkError` (`.apiError(404, _)` when unknown).
    func fetchLink(id: String, domain: String) async throws -> LinkData {
        guard !id.isEmpty else { throw LinkError.invalidURL("Link id is empty.") }
        var components = URLComponents(
            url: configuration.baseURL.appendingPathComponent("links").appendingPathComponent(id),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "domain", value: domain)]
        guard let url = components?.url else { throw LinkError.internalError("Could not build the links URL.") }

        var request = makeRequest(url: url)
        request.httpMethod = "GET"
        let data = try await send(request)
        return try decode(data)
    }

    /// `POST {baseURL}/apple-attribution`. Returns `nil` on 404 (no deferred link for this device).
    func fetchIPAttribution(body: [String: String]) async throws -> LinkData? {
        let url = configuration.baseURL.appendingPathComponent("apple-attribution")
        var request = makeRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let data = try await send(request)
            return try decode(data)
        } catch LinkError.apiError(statusCode: 404, message: _) {
            return nil
        }
    }

    // MARK: - Plumbing

    var userAgent: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "\(os.majorVersion).\(os.minorVersion)" + (os.patchVersion > 0 ? ".\(os.patchVersion)" : "")
        #if os(iOS)
        let platform = "iOS"
        #elseif os(macOS)
        let platform = "macOS"
        #else
        let platform = "Apple"
        #endif
        return "Linklab-iOS-SDK/\(Linklab.version) (\(platform) \(osVersion); \(bundleIdentifier))"
    }

    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: configuration.networkTimeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("ios/\(Linklab.version)", forHTTPHeaderField: "X-Linklab-Sdk")
        request.setValue(bundleIdentifier, forHTTPHeaderField: "X-Linklab-App")
        return request
    }

    private func decode(_ data: Data) throws -> LinkData {
        do {
            return try JSONDecoder().decode(LinkData.self, from: data)
        } catch {
            LinklabLogger.error("Failed to decode backend payload: \(error.localizedDescription)")
            throw LinkError.decodingError(error)
        }
    }

    /// Performs the request with retries for transient failures only (URLError / 5xx).
    private func send(_ request: URLRequest) async throws -> Data {
        let maxAttempts = configuration.networkRetryCount + 1
        var attempt = 0
        while true {
            attempt += 1
            let outcome: Result<Data, LinkError>
            do {
                let (data, response) = try await perform(request)
                guard let http = response as? HTTPURLResponse else {
                    throw LinkError.internalError("Non-HTTP response.")
                }
                LinklabLogger.debug("\(request.httpMethod ?? "GET") \(LinklabLogger.describe(request.url!)) -> \(http.statusCode)")
                if (200..<300).contains(http.statusCode) {
                    return data
                }
                outcome = .failure(.apiError(statusCode: http.statusCode, message: HTTPURLResponse.localizedString(forStatusCode: http.statusCode)))
            } catch let error as URLError where error.code == .timedOut {
                outcome = .failure(.timeout)
            } catch let error as URLError {
                outcome = .failure(.networkError(error))
            } catch let error as LinkError {
                outcome = .failure(error)
            } catch {
                outcome = .failure(.networkError(error))
            }

            guard case .failure(let linkError) = outcome else { continue }
            if linkError.isTransient, attempt < maxAttempts, !Task.isCancelled {
                let delay = Self.retryDelays[min(attempt - 1, Self.retryDelays.count - 1)]
                LinklabLogger.debug("Request failed (\(linkError.code)); retry \(attempt)/\(maxAttempts - 1) in \(delay)s")
                await sleeper(delay)
                continue
            }
            LinklabLogger.error("Request failed: \(linkError.localizedDescription)")
            throw linkError
        }
    }

    /// `URLSession.data(for:)` is iOS 15+, so wrap the task API for the iOS 14.3 deployment target.
    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let box = TaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = urlSession.dataTask(with: request) { data, response, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let response {
                        continuation.resume(returning: (data ?? Data(), response))
                    } else {
                        continuation.resume(throwing: LinkError.internalError("Empty response."))
                    }
                }
                box.set(task)
                task.resume()
            }
        } onCancel: {
            box.cancel()
        }
    }
}

/// Holds a `URLSessionTask` so it can be cancelled from the cancellation handler.
private final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var cancelled = false

    func set(_ task: URLSessionTask) {
        lock.lock(); defer { lock.unlock() }
        self.task = task
        if cancelled { task.cancel() }
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        task?.cancel()
    }
}
