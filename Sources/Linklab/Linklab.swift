import Foundation
import StoreKit
import AdServices

#if canImport(AdServices)
#endif

@available(iOS 14.3, macOS 11.1, *)
@MainActor
public class Linklab {
    // Define constants for LinkLab domain
    private static let linklabHost = "linklab.cc"
    
    public static let shared = Linklab()
    
    private var configuration: Configuration?
    private var installationTracker: InstallationTracker?
    private var apiService: APIService?
    // Using Any type for macOS compatibility - will be downcast when used
    private var attributionService: Any?
    
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
        self.apiService = APIService()
        if #available(macOS 12.0, *) {
            self.attributionService = AttributionService()
        }
        
        // Check for deferred deep link if this is a new installation
        checkForDeferredDeepLink()
    }
    
    /// Handle an incoming URL (Universal Link or Custom Scheme)
    /// - Parameter url: The URL that was opened
    /// - Returns: Boolean indicating whether the URL was identified as a LinkLab link and is being processed.
    @discardableResult
    public func handleIncomingURL(_ url: URL) -> Bool {
        guard let host = url.host else {
            Logger.debug("Incoming URL has no host: \(url.absoluteString)")
            return false
        }

        // Check if it's a linklab.cc or a subdomain of linklab.cc
        if host == Self.linklabHost || host.hasSuffix(".\(Self.linklabHost)") {
            Logger.debug("Handling LinkLab URL: \(url.absoluteString)")
            processIncomingURL(url)
            return true // Indicate that we are processing this URL
        } else {
            Logger.debug("URL is not a LinkLab URL: \(url.absoluteString)")
            return false // Not a LinkLab URL
        }
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
    
    // MARK: - Private Methods
    
    /// Checks if the URL is a LinkLab URL and initiates fetching details if it is.
    private func processIncomingURL(_ url: URL) {
        guard let apiService = apiService else {
            Logger.error("Linklab not initialized or APIService is missing.")
            notifyCallback(with: nil, error: LinkError.notInitialized)
            return
        }

        guard let host = url.host else {
            Logger.error("Cannot process URL without a host: \(url.absoluteString)")
            notifyCallback(with: nil, error: LinkError.invalidURL("URL has no host."))
            return
        }

        // Extract the last path component as the potential link ID
        let linkId = url.lastPathComponent
        guard !linkId.isEmpty && linkId != "/" else { // Ensure lastPathComponent is not empty or just "/"
             Logger.error("Cannot extract link ID from URL: \(url.absoluteString)")
             notifyCallback(with: nil, error: LinkError.invalidURL("Cannot extract link ID."))
             return
        }

        // Determine domain type
        let domainType = (host == Self.linklabHost) ? "rootDomain" : "subDomain"
        let domain = host

        Logger.debug("Extracted LinkID: \(linkId), DomainType: \(domainType), Domain: \(domain)")

        // Call the API service to fetch link details
        apiService.fetchLinkDetails(linkId: linkId, domainType: domainType, domain: domain) { [weak self] result in
             DispatchQueue.main.async { // Ensure callback is on the main thread
                 switch result {
                 case .success(let linkData):
                      Logger.info("Successfully fetched link data for ID \(linkId)")
                      // Convert LinkData to LinkDestination
                      // Use the fullLink string as the route and extract parameters
                      let (route, params) = self?.extractRouteAndParams(from: linkData.fullLink) ?? (linkData.fullLink, [:])
                      let destination = LinkDestination(route: route, parameters: params)
                      self?.notifyCallback(with: destination)
                 case .failure(let error):
                      Logger.error("Failed to fetch link details for ID \(linkId): \(error.localizedDescription)")
                      self?.notifyCallback(with: nil, error: error)
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
            guard let attributionService = attributionService as? AttributionService else {
                 Logger.debug("AttributionService not available.")
                return
            }
        
            // Check if this is a new installation
            if installationTracker.isFirstLaunch() {
                 Logger.info("First launch detected. Checking for deferred deep link.")
                // Request attribution token from AdServices
                #if canImport(AdServices)
                 // Ensure service is accessible from MainActor context before Task
                 guard let attributionService = self.attributionService as? AttributionService else {
                     // Already on MainActor, safe to log and return
                     Logger.error("AttributionService not available when checking for deferred deep link.")
                     return
                 }
                 
                 // Task runs detached from MainActor
                 Task { 
                     // No need to capture self weakly here if we hop back explicitly later
                     // Or keep it weak if preferred for memory management, but MainActor hop is key
                     
                     do {
                          Logger.debug("Requesting AdServices attribution token...")
                         // The attributionToken() method is not async in AdServices
                         let token = try AdServices.AAAttribution.attributionToken()
                          Logger.debug("Received AdServices attribution token.")
                         
                         // Send token to attribution service - fetchDeferredDeepLink is async
                          try await attributionService.fetchDeferredDeepLink(token: token) { result in
                              // Completion handler may run on any thread. Hop back to MainActor.
                              Task { @MainActor [weak self] in // Explicitly run callback logic on MainActor
                                  guard let self = self else { return } // Safely unwrap self
                                  switch result {
                                  case .success(let linkData): 
                                       Logger.info("Successfully fetched deferred link data.")
                                       // Convert LinkData to LinkDestination - safe on MainActor
                                        let (route, params) = self.extractRouteAndParams(from: linkData.fullLink)
                                        let destination = LinkDestination(route: route, parameters: params)
                                        self.notifyCallback(with: destination) // Safe on MainActor
                                  case .failure(let error):
                                       Logger.error("Failed to fetch deferred deep link: \(error.localizedDescription)")
                                       self.notifyCallback(with: nil, error: error) // Safe on MainActor
                                  }
                              }
                         }
                     } catch {
                          Logger.error("Failed to get attribution token: \(error.localizedDescription)")
                          // Hop back to MainActor to call notifyCallback safely
                          Task { @MainActor [weak self] in
                              self?.notifyCallback(with: nil, error: LinkError.attributionError(error))
                          }
                     }
                 }
                 #else // AdServices not available
                  // This code now runs on the MainActor because the class is @MainActor
                  Logger.error("AdServices framework not available. Cannot fetch deferred deep link.")
                  // Direct call is safe as we are already on MainActor
                   self.notifyCallback(with: nil, error: LinkError.featureNotAvailable("AdServices"))
                 #endif
            } else {
                 Logger.debug("Not first launch. Skipping deferred deep link check.")
            }
        } else {
            Logger.error("macOS version too old for AttributionService.")
        }
    }

    /// Helper function to extract route path and query parameters from a URL string.
    private func extractRouteAndParams(from urlString: String) -> (route: String, params: [String: String]) {
        guard let components = URLComponents(string: urlString) else {
            Logger.error("Could not parse URL string to extract route and params: \(urlString)")
            return (urlString, [:]) // Return original string if parsing fails
        }
        
        let route = components.path
        var params: [String: String] = [:]
        
        components.queryItems?.forEach { item in
            params[item.name] = item.value ?? ""
        }
        
        return (route, params)
    }

    /// Helper to safely call the deep link callback on the main thread.
    private func notifyCallback(with destination: LinkDestination? = nil, error: Error? = nil) {
        // Ensure execution on the main thread
        if Thread.isMainThread {
             if let error = error {
                  // Optionally, enhance LinkDestination or callback to include errors
                  Logger.error("Notifying callback with error: \(error.localizedDescription)")
                  deepLinkCallback?(nil) // Or pass error info if callback signature changes
             } else {
                  Logger.debug("Notifying callback with destination route: \(destination?.route ?? "nil"), params: \(destination?.parameters ?? [:])")
                  deepLinkCallback?(destination)
             }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.notifyCallback(with: destination, error: error)
            }
        }
    }
}
