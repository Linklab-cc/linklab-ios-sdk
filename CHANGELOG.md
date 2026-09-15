# Changelog

## 0.3.0

Cross-platform alignment release. The public model and callback API now match the Linklab Android and Flutter SDKs.

### Breaking changes

- `LinkData.rawLink` is deprecated in favour of `fullLink` (kept as a deprecated computed property for one release).
- `LinkData` gained `shortLink`, `parameters` (non-optional, query parameters of `fullLink` merged with server
  parameters), `resolutionStatus`, `errorMessage`, `isDeferred` and `matchType`. Its memberwise initializer changed.
- `LinkData.userId` was removed. The value is ignored when decoding.
- `domainType` now maps the server value `"default"` (or a missing value on a linklab.cc host) to `"linklab"`.
- `initialize(with:deepLinkCallback:)` is deprecated. Use `initialize(with:onLink:onError:)` or set
  `Linklab.shared.onLink` / `Linklab.shared.onError` directly. The deprecated overload bridges to `onLink`.
- `handleIncomingURL(_:)` now returns `false` and delivers nothing for URLs that are not on `linklab.cc`, a
  subdomain of it, or a configured custom domain, and for non-http(s) schemes. Previously every URL produced an
  `unrecognized` result.
- `getLinkData()` is no longer destructive; it returns the last delivered link every time.
- `getInitialLink()` returns the first link delivered in this process (waits for initialization and in-flight work,
  capped at 5 s) and never triggers a callback.
- `Configuration` was renamed to `LinklabConfiguration`; `Configuration` remains as a type alias. Its initializer no
  longer toggles logging as a side effect; the flag is applied by `initialize(with:)`. Default `networkTimeout` is
  now 10 s (was 30 s). New fields: `baseURL`, `pasteboardMode`.
- The public `Logger` type was removed; logging is internal, goes through `os.Logger` and is emitted only when
  `debugLoggingEnabled` is set. Query strings are never logged.
- `LinkError` was trimmed to the cases the SDK actually produces; `.notInitialized` and `.notLinklabLink` added.
- `UniversalLinkHandler` (unused) was removed. `handleUniversalLink(_:)` remains as a deprecated forwarder.
- The test target folder is now `Tests/LinklabTests` (case-sensitive match with the target name).

### New

- `PasteboardMode` (`.automatic` default, `.manual`, `.disabled`) controls pasteboard access for deferred deep
  linking. Automatic mode reads at most once per install, gated by `hasStrings` and `detectPatterns`. Manual mode
  exposes `checkPasteboard(deliver:)`. (`detectPatterns` is used on iOS 15+; iOS 14 falls back to a single read.) A full Linklab URL on the pasteboard is accepted in addition to the legacy
  `linklab_<id>_<type>_<domain>` token.
- Deferred check is a persisted state machine bounded to 3 attempts within 24 h (`linklab_deferred_state`,
  `linklab_deferred_attempts`, `linklab_first_launch_at`). The legacy `linklab_first_launch_key` is migrated to
  `done`.
- Requests carry `Accept`, `User-Agent`, `X-Linklab-Sdk` and `X-Linklab-App` headers, honour `networkTimeout` and
  retry network errors / 5xx with 0.5 s, 1 s, 2 s backoff (`networkRetryCount`).
- Late `onLink` registration replays the last undelivered link once.
- `isLinklabLink(_:)` for chaining with other URL handlers.
- `PrivacyInfo.xcprivacy` privacy manifest (UserDefaults, reason CA92.1) shipped with SPM and CocoaPods.
- macOS 12 added to the package platforms so `swift test` runs on macOS; the SDK itself targets iOS 14.3+.

## 0.2.4 and earlier

See git history.
