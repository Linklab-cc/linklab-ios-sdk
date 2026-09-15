import XCTest
@testable import Linklab

final class DeferredLinkStoreTests: XCTestCase {
    func testDefaultsToPendingAndRunsCheck() {
        let store = DeferredLinkStore(userDefaults: isolatedDefaults())
        XCTAssertEqual(store.state, .pending)
        XCTAssertEqual(store.attempts, 0)
        XCTAssertTrue(store.shouldRunDeferredCheck())
    }

    func testTransientFailuresAreBoundedToThreeAttempts() {
        let store = DeferredLinkStore(userDefaults: isolatedDefaults())
        store.recordTransientFailure()
        XCTAssertEqual(store.attempts, 1)
        XCTAssertEqual(store.state, .pending)
        XCTAssertTrue(store.shouldRunDeferredCheck())
        store.recordTransientFailure()
        XCTAssertTrue(store.shouldRunDeferredCheck())
        store.recordTransientFailure()
        XCTAssertEqual(store.attempts, 3)
        XCTAssertEqual(store.state, .done)
        XCTAssertFalse(store.shouldRunDeferredCheck())
    }

    func testTwentyFourHourWindow() {
        let defaults = isolatedDefaults()
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = DeferredLinkStore(userDefaults: defaults, now: { now })
        XCTAssertTrue(store.shouldRunDeferredCheck())
        now = now.addingTimeInterval(23 * 3600)
        XCTAssertTrue(store.shouldRunDeferredCheck())
        now = now.addingTimeInterval(2 * 3600)
        XCTAssertFalse(store.shouldRunDeferredCheck())
        XCTAssertEqual(store.state, .done)
        XCTAssertEqual(defaults.object(forKey: DeferredLinkStore.Keys.firstLaunchAt) as? Double, 1_700_000_000_000)
    }

    func testLegacyFirstLaunchKeyMigratesToDone() {
        let defaults = isolatedDefaults()
        defaults.set(false, forKey: DeferredLinkStore.Keys.legacyFirstLaunch)
        let store = DeferredLinkStore(userDefaults: defaults)
        XCTAssertEqual(store.state, .done)
        XCTAssertFalse(store.shouldRunDeferredCheck())
        XCTAssertNil(defaults.object(forKey: DeferredLinkStore.Keys.legacyFirstLaunch))
    }

    func testStatePersistsAcrossInstances() {
        let defaults = isolatedDefaults()
        DeferredLinkStore(userDefaults: defaults).markDone()
        XCTAssertEqual(DeferredLinkStore(userDefaults: defaults).state, .done)
        XCTAssertEqual(defaults.string(forKey: DeferredLinkStore.Keys.state), "done")
    }

    func testPasteboardCandidatePersistsAndClearsOnDone() {
        let defaults = isolatedDefaults()
        let store = DeferredLinkStore(userDefaults: defaults)
        let candidate = PasteboardCandidate(linkId: "abc", domain: "linklab.cc", shortLink: "https://linklab.cc/abc")
        store.pasteboardCandidate = candidate
        XCTAssertEqual(DeferredLinkStore(userDefaults: defaults).pasteboardCandidate, candidate)
        store.markDone()
        XCTAssertNil(store.pasteboardCandidate)
    }
}
