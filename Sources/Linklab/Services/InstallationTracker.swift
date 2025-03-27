import Foundation

class InstallationTracker {
    private let userDefaults = UserDefaults.standard
    private let firstLaunchKey = "linklab_first_launch_key"
    
    /// Checks if this is the first launch of the app
    /// - Returns: Boolean indicating whether this is the first launch
    func isFirstLaunch() -> Bool {
        if userDefaults.object(forKey: firstLaunchKey) == nil {
            // This is the first launch, save the flag
            userDefaults.set(false, forKey: firstLaunchKey)
            userDefaults.synchronize()
            return true
        }
        return false
    }
}
