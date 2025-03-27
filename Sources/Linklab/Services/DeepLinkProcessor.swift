import Foundation

class DeepLinkProcessor {
    /// Process deep link parameters and return a destination
    /// - Parameter params: Deep link parameters
    /// - Returns: LinkDestination object
    func processDeepLink(params: [String: String]) -> LinkDestination {
        // Extract the route path (if any)
        let route = params["route"] ?? ""
        
        // Filter out the route from parameters to pass along
        var parameters = params
        parameters.removeValue(forKey: "route")
        
        return LinkDestination(route: route, parameters: parameters)
    }
}
