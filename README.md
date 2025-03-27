# Linklab iOS SDK

A Swift library for handling deferred deep links on iOS. This SDK allows your app to identify what link it was installed from and handle Universal Links appropriately.

## Features

- Detect new app installations
- Handle Universal Links
- Retrieve attribution tokens from StoreKit
- Process deferred deep links
- Route to appropriate screens in your app
- Integration with Linklab Redirector service

## Requirements

- iOS 14.0+
- Swift 5.0+
- Xcode 13.0+

## Installation

### Swift Package Manager

The Linklab SDK can be installed via Swift Package Manager. Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/your-organization/linklab-ios-sdk.git", from: "1.0.0")
]
```

Or add it directly in Xcode using File > Add Packages.

## Usage

### Initialization

Initialize the SDK in your AppDelegate or SceneDelegate:

```swift
import Linklab

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    // Initialize Linklab
    let config = Configuration(
        debugLoggingEnabled: true
    )
    
    Linklab.shared.initialize(with: config) { destination in
        if let destination = destination {
            // Handle deep link destination
            navigateToDestination(destination)
        }
    }
    
    return true
}

// Helper method to navigate to the deep link destination
func navigateToDestination(_ destination: LinkDestination) {
    // Handle routing based on destination.route and destination.parameters
    // For example:
    switch destination.route {
    case "products":
        if let productId = destination.parameters["id"] {
            navigateToProduct(productId)
        }
    case "categories":
        if let categoryId = destination.parameters["id"] {
            navigateToCategory(categoryId)
        }
    default:
        // Handle unknown routes or navigate to home screen
        break
    }
}
```

### Handling Universal Links

Implement the following method in your SceneDelegate:

```swift
func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
       let url = userActivity.webpageURL {
        Linklab.shared.handleUniversalLink(url)
    }
}
```

### Setting up Universal Links

1. Configure your app for Universal Links by adding the Associated Domains capability
2. Add the appropriate domain to your entitlements file
3. Set up the `apple-app-site-association` file on your server

## Redirector Service Integration

The Linklab iOS SDK works with the Linklab Redirector service at `https://linklab.cc` according to its OpenAPI specification. The API URL is hardcoded in the SDK, so you don't need to provide it during initialization.

### Apple Attribution Endpoint

The SDK communicates with the `/apple-attribution` endpoint to process Apple attribution tokens for deferred deep linking:

- **Endpoint**: POST https://linklab.cc/apple-attribution
- **Request Body**: 
  ```json
  {
    "attributionToken": "token-from-apple"
  }
  ```
- **Response**: The SDK processes the Link data returned by the API, extracting both the link properties and any query parameters from the full URL to create a LinkDestination object.

This integration enables:
- First-launch attribution tracking
- Deferred deep linking to specific content
- Parameter passing from acquisition links to the app

## License

See the LICENSE file for details.
