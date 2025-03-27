import Foundation
import StoreKit

#if canImport(AdServices)
import AdServices
#endif

@available(iOS 14.3, macOS 11.1, *)
public class Linklab {
    public static let shared = Linklab()
    
    private var configuration: Configuration?
    private var installationTracker: InstallationTracker?
    // Using Any type for macOS compatibility - will be downcast when used
    private var attributionService: Any?
    private var universalLinkHandler: UniversalLinkHandler?
    private var deepLinkProcessor: DeepLinkProcessor?
    
    private var deepLinkCallback: ((LinkDestination?) -> Void)?
    
    private init() {}
    
    /// Initialize the Linklab SDK
    /// - Parameters:
    ///   - config: Configuration for the Linklab SDK
    ///   - deepLinkCallback: Callback that will be called when a deep link is processed
    public func initialize(with config: Configuration, deepLinkCallback: @escaping (LinkDestination?) -> Void) {
        self.configuration = config
        self.deepLinkCallback = deepLinkCallback
        
        self.installationTracker = InstallationTracker()
        if #available(macOS 12.0, *) {
            self.attributionService = AttributionService()
        }
        self.universalLinkHandler = UniversalLinkHandler()
        self.deepLinkProcessor = DeepLinkProcessor()
        
        // Check for deferred deep link if this is a new installation
        checkForDeferredDeepLink()
    }
    
    /// Handle a Universal Link
    /// - Parameter url: The URL that was opened
    /// - Returns: Boolean indicating whether the URL was handled
    @discardableResult
    public func handleUniversalLink(_ url: URL) -> Bool {
        guard let universalLinkHandler = universalLinkHandler,
              let deepLinkProcessor = deepLinkProcessor else {
            Logger.error("Linklab not initialized")
            return false
        }
        
        do {
            // Parse the URL
            let params = try universalLinkHandler.parseUniversalLink(url)
            
            // Process deep link parameters
            let destination = deepLinkProcessor.processDeepLink(params: params)
            
            // Deliver the deep link to the app
            deepLinkCallback?(destination)
            
            return true
        } catch {
            Logger.error("Failed to handle universal link: \(error)")
            return false
        }
    }
    
    /// Manually trigger processing of a deferred deep link
    public func processDeferredDeepLink() {
        checkForDeferredDeepLink()
    }
    
    // MARK: - Private Methods
    
    private func checkForDeferredDeepLink() {
        guard let installationTracker = installationTracker else {
            Logger.error("Linklab not initialized")
            return
        }
        
        if #available(macOS 12.0, *) {
            guard let attributionService = attributionService as? AttributionService else {
                return
            }
        
        // Check if this is a new installation
        if installationTracker.isFirstLaunch() {
            // Request attribution token from AdServices
            #if canImport(AdServices)
            Task {
                    do {
                        // The attributionToken() method is not async in AdServices
                        let token = try AdServices.AAAttribution.attributionToken()
                        
                        // Send token to attribution service
                        try await attributionService.fetchDeferredDeepLink(token: token) { [weak self] result in
                        switch result {
                        case .success(let params):
                            // Process deep link parameters
                            if let self = self, let processor = self.deepLinkProcessor {
                                let destination = processor.processDeepLink(params: params)
                                // Deliver the deep link to the app
                                self.deepLinkCallback?(destination)
                            }
                        case .failure(let error):
                            Logger.error("Failed to fetch deferred deep link: \(error)")
                            self?.deepLinkCallback?(nil)
                        }
                    }
                } catch {
                    Logger.error("Failed to get attribution token: \(error)")
                    deepLinkCallback?(nil)
                }
            }
            #endif
        }
        }
    }
}
