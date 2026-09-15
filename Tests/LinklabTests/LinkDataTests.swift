import XCTest
@testable import Linklab

final class LinkDataTests: XCTestCase {
    private func decode(_ json: String) throws -> LinkData {
        try JSONDecoder().decode(LinkData.self, from: Data(json.utf8))
    }

    func testDecodesBackendPayloadWithMergedParametersAndDomainTypeMapping() throws {
        let link = try decode(resolvedJSON)
        XCTAssertEqual(link.id, "abc123")
        XCTAssertEqual(link.fullLink, "https://example.com/product?id=123&campaign=test&enc=a%20b")
        XCTAssertEqual(link.domainType, "linklab", "server 'default' maps to 'linklab'")
        XCTAssertEqual(link.domain, "linklab.cc")
        XCTAssertEqual(link.bundleId, "com.example.app")
        XCTAssertEqual(link.appStoreId, "987654321")
        XCTAssertNil(link.packageName)
        // Query params first (URL-decoded), then server parameters override.
        XCTAssertEqual(link.parameters, ["id": "123", "campaign": "server", "enc": "a b", "extra": "1"])
        XCTAssertEqual(link.resolutionStatus, "resolved")
        XCTAssertEqual(link.matchType, "direct")
        XCTAssertFalse(link.isDeferred)
        XCTAssertNil(link.shortLink)
        XCTAssertNil(link.errorMessage)
    }

    func testDatesWithAndWithoutFractionalSeconds() throws {
        let link = try decode(resolvedJSON)
        let createdAt = try XCTUnwrap(link.createdAt, "fractional-second ISO-8601 must decode")
        let updatedAt = try XCTUnwrap(link.updatedAt, "plain ISO-8601 must decode")
        XCTAssertEqual(createdAt.timeIntervalSince1970, 1742817600.25, accuracy: 0.001)
        XCTAssertEqual(updatedAt.timeIntervalSince1970, 1742817600, accuracy: 0.001)
    }

    func testEpochMillisDates() throws {
        let link = try decode(#"{"id":"x","fullLink":"https://e.com","createdAt":1742817600250,"domain":"linklab.cc"}"#)
        XCTAssertEqual(try XCTUnwrap(link.createdAt).timeIntervalSince1970, 1742817600.25, accuracy: 0.001)
    }

    func testUnparseableDateIsNilNotFatal() throws {
        let link = try decode(#"{"id":"x","fullLink":"https://e.com","createdAt":"yesterday"}"#)
        XCTAssertNil(link.createdAt)
    }

    func testDomainTypeMissingFollowsHost() throws {
        XCTAssertEqual(try decode(#"{"id":"x","fullLink":"https://e.com","domain":"app.linklab.cc"}"#).domainType, "linklab")
        XCTAssertEqual(try decode(#"{"id":"x","fullLink":"https://e.com","domain":"go.example.com"}"#).domainType, "custom")
        XCTAssertEqual(try decode(#"{"id":"x","fullLink":"https://e.com","domainType":"custom"}"#).domainType, "custom")
    }

    func testUserIdIsNotExposed() throws {
        let link = try decode(resolvedJSON)
        let mirror = Mirror(reflecting: link)
        XCTAssertFalse(mirror.children.contains { $0.label == "userId" })
    }

    func testUnrecognizedAndFailedFactories() {
        let url = URL(string: "https://go.example.com/?promo=ABC&x=1")!
        let unrecognized = LinkData.unrecognized(url: url)
        XCTAssertNil(unrecognized.id)
        XCTAssertEqual(unrecognized.fullLink, url.absoluteString)
        XCTAssertEqual(unrecognized.shortLink, url.absoluteString)
        XCTAssertEqual(unrecognized.domain, "go.example.com")
        XCTAssertEqual(unrecognized.domainType, "unrecognized")
        XCTAssertEqual(unrecognized.resolutionStatus, "unrecognized")
        XCTAssertEqual(unrecognized.parameters, ["promo": "ABC", "x": "1"])
        XCTAssertEqual(unrecognized.matchType, "direct")
        XCTAssertFalse(unrecognized.isDeferred)

        let failed = LinkData.failed(url: url, message: "boom")
        XCTAssertEqual(failed.resolutionStatus, "failed")
        XCTAssertEqual(failed.errorMessage, "boom")
        XCTAssertEqual(failed.parameters, ["promo": "ABC", "x": "1"])
    }

    func testResolvedHelperTagsContext() throws {
        let decoded = try decode(resolvedJSON)
        let link = LinkData.resolved(from: decoded, shortLink: "https://linklab.cc/abc123", isDeferred: true, matchType: "clipboard")
        XCTAssertEqual(link.shortLink, "https://linklab.cc/abc123")
        XCTAssertTrue(link.isDeferred)
        XCTAssertEqual(link.matchType, "clipboard")
        XCTAssertEqual(link.parameters, decoded.parameters)
    }

    func testEncodeDecodeRoundTrip() throws {
        let original = LinkData.resolved(from: try decode(resolvedJSON), shortLink: "https://linklab.cc/abc123", isDeferred: true, matchType: "ipAddress")
        let data = try JSONEncoder().encode(original)
        let copy = try JSONDecoder().decode(LinkData.self, from: data)
        XCTAssertEqual(copy, original)
    }

    @available(*, deprecated)
    func testRawLinkAlias() throws {
        let link = try decode(resolvedJSON)
        XCTAssertEqual(link.rawLink, link.fullLink)
    }

    func testHostMatching() {
        XCTAssertTrue(LinklabHost.matches("linklab.cc", customDomains: []))
        XCTAssertTrue(LinklabHost.matches("LinkLab.CC", customDomains: []))
        XCTAssertTrue(LinklabHost.matches("myapp.linklab.cc", customDomains: []))
        XCTAssertFalse(LinklabHost.matches("notlinklab.cc", customDomains: []))
        XCTAssertFalse(LinklabHost.matches("linklab.cc.evil.com", customDomains: []))
        XCTAssertTrue(LinklabHost.matches("GO.Example.com", customDomains: ["go.example.com"]))
        XCTAssertFalse(LinklabHost.matches("example.com", customDomains: ["go.example.com"]))
        XCTAssertFalse(LinklabHost.isLinklabLink(URL(string: "myapp://linklab.cc/abc")!, customDomains: []))
        XCTAssertTrue(LinklabHost.isLinklabLink(URL(string: "HTTPS://linklab.cc/abc")!, customDomains: []))
    }

    func testPasteboardCandidateParsing() {
        XCTAssertEqual(
            PasteboardCandidate.parse("https://linklab.cc/abc123?x=1", customDomains: []),
            PasteboardCandidate(linkId: "abc123", domain: "linklab.cc", shortLink: "https://linklab.cc/abc123?x=1")
        )
        XCTAssertEqual(
            PasteboardCandidate.parse(" https://Go.Example.com/XYZ \n", customDomains: ["go.example.com"])?.domain,
            "go.example.com"
        )
        XCTAssertNil(PasteboardCandidate.parse("https://example.com/abc123", customDomains: []), "foreign host rejected")
        XCTAssertNil(PasteboardCandidate.parse("https://linklab.cc/", customDomains: []), "root path has no id")
        XCTAssertNil(PasteboardCandidate.parse("myapp://linklab.cc/abc", customDomains: []), "custom scheme rejected")
        XCTAssertEqual(
            PasteboardCandidate.parse("linklab_6IbTF_customDomain_app.potje.tech", customDomains: []),
            PasteboardCandidate(linkId: "6IbTF", domain: "app.potje.tech", shortLink: nil)
        )
        // Domain may contain underscores; id and type may not.
        XCTAssertEqual(PasteboardCandidate.parse("linklab_id_type_my_odd.host", customDomains: [])?.domain, "my_odd.host")
        XCTAssertNil(PasteboardCandidate.parse("linklab_only_two", customDomains: []))
        XCTAssertNil(PasteboardCandidate.parse("hello world", customDomains: []))
        XCTAssertNil(PasteboardCandidate.parse("", customDomains: []))
    }
}
