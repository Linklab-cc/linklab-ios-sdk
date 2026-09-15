import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Abstraction over `UIPasteboard` so the SDK can be tested without touching the real pasteboard.
protocol PasteboardReading: Sendable {
    /// `UIPasteboard.general.hasStrings` — does not trigger the paste banner.
    func hasStrings() async -> Bool
    /// `detectPatterns(for: [\.probableWebURL])` (iOS 15+ Swift API) — `true`/`false` when detection ran, `nil` when unavailable (iOS 14).
    func detectsWebURL() async -> Bool?
    /// Reads the string (may trigger the iOS paste banner).
    func string() async -> String?
}

/// Production reader backed by `UIPasteboard.general`. On macOS everything is `nil`/`false`.
struct SystemPasteboardReader: PasteboardReading {
    @MainActor
    func hasStrings() async -> Bool {
        #if canImport(UIKit)
        return UIPasteboard.general.hasStrings
        #else
        return false
        #endif
    }

    @MainActor
    func detectsWebURL() async -> Bool? {
        #if canImport(UIKit)
        if #available(iOS 15.0, *) {
            let patterns: Set<PartialKeyPath<UIPasteboard.DetectedValues>> = [\.probableWebURL]
            return await withCheckedContinuation { (continuation: CheckedContinuation<Bool?, Never>) in
                UIPasteboard.general.detectPatterns(for: patterns) { result in
                    switch result {
                    case .success(let detected):
                        continuation.resume(returning: detected.contains(\.probableWebURL))
                    case .failure:
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
        return nil
        #else
        return nil
        #endif
    }

    @MainActor
    func string() async -> String? {
        #if canImport(UIKit)
        return UIPasteboard.general.string
        #else
        return nil
        #endif
    }
}

/// A Linklab reference found on the pasteboard.
struct PasteboardCandidate: Codable, Equatable, Sendable {
    let linkId: String
    let domain: String
    /// The pasteboard content when it was a URL; `nil` for the legacy `linklab_<id>_<type>_<domain>` token.
    let shortLink: String?

    /// Accepts a Linklab URL (host must pass the host check) or the legacy token.
    ///
    /// Legacy token format is `linklab_<id>_<domainType>_<domain>` where `<id>` and `<domainType>` cannot contain
    /// underscores (they are matched with `[^_]+`); the domain is the remainder and may contain anything.
    static func parse(_ raw: String, customDomains: [String]) -> PasteboardCandidate? {
        let string = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !string.isEmpty else { return nil }

        if let url = URL(string: string), url.scheme != nil {
            guard LinklabHost.isLinklabLink(url, customDomains: customDomains),
                  let host = url.host?.lowercased(),
                  let id = LinklabHost.linkId(of: url) else { return nil }
            return PasteboardCandidate(linkId: id, domain: host, shortLink: url.absoluteString)
        }

        let pattern = "^linklab_([^_]+)_([^_]+)_(.+)$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(string.startIndex..., in: string)
        guard let match = regex.firstMatch(in: string, range: range), match.numberOfRanges == 4,
              let idRange = Range(match.range(at: 1), in: string),
              let domainRange = Range(match.range(at: 3), in: string) else { return nil }
        return PasteboardCandidate(linkId: String(string[idRange]), domain: String(string[domainRange]).lowercased(), shortLink: nil)
    }
}
