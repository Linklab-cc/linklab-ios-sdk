import XCTest
@testable import LinkLabSDK

final class InstallationTrackerTests: XCTestCase {
    private let firstLaunchKey = "linklab_first_launch_key"
    private var installationTracker: InstallationTracker!
    
    override func setUp() {
        super.setUp()
        // Clear the UserDefaults for tests
        UserDefaults.standard.removeObject(forKey: firstLaunchKey)
        installationTracker = InstallationTracker()
    }
    
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: firstLaunchKey)
        installationTracker = nil
        super.tearDown()
    }
    
    func testFirstLaunch() {
        // First call should return true
        XCTAssertTrue(installationTracker.isFirstLaunch())
        
        // Second call should return false
        XCTAssertFalse(installationTracker.isFirstLaunch())
    }
}
