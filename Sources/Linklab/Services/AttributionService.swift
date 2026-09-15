import Foundation

/// Deferred deep-link sources: pasteboard (URL or legacy token) and IP attribution.
final class AttributionService {
    private let apiService: APIService
    private let configuration: LinklabConfiguration
    private let pasteboard: PasteboardReading

    init(apiService: APIService, configuration: LinklabConfiguration, pasteboard: PasteboardReading) {
        self.apiService = apiService
        self.configuration = configuration
        self.pasteboard = pasteboard
    }

    // MARK: - Pasteboard

    /// Applies the pasteboard gates (`hasStrings`, then `detectPatterns`) and reads the string at most once.
    /// Returns `nil` when the pasteboard holds nothing that looks like a Linklab reference.
    func readPasteboardCandidate() async -> PasteboardCandidate? {
        guard await pasteboard.hasStrings() else {
            LinklabLogger.debug("Pasteboard has no strings; skipping.")
            return nil
        }
        let detected = await pasteboard.detectsWebURL()
        if detected == true {
            LinklabLogger.debug("Pasteboard contains a probable web URL.")
        } else {
            // No URL pattern (or detection unavailable): read anyway to support the legacy token.
            LinklabLogger.debug("No web URL pattern on pasteboard; reading for a legacy token.")
        }
        guard let string = await pasteboard.string() else { return nil }
        let candidate = PasteboardCandidate.parse(string, customDomains: configuration.customDomains)
        if candidate == nil {
            LinklabLogger.debug("Pasteboard content is not a Linklab reference.")
        }
        return candidate
    }

    /// Resolves a candidate. Returns `nil` when the backend does not know the link (404).
    func resolve(_ candidate: PasteboardCandidate) async throws -> LinkData? {
        do {
            let decoded = try await apiService.fetchLink(id: candidate.linkId, domain: candidate.domain)
            return LinkData.resolved(from: decoded, shortLink: candidate.shortLink, isDeferred: true, matchType: LinkData.MatchType.clipboard)
        } catch LinkError.apiError(statusCode: 404, message: _) {
            LinklabLogger.debug("Pasteboard link is unknown to the backend.")
            return nil
        }
    }

    // MARK: - IP attribution

    /// `POST /apple-attribution`. Returns `nil` when there is no deferred link for this device.
    func fetchIPAttribution() async throws -> LinkData? {
        let body: [String: String] = [
            "osVersion": Self.osVersionString,
            "deviceModel": Self.deviceModel,
            "locale": Locale.current.identifier,
            "timeZone": TimeZone.current.identifier,
            "bundleId": Bundle.main.bundleIdentifier ?? "unknown",
        ]
        guard let decoded = try await apiService.fetchIPAttribution(body: body) else { return nil }
        return LinkData.resolved(from: decoded, shortLink: nil, isDeferred: true, matchType: LinkData.MatchType.ipAddress)
    }

    static var osVersionString: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// Hardware identifier such as `iPhone15,2` (from `utsname`).
    static var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let bytes = mirror.children.compactMap { $0.value as? Int8 }.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let model = String(decoding: bytes, as: UTF8.self)
        return model.isEmpty ? "unknown" : model
    }
}
