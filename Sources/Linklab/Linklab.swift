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
            // Even if no host, we process it to return unrecognized
            processIncomingURL(url, host: "")
            return true
        }

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
           // Retrieve the current link data to be returned.
           let linkDataToReturn = currentLinkData
           
           // Clear the stored link data to prevent it from being returned again.
           self.currentLinkData = nil
           
           // Return the retrieved data.
           return linkDataToReturn
       }
    
    // MARK: - Private Methods
    
    /// Checks if the URL is a LinkLab URL and initiates fetching details if it is.
    /// - Parameter url: The incoming URL.
    /// - Parameter host: The lowercased host extracted from the URL.
    private func processIncomingURL(_ url: URL, host: String) {
        guard let apiService = apiService else {
            Logger.error("Linklab not initialized or APIService is missing.")
            // Here we fall back to unrecognized if SDK is not ready but we want to fail open?
            // Usually if not initialized we can't really do much, but following your logic:
            notifyCallback(with: LinkData.unrecognized(url: url))
            return
        }

        // Extract the last path component as the potential link ID
        let linkId = url.lastPathComponent
        
        // Validation: If no ID or ID is just root, treat as unrecognized immediately
        if linkId.isEmpty || linkId == "/" {
             Logger.debug("URL does not contain a valid ID, treating as unrecognized: \(url.absoluteString)")
             notifyCallback(with: LinkData.unrecognized(url: url))
             return
        }

        let domain = host

        Logger.debug("Extracted LinkID: \(linkId), Domain: \(domain)")

        // Call the API service to fetch link details
        apiService.fetchLinkDetails(linkId: linkId, domain: domain) { [weak self] result in
             // Hop back to main actor for UI updates / callback
             Task { @MainActor [weak self] in
                 guard let self = self else { return }
                 switch result {
                 case .success(let linkData):
                      Logger.info("Successfully fetched link data for ID \(linkId)")
                      self.notifyCallback(with: linkData)
                      
                 case .failure(let error):
                      // CHANGED: Instead of returning error, we assume it's not a LinkLab link
                      // or the link is broken/expired/offline. We fall back to unrecognized.
                      Logger.info("API request failed (Error: \(error.localizedDescription)). Treating as unrecognized link.")
                      
                      let fallbackData = LinkData.unrecognized(url: url)
                      self.notifyCallback(with: fallbackData)
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
            guard self.attributionService is AttributionService else {
                 Logger.debug("AttributionService not available or wrong type initially.")
                return
            }
        
            if installationTracker.isFirstLaunch() {
                 Logger.info("First launch detected. Checking for deferred deep link.")
                 
                 guard let attributionService = self.attributionService as? AttributionService else {
                     Logger.error("AttributionService not available when checking for deferred deep link.")
                     return
                 }
                 
                 Task { [attributionService] in
                     do {
                          Logger.debug("Requesting deferred deep link based on IP address...")
                         
                          try await attributionService.fetchDeferredDeepLink() { result in
                              Task { @MainActor [weak self] in
                                  guard let self = self else { return }
                                  switch result {
                                  case .success(let linkData):
                                       Logger.info("Successfully fetched deferred link data.")
                                       self.notifyCallback(with: linkData)
                                  case .failure(let error):
                                       Logger.error("Failed to fetch deferred deep link: \(error.localizedDescription)")
                                       // For deferred deep links, if it fails, we usually simply don't trigger anything,
                                       // or we could trigger unrecognized if we really wanted to, but usually silence is better here
                                       // unless there is a specific URL involved (which there isn't, just IP).
                                       self.notifyCallback(with: nil, error: error)
                                  }
                              }
                         }
                     } catch {
                          Logger.error("Failed to fetch deferred deep link: \(error.localizedDescription)")
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
        if Thread.isMainThread {
             // Prioritize returning linkData (even if it's unrecognized) over error
             if let linkData = linkData {
                  currentLinkData = linkData
                  Logger.debug("Notifying callback with LinkData: id=\(linkData.id ?? "nil"), domainType=\(linkData.domainType)")
                  deepLinkCallback?(linkData)
             } else if let error = error {
                  Logger.error("Notifying callback with error: \(error.localizedDescription)")
                  deepLinkCallback?(nil)
             }
        } else {
            Task { @MainActor [weak self] in
                self?.notifyCallback(with: linkData, error: error)
            }
        }
    }
}
