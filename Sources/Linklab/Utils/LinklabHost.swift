import Foundation

/// Host matching shared by direct links and pasteboard URLs.
enum LinklabHost {
    static let rootHost = "linklab.cc"

    /// `linklab.cc` or any subdomain of it.
    static func isLinklabOwnedHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased(), !host.isEmpty else { return false }
        return host == rootHost || host.hasSuffix("." + rootHost)
    }

    /// Contract rule 1: linklab.cc, *.linklab.cc or a configured custom domain (case-insensitive).
    static func matches(_ host: String?, customDomains: [String]) -> Bool {
        guard let host = host?.lowercased(), !host.isEmpty else { return false }
        return isLinklabOwnedHost(host) || customDomains.contains { $0.lowercased() == host }
    }

    /// `true` only for http(s) URLs whose host matches.
    static func isLinklabLink(_ url: URL, customDomains: [String]) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        return matches(url.host, customDomains: customDomains)
    }

    /// Link id from the path, or `nil` for the root path.
    static func linkId(of url: URL) -> String? {
        let id = url.lastPathComponent
        guard !id.isEmpty, id != "/" else { return nil }
        return id
    }
}
