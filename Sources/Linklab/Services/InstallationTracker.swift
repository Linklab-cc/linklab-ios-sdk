import Foundation

class InstallationTracker {
    private let userDefaults: UserDefaults
    private let firstLaunchKey = "linklab_first_launch_key"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// Checks if this is the first launch of the app
    /// - Returns: Boolean indicating whether this is the first launch
    func isFirstLaunch() -> Bool {
        return userDefaults.object(forKey: firstLaunchKey) == nil
    }

    func markAttributionCompleted() {
        // This is the first launch, save the flag
        userDefaults.set(false, forKey: firstLaunchKey)
    }
}
