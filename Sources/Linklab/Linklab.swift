import Foundation

/// Entry point of the Linklab iOS SDK.
///
/// Call `initialize(with:onLink:onError:)` once at launch, forward every incoming URL to
/// `handleIncomingURL(_:)`, and receive resolved links through `onLink`.
@available(iOS 14.3, macOS 12.0, *)
@MainActor
public final class Linklab {
    public static let shared = Linklab()

    // MARK: - Public state

    /// Receives every delivered link exactly once. If set after a link was delivered while no callback was
    /// registered, that link is replayed once.
    public var onLink: ((LinkData) -> Void)? {
        didSet { replayUndeliveredLinkIfNeeded() }
    }

    /// Receives failures of the deferred check and of `checkPasteboard()`. Direct-link failures are reported
    /// through `onLink` with `resolutionStatus == "failed"` instead.
    public var onError: ((LinkError) -> Void)?

    /// The most recently delivered link (non-destructive).
    public private(set) var lastLink: LinkData?

    /// The first link delivered in this process.
    public private(set) var firstLink: LinkData?

    /// The active configuration, once `initialize(with:)` has been called.
    public private(set) var configuration: LinklabConfiguration?

    public var isInitialized: Bool { configuration != nil }

    // MARK: - Dependencies

    private let urlSession: URLSession
    private let userDefaults: UserDefaults
    private let pasteboard: PasteboardReading
    private let sleeper: Sleeper
    private var apiService: APIService?
    private var attributionService: AttributionService?
    private var store: DeferredLinkStore?

    // MARK: - Runtime state

    private var pendingURLs: [URL] = []
    private var inFlight: [String: Task<Void, Never>] = [:]
    private var deferredTask: Task<Void, Never>?
    private var hasUndeliveredLink = false
    private var initializationWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    /// Internal so tests can inject a mocked session, isolated defaults and a fake pasteboard.
    init(
        urlSession: URLSession = .shared,
        userDefaults: UserDefaults = .standard,
        pasteboard: PasteboardReading = SystemPasteboardReader(),
        sleeper: @escaping Sleeper = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        }
    ) {
        self.urlSession = urlSession
        self.userDefaults = userDefaults
        self.pasteboard = pasteboard
        self.sleeper = sleeper
    }

    // MARK: - Initialization

    /// Initializes the SDK. Safe to call once per launch, as early as possible (e.g. in
    /// `application(_:didFinishLaunchingWithOptions:)`). URLs passed to `handleIncomingURL(_:)` before this call
    /// are queued and processed in order.
    public func initialize(
        with configuration: LinklabConfiguration,
        onLink: ((LinkData) -> Void)? = nil,
        onError: ((LinkError) -> Void)? = nil
    ) {
        LinklabLogger.isEnabled = configuration.debugLoggingEnabled
        self.configuration = configuration

        let api = APIService(configuration: configuration, urlSession: urlSession, sleeper: sleeper)
        apiService = api
        store = DeferredLinkStore(userDefaults: userDefaults)
        attributionService = AttributionService(apiService: api, configuration: configuration, pasteboard: pasteboard)

        if let onError { self.onError = onError }
        if let onLink { self.onLink = onLink }
        LinklabLogger.info("Linklab \(Linklab.version) initialized (customDomains: \(configuration.customDomains.count), pasteboard: \(configuration.pasteboardMode))")

        resumeInitializationWaiters()

        let queued = pendingURLs
        pendingURLs = []
        for url in queued {
            handleIncomingURL(url)
        }

        runDeferredCheckIfNeeded()
    }

    /// Deprecated: use `initialize(with:onLink:onError:)`. The callback is bridged to `onLink`.
    @available(*, deprecated, message: "Use initialize(with:onLink:onError:) instead.")
    public func initialize(with configuration: LinklabConfiguration, deepLinkCallback: @escaping (LinkData?) -> Void) {
        initialize(with: configuration, onLink: { deepLinkCallback($0) }, onError: nil)
    }

    // MARK: - Incoming URLs

    /// `true` for http(s) URLs on linklab.cc, a subdomain of it, or a configured custom domain.
    /// Before `initialize(with:)`, only linklab.cc hosts are known.
    public func isLinklabLink(_ url: URL) -> Bool {
        LinklabHost.isLinklabLink(url, customDomains: configuration?.customDomains ?? [])
    }

    /// Forwards a URL the app received (universal link, `onOpenURL`, user activity).
    ///
    /// Returns `false` and delivers nothing for non-http(s) URLs and URLs whose host is not a Linklab host.
    /// Before `initialize(with:)` the URL is queued; the return value then reflects only the built-in hosts,
    /// because custom domains are not known yet.
    @discardableResult
    public func handleIncomingURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            LinklabLogger.debug("Ignoring URL with unsupported scheme: \(url.scheme ?? "nil")")
            return false
        }
        guard let configuration else {
            LinklabLogger.debug("Not initialized yet; queueing \(LinklabLogger.describe(url))")
            pendingURLs.append(url)
            return LinklabHost.isLinklabLink(url, customDomains: [])
        }
        guard LinklabHost.isLinklabLink(url, customDomains: configuration.customDomains) else {
            LinklabLogger.debug("Ignoring non-Linklab URL \(LinklabLogger.describe(url))")
            return false
        }
        process(url)
        return true
    }

    /// Deprecated: use `handleIncomingURL(_:)`.
    @available(*, deprecated, renamed: "handleIncomingURL(_:)")
    @discardableResult
    public func handleUniversalLink(_ url: URL) -> Bool {
        handleIncomingURL(url)
    }

    // MARK: - Reading results

    /// The most recently delivered link, without clearing it.
    public func getLinkData() -> LinkData? { lastLink }

    /// The first link delivered in this process, or `nil`.
    ///
    /// Waits (up to 5 s) for `initialize(with:)` if it has not been called yet, then for any in-flight direct
    /// fetch and the deferred check. Never triggers a callback by itself.
    public func getInitialLink() async -> LinkData? {
        if configuration == nil {
            await waitForInitialization(timeout: 5)
        }
        await awaitInFlightWork(timeout: 5)
        return firstLink
    }

    /// Runs the deferred (first-launch) check if the persisted state machine still allows it.
    /// Called automatically by `initialize(with:)`; normally there is no need to call it.
    public func processDeferredDeepLink() {
        runDeferredCheckIfNeeded()
    }

    /// Reads the pasteboard once and resolves a Linklab URL or token found there.
    ///
    /// Intended for `pasteboardMode == .manual` after an explicit user action; also allowed in `.automatic`.
    /// Returns `nil` in `.disabled` mode or when nothing was found. The result is returned **and**, when
    /// `deliver` is `true` (default), also delivered through `onLink`.
    @discardableResult
    public func checkPasteboard(deliver: Bool = true) async -> LinkData? {
        guard let configuration, let attributionService else {
            onError?(.notInitialized)
            return nil
        }
        guard configuration.pasteboardMode != .disabled else {
            LinklabLogger.debug("checkPasteboard() ignored: pasteboardMode is .disabled")
            return nil
        }
        guard let candidate = await attributionService.readPasteboardCandidate() else { return nil }
        do {
            guard let link = try await attributionService.resolve(candidate) else { return nil }
            if deliver { self.deliver(link) }
            return link
        } catch {
            report(error)
            return nil
        }
    }

    // MARK: - Direct links

    private func process(_ url: URL) {
        let key = url.absoluteString
        guard inFlight[key] == nil else {
            LinklabLogger.debug("URL already in flight; ignoring duplicate \(LinklabLogger.describe(url))")
            return
        }
        guard let linkId = LinklabHost.linkId(of: url) else {
            LinklabLogger.debug("Root path on Linklab host; delivering as unrecognized")
            deliver(.unrecognized(url: url))
            return
        }
        guard let apiService, let host = url.host?.lowercased() else {
            onError?(.notInitialized)
            return
        }

        LinklabLogger.debug("Resolving \(LinklabLogger.describe(url))")
        inFlight[key] = Task { @MainActor [weak self] in
            let result: LinkData
            do {
                let decoded = try await apiService.fetchLink(id: linkId, domain: host)
                result = .resolved(from: decoded, shortLink: url.absoluteString, isDeferred: false, matchType: LinkData.MatchType.direct)
            } catch LinkError.apiError(statusCode: 404, message: _) {
                result = .unrecognized(url: url)
            } catch {
                result = .failed(url: url, message: error.localizedDescription)
            }
            guard let self else { return }
            self.inFlight[key] = nil
            self.deliver(result)
        }
    }

    // MARK: - Deferred state machine

    private func runDeferredCheckIfNeeded() {
        guard deferredTask == nil, let store, let attributionService, let configuration else { return }
        guard store.shouldRunDeferredCheck() else {
            LinklabLogger.debug("Deferred check not needed (state: \(store.state.rawValue))")
            return
        }
        LinklabLogger.info("Running deferred check (attempt \(store.attempts + 1)/\(DeferredLinkStore.maxAttempts))")
        deferredTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performDeferredCheck(store: store, attribution: attributionService, configuration: configuration)
            self.deferredTask = nil
        }
    }

    private func performDeferredCheck(store: DeferredLinkStore, attribution: AttributionService, configuration: LinklabConfiguration) async {
        do {
            var link: LinkData?

            if configuration.pasteboardMode == .automatic {
                var candidate = store.pasteboardCandidate
                if candidate == nil, !store.pasteboardChecked {
                    store.pasteboardChecked = true // once per install, regardless of outcome
                    candidate = await attribution.readPasteboardCandidate()
                    store.pasteboardCandidate = candidate // kept for retries after a transient failure
                }
                if let candidate {
                    link = try await attribution.resolve(candidate)
                }
            }

            if link == nil {
                link = try await attribution.fetchIPAttribution()
            }

            store.markDone()
            if let link {
                LinklabLogger.info("Deferred link found via \(link.matchType)")
                deliver(link)
            } else {
                LinklabLogger.debug("No deferred link for this install")
            }
        } catch {
            let linkError = (error as? LinkError) ?? .internalError(error.localizedDescription)
            if linkError.isTransient {
                store.recordTransientFailure()
                LinklabLogger.debug("Deferred check failed transiently (\(linkError.code)); attempts=\(store.attempts)")
            } else {
                store.markDone()
                LinklabLogger.error("Deferred check failed definitively: \(linkError.localizedDescription)")
            }
            onError?(linkError)
        }
    }

    // MARK: - Delivery

    private func deliver(_ link: LinkData) {
        if firstLink == nil { firstLink = link }
        lastLink = link
        LinklabLogger.debug("Delivering link: status=\(link.resolutionStatus) match=\(link.matchType) id=\(link.id ?? "-")")
        if let onLink {
            hasUndeliveredLink = false
            onLink(link)
        } else {
            hasUndeliveredLink = true
        }
    }

    private func replayUndeliveredLinkIfNeeded() {
        guard hasUndeliveredLink, let onLink, let lastLink else { return }
        hasUndeliveredLink = false
        onLink(lastLink)
    }

    private func report(_ error: Error) {
        let linkError = (error as? LinkError) ?? .internalError(error.localizedDescription)
        LinklabLogger.error(linkError.localizedDescription)
        onError?(linkError)
    }

    // MARK: - Waiting helpers

    private func waitForInitialization(timeout: TimeInterval) async {
        guard configuration == nil else { return }
        let id = UUID()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            initializationWaiters[id] = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.initializationWaiters.removeValue(forKey: id)?.resume()
            }
        }
    }

    private func resumeInitializationWaiters() {
        let waiters = initializationWaiters
        initializationWaiters = [:]
        waiters.values.forEach { $0.resume() }
    }

    /// Waits for the current direct fetches and the deferred task, capped at `timeout`.
    private func awaitInFlightWork(timeout: TimeInterval) async {
        let tasks = Array(inFlight.values) + [deferredTask].compactMap { $0 }
        guard !tasks.isEmpty else { return }
        let gate = ResumeOnce()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            gate.continuation = continuation
            Task { @MainActor in
                for task in tasks { await task.value }
                gate.resume()
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                gate.resume()
            }
        }
    }
}

@MainActor
private final class ResumeOnce {
    var continuation: CheckedContinuation<Void, Never>?
    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
