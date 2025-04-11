import Foundation

/// Represents the data associated with a LinkLab link, retrieved from the API.
public struct LinkData: Codable {
    public let id: String
    public let fullLink: String
    public let createdAt: Date? // Use Date for automatic decoding
    public let updatedAt: Date? // Use Date for automatic decoding
    public let userId: String
    public let packageName: String?
    public let bundleId: String?
    public let appStoreId: String?
    public let domainType: String? // Optional as per API call
    public let domain: String?     // Optional as per API call

    // Adjust coding keys if they differ from the JSON keys
    enum CodingKeys: String, CodingKey {
        case id
        case fullLink
        case createdAt
        case updatedAt
        case userId
        case packageName
        case bundleId
        case appStoreId
        case domainType // Assuming API returns these as optional query params if requested
        case domain
    }

    // Custom Date Formatter for ISO8601 with milliseconds
    private static var dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        fullLink = try container.decode(String.self, forKey: .fullLink)
        userId = try container.decode(String.self, forKey: .userId)
        packageName = try container.decodeIfPresent(String.self, forKey: .packageName)
        bundleId = try container.decodeIfPresent(String.self, forKey: .bundleId)
        appStoreId = try container.decodeIfPresent(String.self, forKey: .appStoreId)
        domainType = try container.decodeIfPresent(String.self, forKey: .domainType)
        domain = try container.decodeIfPresent(String.self, forKey: .domain)

        // Handle date decoding manually to support potential nulls or format variations
        if let createdAtString = try container.decodeIfPresent(String.self, forKey: .createdAt) {
            createdAt = Self.dateFormatter.date(from: createdAtString)
        } else {
            createdAt = nil
        }

        if let updatedAtString = try container.decodeIfPresent(String.self, forKey: .updatedAt) {
            updatedAt = Self.dateFormatter.date(from: updatedAtString)
        } else {
            updatedAt = nil
        }
    }
} 