import Foundation

/// Represents the data associated with a LinkLab link, retrieved from the API.
/// Mirrors the structure used in the LinkLab Android SDK.
public struct LinkData: Codable, Equatable {
    public let id: String?
    public let rawLink: String
    public let createdAt: Date?
    public let updatedAt: Date?
    public let userId: String?
    public let packageName: String?
    public let bundleId: String?
    public let appStoreId: String?
    public let domainType: String // Non-optional
    public let domain: String?

    // Coding keys match the expected JSON keys from the API
    enum CodingKeys: String, CodingKey {
        case id
        case rawLink = "fullLink"
        case createdAt, updatedAt, userId, packageName, bundleId, appStoreId, domainType, domain
    }

    // Custom Date Formatter for ISO8601 with potential fractional seconds
    private static var dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        // Allow flexibility in format parsing
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return formatter
    }()
    
    // Standard initializer for creating LinkData instances in code/tests
    // UPDATED: id is now Optional string
    public init(
        id: String?,
        rawLink: String,
        createdAt: Date?,
        updatedAt: Date?,
        userId: String?,
        packageName: String?,
        bundleId: String?,
        appStoreId: String?,
        domainType: String,
        domain: String?
    ) {
        self.id = id
        self.rawLink = rawLink
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.userId = userId
        self.packageName = packageName
        self.bundleId = bundleId
        self.appStoreId = appStoreId
        self.domainType = domainType
        self.domain = domain
    }
    
    // Helper init for Unrecognized links
    public static func unrecognized(url: URL) -> LinkData {
        return LinkData(
            id: nil,
            rawLink: url.absoluteString,
            createdAt: nil,
            updatedAt: nil,
            userId: nil,
            packageName: nil,
            bundleId: nil,
            appStoreId: nil,
            domainType: "unrecognized",
            domain: url.host
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        rawLink = try container.decode(String.self, forKey: .rawLink)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        packageName = try container.decodeIfPresent(String.self, forKey: .packageName)
        bundleId = try container.decodeIfPresent(String.self, forKey: .bundleId)
        appStoreId = try container.decodeIfPresent(String.self, forKey: .appStoreId)
        
        // Decode domainType and domain as non-optional, throwing if missing
        domainType = try container.decode(String.self, forKey: .domainType)
        domain = try container.decodeIfPresent(String.self, forKey: .domain)

        // Handle date decoding manually to support potential nulls or format variations
        if let createdAtString = try container.decodeIfPresent(String.self, forKey: .createdAt) {
            createdAt = Self.dateFormatter.date(from: createdAtString)
            if createdAt == nil {
                // Logger not available here directly, but logic remains same
            }
        } else {
            createdAt = nil
        }

        if let updatedAtString = try container.decodeIfPresent(String.self, forKey: .updatedAt) {
            updatedAt = Self.dateFormatter.date(from: updatedAtString)
        } else {
            updatedAt = nil
        }
    }
    
    // Add Equatable conformance for testing
    public static func == (lhs: LinkData, rhs: LinkData) -> Bool {
        return lhs.id == rhs.id &&
               lhs.rawLink == rhs.rawLink &&
               lhs.createdAt == rhs.createdAt &&
               lhs.updatedAt == rhs.updatedAt &&
               lhs.userId == rhs.userId &&
               lhs.packageName == rhs.packageName &&
               lhs.bundleId == rhs.bundleId &&
               lhs.appStoreId == rhs.appStoreId &&
               lhs.domainType == rhs.domainType &&
               lhs.domain == rhs.domain
    }
}
