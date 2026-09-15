import Foundation

/// The result of resolving a Linklab link.
///
/// Field names are identical across the Linklab Android, iOS and Flutter SDKs.
public struct LinkData: Codable, Equatable, Sendable {
    /// Server link id. `nil` for `unrecognized` / `failed` results.
    public let id: String?
    /// Resolved destination URL. For `unrecognized` / `failed` results this is the original URL as received.
    public let fullLink: String
    /// The URL as received by the app (universal link / clipboard URL). `nil` for IP attribution.
    public let shortLink: String?
    public let createdAt: Date?
    public let updatedAt: Date?
    public let packageName: String?
    public let bundleId: String?
    public let appStoreId: String?
    /// Host of the short link.
    public let domain: String?
    /// `"linklab"` | `"custom"` | `"unrecognized"`.
    public let domainType: String
    /// Query parameters of `fullLink` (URL-decoded), overridden by the server-side `parameters` map. Never nil.
    public let parameters: [String: String]
    /// `"resolved"` | `"unrecognized"` | `"failed"`.
    public let resolutionStatus: String
    /// Set when `resolutionStatus == "failed"`.
    public let errorMessage: String?
    /// `true` when the link was obtained through deferred attribution (pasteboard / IP).
    public let isDeferred: Bool
    /// `"direct"` | `"installReferrer"` | `"clipboard"` | `"ipAddress"` | `"none"`.
    public let matchType: String

    @available(*, deprecated, renamed: "fullLink")
    public var rawLink: String { fullLink }

    /// `true` when the link was resolved by the Linklab backend.
    public var isResolved: Bool { resolutionStatus == ResolutionStatus.resolved }

    /// `fullLink` as a `URL`, when it parses.
    public var url: URL? { URL(string: fullLink) }

    public enum ResolutionStatus {
        public static let resolved = "resolved"
        public static let unrecognized = "unrecognized"
        public static let failed = "failed"
    }

    public enum DomainType {
        public static let linklab = "linklab"
        public static let custom = "custom"
        public static let unrecognized = "unrecognized"
    }

    public enum MatchType {
        public static let direct = "direct"
        public static let installReferrer = "installReferrer"
        public static let clipboard = "clipboard"
        public static let ipAddress = "ipAddress"
        public static let none = "none"
    }

    public init(
        id: String?,
        fullLink: String,
        shortLink: String?,
        createdAt: Date?,
        updatedAt: Date?,
        packageName: String?,
        bundleId: String?,
        appStoreId: String?,
        domain: String?,
        domainType: String,
        parameters: [String: String],
        resolutionStatus: String,
        errorMessage: String?,
        isDeferred: Bool,
        matchType: String
    ) {
        self.id = id
        self.fullLink = fullLink
        self.shortLink = shortLink
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.packageName = packageName
        self.bundleId = bundleId
        self.appStoreId = appStoreId
        self.domain = domain
        self.domainType = domainType
        self.parameters = parameters
        self.resolutionStatus = resolutionStatus
        self.errorMessage = errorMessage
        self.isDeferred = isDeferred
        self.matchType = matchType
    }

    // MARK: - Factories

    /// A link on a Linklab host that the backend does not know (404) or that has no id (root path).
    public static func unrecognized(url: URL) -> LinkData {
        fallback(url: url, status: ResolutionStatus.unrecognized, message: nil)
    }

    /// A link on a Linklab host that could not be resolved because of a network / server / decoding failure.
    public static func failed(url: URL, message: String) -> LinkData {
        fallback(url: url, status: ResolutionStatus.failed, message: message)
    }

    private static func fallback(url: URL, status: String, message: String?) -> LinkData {
        LinkData(
            id: nil,
            fullLink: url.absoluteString,
            shortLink: url.absoluteString,
            createdAt: nil,
            updatedAt: nil,
            packageName: nil,
            bundleId: nil,
            appStoreId: nil,
            domain: url.host?.lowercased(),
            domainType: DomainType.unrecognized,
            parameters: queryParameters(of: url.absoluteString),
            resolutionStatus: status,
            errorMessage: message,
            isDeferred: false,
            matchType: MatchType.direct
        )
    }

    /// Re-tags a server-decoded payload with the delivery context.
    static func resolved(from decoded: LinkData, shortLink: String?, isDeferred: Bool, matchType: String) -> LinkData {
        LinkData(
            id: decoded.id,
            fullLink: decoded.fullLink,
            shortLink: shortLink,
            createdAt: decoded.createdAt,
            updatedAt: decoded.updatedAt,
            packageName: decoded.packageName,
            bundleId: decoded.bundleId,
            appStoreId: decoded.appStoreId,
            domain: decoded.domain,
            domainType: decoded.domainType,
            parameters: decoded.parameters,
            resolutionStatus: ResolutionStatus.resolved,
            errorMessage: nil,
            isDeferred: isDeferred,
            matchType: matchType
        )
    }

    /// URL-decoded query parameters of a URL string. Later duplicates win.
    static func queryParameters(of urlString: String) -> [String: String] {
        guard let items = URLComponents(string: urlString)?.queryItems else { return [:] }
        var result: [String: String] = [:]
        for item in items where !item.name.isEmpty {
            result[item.name] = item.value ?? ""
        }
        return result
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, fullLink, shortLink, createdAt, updatedAt, packageName, bundleId, appStoreId
        case domain, domainType, parameters, resolutionStatus, errorMessage, isDeferred, matchType
    }

    /// Decodes either a raw backend payload (`GET /links/{id}`, `POST /apple-attribution`) or a
    /// previously encoded `LinkData`. Backend payloads decode as `resolved` / `direct`; use
    /// `resolved(from:shortLink:isDeferred:matchType:)` to tag the delivery context.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        fullLink = try c.decode(String.self, forKey: .fullLink)
        shortLink = try c.decodeIfPresent(String.self, forKey: .shortLink)
        createdAt = try Self.decodeDate(from: c, key: .createdAt)
        updatedAt = try Self.decodeDate(from: c, key: .updatedAt)
        packageName = try c.decodeIfPresent(String.self, forKey: .packageName)
        bundleId = try c.decodeIfPresent(String.self, forKey: .bundleId)
        appStoreId = try c.decodeIfPresent(String.self, forKey: .appStoreId)
        let domain = try c.decodeIfPresent(String.self, forKey: .domain)
        self.domain = domain
        domainType = Self.normalizeDomainType(try c.decodeIfPresent(String.self, forKey: .domainType), domain: domain)

        var merged = Self.queryParameters(of: fullLink)
        if let serverParameters = try c.decodeIfPresent([String: JSONScalar].self, forKey: .parameters) {
            for (key, value) in serverParameters {
                if let string = value.stringValue { merged[key] = string }
            }
        }
        parameters = merged

        resolutionStatus = try c.decodeIfPresent(String.self, forKey: .resolutionStatus) ?? ResolutionStatus.resolved
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        isDeferred = try c.decodeIfPresent(Bool.self, forKey: .isDeferred) ?? false
        matchType = try c.decodeIfPresent(String.self, forKey: .matchType) ?? MatchType.direct
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encode(fullLink, forKey: .fullLink)
        try c.encodeIfPresent(shortLink, forKey: .shortLink)
        try c.encodeIfPresent(createdAt.map { Self.isoWithFractionalSeconds.string(from: $0) }, forKey: .createdAt)
        try c.encodeIfPresent(updatedAt.map { Self.isoWithFractionalSeconds.string(from: $0) }, forKey: .updatedAt)
        try c.encodeIfPresent(packageName, forKey: .packageName)
        try c.encodeIfPresent(bundleId, forKey: .bundleId)
        try c.encodeIfPresent(appStoreId, forKey: .appStoreId)
        try c.encodeIfPresent(domain, forKey: .domain)
        try c.encode(domainType, forKey: .domainType)
        try c.encode(parameters, forKey: .parameters)
        try c.encode(resolutionStatus, forKey: .resolutionStatus)
        try c.encodeIfPresent(errorMessage, forKey: .errorMessage)
        try c.encode(isDeferred, forKey: .isDeferred)
        try c.encode(matchType, forKey: .matchType)
    }

    /// Server sends `"default"` for links on linklab.cc; missing on a linklab.cc host also means `"linklab"`.
    static func normalizeDomainType(_ raw: String?, domain: String?) -> String {
        switch raw?.lowercased() {
        case nil, "":
            return LinklabHost.isLinklabOwnedHost(domain) ? DomainType.linklab : DomainType.custom
        case "default":
            return DomainType.linklab
        default:
            return raw!
        }
    }

    // MARK: Dates (ISO-8601 with and without fractional seconds, or epoch millis)

    private static let isoWithFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseDate(_ string: String) -> Date? {
        isoWithFractionalSeconds.date(from: string) ?? isoPlain.date(from: string)
    }

    private static func decodeDate(from c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Date? {
        guard c.contains(key), !(try c.decodeNil(forKey: key)) else { return nil }
        if let string = try? c.decode(String.self, forKey: key) {
            return parseDate(string)
        }
        if let number = try? c.decode(Double.self, forKey: key) {
            // Heuristic: values above 1e11 are epoch milliseconds, otherwise seconds.
            return Date(timeIntervalSince1970: number > 1e11 ? number / 1000 : number)
        }
        return nil
    }
}

/// Tolerant scalar used for the server `parameters` map, which may contain non-string values.
private enum JSONScalar: Decodable {
    case string(String), int(Int), double(Double), bool(Bool), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode(Int.self) { self = .int(v); return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported parameter value")
    }

    var stringValue: String? {
        switch self {
        case .string(let v): return v
        case .int(let v): return String(v)
        case .double(let v): return String(v)
        case .bool(let v): return String(v)
        case .null: return nil
        }
    }
}
