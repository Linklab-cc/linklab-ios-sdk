# Linklab iOS SDK

Swift SDK for [Linklab](https://linklab.cc) deep links: resolves universal links on `linklab.cc`, `<yourapp>.linklab.cc`
and your custom domains, and recovers deferred deep links after install (pasteboard or IP attribution).

Field names and behaviour match the Linklab Android and Flutter SDKs.

## Requirements

- iOS 14.3+
- Swift 5.9+ / Xcode 15+

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/Linklab-cc/linklab-ios-sdk.git", from: "0.3.0")
]
```

Or in Xcode: File > Add Package Dependencies… and paste the repository URL.

### CocoaPods

```ruby
pod 'Linklab', '~> 0.3.0'
```

## Quick start

Initialize once, as early as possible, and register the callbacks:

```swift
import Linklab

let config = LinklabConfiguration(
    customDomains: ["go.example.com"],   // optional, domains you registered with Linklab
    pasteboardMode: .automatic           // .automatic (default) | .manual | .disabled
)

Linklab.shared.initialize(
    with: config,
    onLink: { link in
        // Every resolved / unrecognized / failed link arrives here exactly once.
        route(to: link)
    },
    onError: { error in
        // Failures of the deferred check or checkPasteboard(). Optional.
        print("Linklab:", error.localizedDescription)
    }
)
```

Then forward every URL your app receives to `Linklab.shared.handleIncomingURL(_:)`. It returns `true` when the URL
is a Linklab link and is being processed, and `false` (delivering nothing) for any other URL, so you can chain your
own handlers.

### Entry points

**SceneDelegate** (cold start and warm start):

```swift
func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    for activity in connectionOptions.userActivities where activity.activityType == NSUserActivityTypeBrowsingWeb {
        if let url = activity.webpageURL {
            Linklab.shared.handleIncomingURL(url)
        }
    }
}

func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
          let url = userActivity.webpageURL else { return }
    if !Linklab.shared.handleIncomingURL(url) {
        // Not a Linklab link: hand it to your other handlers.
    }
}
```

**AppDelegate** (no scenes):

```swift
func application(_ application: UIApplication,
                 continue userActivity: NSUserActivity,
                 restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
    guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
          let url = userActivity.webpageURL else { return false }
    return Linklab.shared.handleIncomingURL(url)
}
```

**SwiftUI**:

```swift
@main
struct MyApp: App {
    init() {
        Linklab.shared.initialize(with: LinklabConfiguration(), onLink: { link in
            Router.shared.handle(link)
        })
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    Linklab.shared.handleIncomingURL(url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL {
                        Linklab.shared.handleIncomingURL(url)
                    }
                }
        }
    }
}
```

`Linklab.shared` is `@MainActor`; call it from the main thread (all of the above already are).

### Chaining with other handlers

```swift
if Linklab.shared.isLinklabLink(url) {
    Linklab.shared.handleIncomingURL(url)
} else {
    otherSDK.handle(url)
}
```

A URL is a Linklab link iff its scheme is http(s) and its host is `linklab.cc`, a subdomain of `linklab.cc`, or one
of `customDomains` (case-insensitive). URLs received before `initialize(with:)` are queued and processed, in order,
when `initialize(with:)` runs; the return value before initialization reflects only the built-in hosts because custom
domains are not known yet — initialize early.

### Universal links / AASA

Add the Associated Domains capability with `applinks:<yourapp>.linklab.cc` (and `applinks:go.example.com` for each
custom domain). The `apple-app-site-association` file is served automatically by Linklab for `<yourapp>.linklab.cc`
and for custom domains pointed at Linklab; you do not host it yourself.

## Receiving links

`onLink` receives a `LinkData` for every incoming Linklab URL, exactly once per URL. If the same URL is opened again
while the first is still resolving, the duplicate is ignored; after completion, re-opening processes it again.

If a link is delivered while `onLink` is `nil`, it is stored and replayed once to the first `onLink` you set.

```swift
Linklab.shared.lastLink          // most recent link (non-destructive); also getLinkData()
await Linklab.shared.getInitialLink()
```

`getInitialLink()` returns the **first** link delivered in this process. It waits (up to 5 s) for `initialize(with:)`
if needed, then for any in-flight resolution and for the deferred check, and never triggers a callback.

### LinkData

| field | type | notes |
|---|---|---|
| `id` | `String?` | server link id; `nil` for unrecognized / failed |
| `fullLink` | `String` | destination URL; for unrecognized / failed = the URL as received |
| `shortLink` | `String?` | the URL as received (universal link / clipboard URL); `nil` for IP attribution |
| `createdAt`, `updatedAt` | `Date?` | |
| `packageName`, `bundleId`, `appStoreId` | `String?` | |
| `domain` | `String?` | host |
| `domainType` | `String` | `"linklab"` \| `"custom"` \| `"unrecognized"` |
| `parameters` | `[String: String]` | query parameters of `fullLink` (URL-decoded), overridden by server parameters |
| `resolutionStatus` | `String` | `"resolved"` \| `"unrecognized"` \| `"failed"` |
| `errorMessage` | `String?` | set when `resolutionStatus == "failed"` |
| `isDeferred` | `Bool` | `true` for pasteboard / IP attribution results |
| `matchType` | `String` | `"direct"` \| `"clipboard"` \| `"ipAddress"` \| `"installReferrer"` \| `"none"` |

Resolution rules for a URL on a Linklab host:

- root path (`https://go.example.com/?promo=X`) → `unrecognized` immediately, no network; `parameters` holds the query
- `GET /links/{id}` 200 → `resolved`
- 404 → `unrecognized`
- network error / timeout / 5xx after retries, or decoding failure → `failed` with `errorMessage`

Unrecognized and failed results still carry `fullLink` and `parameters`, so custom-domain landing pages with only
query parameters reach your app.

## Deferred deep linking

On first launch the SDK tries to recover the link the user tapped before installing. The check is a persisted state
machine: it runs while the state is `pending`, at most 3 attempts within 24 h of first launch, and becomes `done` on
any definitive outcome (link delivered, nothing found, 4xx, decoding error). Transient failures (network errors, 5xx)
count as an attempt and are retried on the next launch. Nothing found is normal and is **not** reported to `onError`.

### Pasteboard (`pasteboardMode`)

Linklab's landing page can copy a link to the pasteboard before sending the user to the App Store. The SDK accepts a
full Linklab URL (host must pass the host check above) or the legacy token `linklab_<id>_<domainType>_<domain>`.

- `.automatic` (default): reads the pasteboard **at most once per install**, inside the first-launch check. Before
  reading it verifies `UIPasteboard.general.hasStrings` and, on iOS 15+, asks `detectPatterns(for: [\.probableWebURL])`
  (which does not trigger the paste banner). If a URL is detected it is read; otherwise (no URL pattern, or iOS 14
  where the Swift `detectPatterns` API is unavailable) the pasteboard is still read once to support the legacy token,
  which may show the iOS paste banner one time. The "checked" flag is persisted regardless of
  outcome.
- `.manual`: the SDK never reads automatically. After an explicit user action call

  ```swift
  let link = await Linklab.shared.checkPasteboard()
  ```

  It applies the same gates, reads at most once per call, and both **returns** the link and **delivers** it through
  `onLink`. Pass `checkPasteboard(deliver: false)` to only get the return value.
- `.disabled`: the pasteboard is never read.

### IP attribution fallback

When the pasteboard yields nothing (or the mode is not `.automatic`), the SDK calls `POST /apple-attribution` with
`osVersion`, `deviceModel`, `locale`, `timeZone` and `bundleId`. A match is delivered with `matchType == "ipAddress"`;
404 means no deferred link and completes the state machine.

## Configuration

| property | default | |
|---|---|---|
| `customDomains` | `[]` | custom domains registered with Linklab |
| `debugLoggingEnabled` | `false` | logs through `os.Logger` (subsystem `cc.linklab.sdk`); query strings are never logged |
| `networkTimeout` | `10` | seconds per request |
| `networkRetryCount` | `3` | retries for network errors / 5xx with 0.5 s, 1 s, 2 s backoff; 4xx is never retried |
| `baseURL` | `https://linklab.cc` | |
| `pasteboardMode` | `.automatic` | see above |

`Configuration` remains available as a type alias of `LinklabConfiguration`.

## Privacy manifest

The package ships `PrivacyInfo.xcprivacy` (SPM resource / CocoaPods resource bundle) declaring UserDefaults access
(reason `CA92.1`) and no tracking. The SDK sends the device's OS version, model, locale, time zone and bundle id to
Linklab for deferred attribution; declare whatever applies in your app's own privacy nutrition label.

## Migration from 0.2.x

- `LinkData.rawLink` → `fullLink` (`rawLink` still compiles, deprecated). `userId` is gone. New fields:
  `shortLink`, `parameters`, `resolutionStatus`, `errorMessage`, `isDeferred`, `matchType`.
- `initialize(with:deepLinkCallback:)` → `initialize(with:onLink:onError:)`. The old overload still works (deprecated)
  and bridges to `onLink`.
- `handleIncomingURL(_:)` now returns `false` and delivers nothing for non-Linklab URLs and custom schemes. If you
  relied on receiving an `unrecognized` result for every URL, handle foreign URLs yourself when it returns `false`.
- `getLinkData()` is no longer cleared after reading. `getInitialLink()` returns the first link of the process.
- `Configuration` → `LinklabConfiguration` (alias kept). Default timeout is 10 s instead of 30 s. The public `Logger`
  type is gone; use `debugLoggingEnabled`.
- `domainType` `"default"` is now reported as `"linklab"`.
- The pasteboard is read at most once per install (previously on every first-launch attempt). Choose `.manual` or
  `.disabled` if you do not want the automatic read.
- The deferred check is bounded to 3 attempts / 24 h. Installs that already completed it on 0.2.x are migrated to
  `done`.

## License

Apache 2.0 — see `LICENSE`.
