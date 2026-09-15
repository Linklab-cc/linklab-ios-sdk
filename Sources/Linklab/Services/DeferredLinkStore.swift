import Foundation

/// Persists the deferred-attribution state machine (contract rule 9) in `UserDefaults`.
final class DeferredLinkStore {
    enum Keys {
        static let state = "linklab_deferred_state"
        static let attempts = "linklab_deferred_attempts"
        static let firstLaunchAt = "linklab_first_launch_at"
        static let pasteboardChecked = "linklab_pasteboard_checked"
        static let pasteboardCandidate = "linklab_pasteboard_candidate"
        /// Pre-0.3 key. Any value means the deferred check already completed.
        static let legacyFirstLaunch = "linklab_first_launch_key"
    }

    enum State: String { case pending, done }

    static let maxAttempts = 3
    static let window: TimeInterval = 24 * 60 * 60

    private let defaults: UserDefaults
    private let now: () -> Date

    init(userDefaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = userDefaults
        self.now = now
        migrateLegacyKeyIfNeeded()
    }

    private func migrateLegacyKeyIfNeeded() {
        guard defaults.object(forKey: Keys.legacyFirstLaunch) != nil else { return }
        if defaults.string(forKey: Keys.state) == nil {
            defaults.set(State.done.rawValue, forKey: Keys.state)
        }
        defaults.removeObject(forKey: Keys.legacyFirstLaunch)
    }

    var state: State {
        get { State(rawValue: defaults.string(forKey: Keys.state) ?? "") ?? .pending }
        set { defaults.set(newValue.rawValue, forKey: Keys.state) }
    }

    var attempts: Int {
        get { defaults.integer(forKey: Keys.attempts) }
        set { defaults.set(newValue, forKey: Keys.attempts) }
    }

    /// Set on first access.
    var firstLaunchAt: Date {
        if let millis = defaults.object(forKey: Keys.firstLaunchAt) as? Double {
            return Date(timeIntervalSince1970: millis / 1000)
        }
        let date = now()
        defaults.set(date.timeIntervalSince1970 * 1000, forKey: Keys.firstLaunchAt)
        return date
    }

    var pasteboardChecked: Bool {
        get { defaults.bool(forKey: Keys.pasteboardChecked) }
        set { defaults.set(newValue, forKey: Keys.pasteboardChecked) }
    }

    /// A pasteboard candidate kept across launches so a transient failure can be retried without reading again.
    var pasteboardCandidate: PasteboardCandidate? {
        get {
            guard let data = defaults.data(forKey: Keys.pasteboardCandidate) else { return nil }
            return try? JSONDecoder().decode(PasteboardCandidate.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.pasteboardCandidate)
            } else {
                defaults.removeObject(forKey: Keys.pasteboardCandidate)
            }
        }
    }

    /// `true` when the deferred check should run now. Marks `done` when the bound is exhausted.
    func shouldRunDeferredCheck() -> Bool {
        guard state == .pending else { return false }
        let start = firstLaunchAt // stamps the first launch on first access
        let elapsed = now().timeIntervalSince(start)
        if attempts >= Self.maxAttempts || elapsed >= Self.window {
            markDone()
            return false
        }
        return true
    }

    func markDone() {
        state = .done
        pasteboardCandidate = nil
    }

    /// Transient failure: count the attempt; the bound is enforced on the next `shouldRunDeferredCheck()`.
    func recordTransientFailure() {
        attempts += 1
        if attempts >= Self.maxAttempts { markDone() }
    }
}
