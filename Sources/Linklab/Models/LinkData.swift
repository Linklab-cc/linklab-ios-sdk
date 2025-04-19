import Foundation

/// Represents the data associated with a LinkLab link, retrieved from the API.
/// Mirrors the structure used in the LinkLab Android SDK.
public struct LinkData: Codable, Equatable {
    public let id: String
    public let fullLink: String
    public let createdAt: Date?
    public let updatedAt: Date?
    public let userId: String
    public let packageName: String?
    public let bundleId: String?
    public let appStoreId: String?
    public let domainType: String // Non-optional like Android
    public let domain: String     // Non-optional like Android

    // Coding keys match the expected JSON keys from the API
    enum CodingKeys: String, CodingKey {
        case id, fullLink, createdAt, updatedAt, userId, packageName, bundleId, appStoreId, domainType, domain
    }

    // Custom Date Formatter for ISO8601 with potential fractional seconds
    private static var dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        // Allow flexibility in format parsing
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return formatter
    }()
    
    // Standard initializer for creating LinkData instances in code/tests
    public init(
        id: String,
        fullLink: String,
        createdAt: Date?,
        updatedAt: Date?,
        userId: String,
        packageName: String?,
        bundleId: String?,
        appStoreId: String?,
        domainType: String,
        domain: String
    ) {
        self.id = id
        self.fullLink = fullLink
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.userId = userId
        self.packageName = packageName
        self.bundleId = bundleId
        self.appStoreId = appStoreId
        self.domainType = domainType
        self.domain = domain
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        fullLink = try container.decode(String.self, forKey: .fullLink)
        userId = try container.decode(String.self, forKey: .userId)
        packageName = try container.decodeIfPresent(String.self, forKey: .packageName)
        bundleId = try container.decodeIfPresent(String.self, forKey: .bundleId)
        appStoreId = try container.decodeIfPresent(String.self, forKey: .appStoreId)
        
        // Decode domainType and domain as non-optional, throwing if missing
        domainType = try container.decode(String.self, forKey: .domainType)
        domain = try container.decode(String.self, forKey: .domain)

        // Handle date decoding manually to support potential nulls or format variations
        if let createdAtString = try container.decodeIfPresent(String.self, forKey: .createdAt) {
            createdAt = Self.dateFormatter.date(from: createdAtString)
            if createdAt == nil {
                Logger.error("Failed to parse createdAt date string: \(createdAtString)")
                // Optionally throw an error here if dates are critical and must be valid
                // throw DecodingError.dataCorruptedError(forKey: .createdAt, in: container, debugDescription: "Invalid date format")
            }
        } else {
            createdAt = nil
        }

        if let updatedAtString = try container.decodeIfPresent(String.self, forKey: .updatedAt) {
            updatedAt = Self.dateFormatter.date(from: updatedAtString)
             if updatedAt == nil {
                 Logger.error("Failed to parse updatedAt date string: \(updatedAtString)")
                 // Optionally throw an error here
                 // throw DecodingError.dataCorruptedError(forKey: .updatedAt, in: container, debugDescription: "Invalid date format")
             }
        } else {
            updatedAt = nil
        }
    }
    
    // Add Equatable conformance for testing
    public static func == (lhs: LinkData, rhs: LinkData) -> Bool {
        return lhs.id == rhs.id &&
               lhs.fullLink == rhs.fullLink &&
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