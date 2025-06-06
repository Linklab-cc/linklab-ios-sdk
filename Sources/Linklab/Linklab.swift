import Foundation
import StoreKit

@available(iOS 14.3, macOS 11.1, *)
@MainActor
public class Linklab {
    // Define constants for LinkLab domain
    private static let linklabHost = "linklab.cc"
    
    public static let shared = Linklab()
    
    // Store configuration including custom domains
    private var configuration: Configuration?

    private var installationTracker: InstallationTracker?
    private var apiService: APIService?
    // Using Any type for macOS compatibility - will be downcast when used
    private var attributionService: Any?
    
    // Callback now returns the full LinkData object
    private var deepLinkCallback: ((LinkData?) -> Void)?
    
    // Store the most recent link data
    private var currentLinkData: LinkData?
    
    // Store incoming URL if it arrives before initialization
    private var pendingDeepLinkURL: URL?
    
    private init() {}
    
    /// Initialize the Linklab SDK
    /// - Parameters:
    ///   - config: Configuration for the Linklab SDK
    ///   - deepLinkCallback: Callback called when a deep link is processed, returning LinkData
    public func initialize(with config: Configuration, deepLinkCallback: @escaping (LinkData?) -> Void) {
        self.configuration = config
        self.deepLinkCallback = deepLinkCallback
        // Removed initialization of configuredCustomDomains
        // self.configuredCustomDomains = Set(config.customDomains.map { $0.lowercased() })
        // if !configuredCustomDomains.isEmpty {
        //      Logger.info("Initialized with custom domains: \(self.configuredCustomDomains.joined(separator: ", "))")
        // }
        
        self.installationTracker = InstallationTracker()
        self.apiService = APIService()
        if #available(macOS 12.0, *) {
            self.attributionService = AttributionService()
        }
        
        // Check for deferred deep link if this is a new installation
        checkForDeferredDeepLink()

        // Process any pending deep link URL received before initialization
        if let pendingURL = pendingDeepLinkURL {
            Logger.debug("Processing pending deep link URL: \(pendingURL.absoluteString)")
            handleIncomingURL(pendingURL) // Process the stored URL
            self.pendingDeepLinkURL = nil // Clear the stored URL
        }
    }
    
    /// Handle an incoming URL (Universal Link or Custom Scheme)
    /// - Parameter url: The URL that was opened
    /// - Returns: Boolean indicating whether the URL was identified as a LinkLab link and is being processed.
    @discardableResult
    public func handleIncomingURL(_ url: URL) -> Bool {
        // Check if the SDK has been initialized
        guard configuration != nil else {
            Logger.info("SDK not yet initialized. Storing incoming URL for later processing: \(url.absoluteString)")
            self.pendingDeepLinkURL = url
            return true // Indicate that we will handle this URL later
        }

        guard let host = url.host?.lowercased() else { // Lowercase host for comparison
            Logger.debug("Incoming URL has no host: \(url.absoluteString)")
            return false // Still need a host to proceed
        }

        // Removed domain validation checks. Assume any URL might be a LinkLab link.
        Logger.debug("Processing potential LinkLab URL: \(url.absoluteString)")
        processIncomingURL(url, host: host) // Pass the lowercased host
        return true // Indicate that we are processing this URL
    }

    // MARK: - Deprecated Handlers (Kept for compatibility, redirect to new handler)

    /// Deprecated: Use handleIncomingURL instead. Handles a Universal Link.
    /// - Parameter url: The URL that was opened
    /// - Returns: Boolean indicating whether the URL was handled
    @available(*, deprecated, message: "Use handleIncomingURL(_:) instead.")
    @discardableResult
    public func handleUniversalLink(_ url: URL) -> Bool {
        return handleIncomingURL(url)
    }

    // Optional: Add a similar handler for custom schemes if your app uses them
    // public func handleCustomSchemeURL(_ url: URL) -> Bool { ... }
    
    /// Manually trigger processing of a deferred deep link
    public func processDeferredDeepLink() {
        checkForDeferredDeepLink()
    }
    
    /// Get the most recently processed link data, if any
    /// - Returns: The most recent LinkData or nil if no link has been processed
    public func getLinkData() -> LinkData? {
        return currentLinkData
    }
    
    // MARK: - Private Methods
    
    /// Checks if the URL is a LinkLab URL and initiates fetching details if it is.
    /// - Parameter url: The incoming URL.
    /// - Parameter host: The lowercased host extracted from the URL.
    private func processIncomingURL(_ url: URL, host: String) {
        guard let apiService = apiService else {
            Logger.error("Linklab not initialized or APIService is missing.")
            notifyCallback(with: nil, error: LinkError.notInitialized)
            return
        }

        // Extract the last path component as the potential link ID
        let linkId = url.lastPathComponent
        guard !linkId.isEmpty && linkId != "/" else { // Ensure lastPathComponent is not empty or just "/"
             Logger.error("Cannot extract link ID from URL: \(url.absoluteString)")
             notifyCallback(with: nil, error: LinkError.invalidURL("Cannot extract link ID."))
             return
        }

        // Domain is simply the host provided
        let domain = host // Use the already lowercased host

        Logger.debug("Extracted LinkID: \(linkId), Domain: \(domain)")

        // Call the API service to fetch link details - removed domainType parameter
        apiService.fetchLinkDetails(linkId: linkId, domain: domain) { [weak self] result in
             // Hop back to main actor for UI updates / callback
             Task { @MainActor [weak self] in
                 guard let self = self else { return }
                 switch result {
                 case .success(let linkData):
                      Logger.info("Successfully fetched link data for ID \(linkId)")
                      // Pass the full LinkData object to the callback
                      self.notifyCallback(with: linkData)
                 case .failure(let error):
                      Logger.error("Failed to fetch link details for ID \(linkId): \(error.localizedDescription)")
                      self.notifyCallback(with: nil, error: error)
                 }
             }
        }
    }

    private func checkForDeferredDeepLink() {
        guard let installationTracker = installationTracker else {
            Logger.error("Linklab not initialized")
            return
        }
        
        if #available(macOS 12.0, *) {
            // Check if the service exists and is the correct type, don't need the value here.
            guard self.attributionService is AttributionService else {
                 Logger.debug("AttributionService not available or wrong type initially.")
                return
            }
        
            // Check if this is a new installation
            if installationTracker.isFirstLaunch() {
                 Logger.info("First launch detected. Checking for deferred deep link.")
                 
                 // Ensure service is accessible from MainActor context before Task
                 guard let attributionService = self.attributionService as? AttributionService else {
                     // Already on MainActor, safe to log and return
                     Logger.error("AttributionService not available when checking for deferred deep link.")
                     return
                 }
                 
                 // Task runs detached from MainActor
                 // Capture the non-optional 'attributionService' constant defined above
                 Task { [attributionService] in 
                     do {
                          Logger.debug("Requesting deferred deep link based on IP address...")
                         
                         // Send request to attribution service without token
                          try await attributionService.fetchDeferredDeepLink() { result in
                              // Completion handler may run on any thread. Hop back to MainActor.
                              Task { @MainActor [weak self] in // Explicitly run callback logic on MainActor
                                  guard let self = self else { return } // Safely unwrap self
                                  switch result {
                                  case .success(let linkData): 
                                       Logger.info("Successfully fetched deferred link data.")
                                       // Pass the full LinkData object to the callback
                                       self.notifyCallback(with: linkData) // Safe on MainActor
                                  case .failure(let error):
                                       Logger.error("Failed to fetch deferred deep link: \(error.localizedDescription)")
                                       self.notifyCallback(with: nil, error: error) // Safe on MainActor
                                  }
                              }
                         }
                     } catch {
                          Logger.error("Failed to fetch deferred deep link: \(error.localizedDescription)")
                          // Hop back to MainActor to call notifyCallback safely
                          Task { @MainActor [weak self] in
                              self?.notifyCallback(with: nil, error: error)
                          }
                     }
                 }
            } else {
                 Logger.debug("Not first launch. Skipping deferred deep link check.")
            }
        } else {
            Logger.error("macOS version too old for AttributionService.")
        }
    }

    /// Helper to safely call the deep link callback on the main thread.
    private func notifyCallback(with linkData: LinkData? = nil, error: Error? = nil) {
        // Ensure execution on the main thread
        if Thread.isMainThread {
             if let error = error {
                  // Optionally, enhance LinkDestination or callback to include errors
                  Logger.error("Notifying callback with error: \(error.localizedDescription)")
                  deepLinkCallback?(nil) // Pass nil data on error
             } else {
                  // Store the link data for later retrieval
                  if let linkData = linkData {
                      currentLinkData = linkData
                  }
                  
                  // Log relevant info from LinkData
                  Logger.debug("Notifying callback with LinkData: id=\(linkData?.id ?? "nil"), fullLink=\(linkData?.fullLink ?? "nil")")
                  deepLinkCallback?(linkData)
             }
        } else {
            // Ensure hopping back to main thread if called from background
            Task { @MainActor [weak self] in
                self?.notifyCallback(with: linkData, error: error)
            }
        }
    }
}
