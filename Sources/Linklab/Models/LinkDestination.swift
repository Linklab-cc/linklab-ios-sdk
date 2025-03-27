import Foundation

public struct LinkDestination {
    /// The route path to navigate to in the app
    public let route: String
    
    /// Additional parameters to pass to the destination
    public let parameters: [String: String]
    
    public init(route: String, parameters: [String: String] = [:]) {
        self.route = route
        self.parameters = parameters
    }
}
