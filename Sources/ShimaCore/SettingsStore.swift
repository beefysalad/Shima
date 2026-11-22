import Foundation

/// String key-value storage behind the settings: UserDefaults in the app, in memory in tests.
@MainActor public protocol PreferenceStorage: AnyObject {
    func string(forKey key: String) -> String?
    func setString(_ value: String, forKey key: String)
}

@MainActor public final class InMemoryPreferenceStorage: PreferenceStorage {
    public private(set) var values: [String: String]
    public private(set) var writes = 0

    public init(_ values: [String: String] = [:]) { self.values = values }

    public func string(forKey key: String) -> String? { values[key] }

    public func setString(_ value: String, forKey key: String) {
        values[key] = value
        writes += 1
    }
}

@MainActor public final class UserDefaultsPreferenceStorage: PreferenceStorage {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) { self.defaults = defaults }

    /// Inside Shima.app (bundle id `local.shima`) the standard defaults already are the `local.shima`
    /// domain, and a suite named like the own bundle id only logs a warning. Elsewhere use the suite.
    public static func forShima(bundleIdentifier: String?) -> UserDefaultsPreferenceStorage {
        if SettingsStore.usesStandardDefaults(bundleIdentifier: bundleIdentifier) {
            return UserDefaultsPreferenceStorage(defaults: .standard)
        }
        return UserDefaultsPreferenceStorage(defaults: UserDefaults(suiteName: SettingsStore.suiteName) ?? .standard)
    }

    public func string(forKey key: String) -> String? { defaults.string(forKey: key) }

    public func setString(_ value: String, forKey key: String) { defaults.set(value, forKey: key) }
}

/// UI preferences (design: UserDefaults now; `~/.config/shima/config.json` stays reserved for M4 automations).
@MainActor public final class SettingsStore {
    public static let suiteName = "local.shima"
    public static let equalizerModeKey = "equalizerMode"

    private let storage: PreferenceStorage

    public init(storage: PreferenceStorage) { self.storage = storage }

    public static func usesStandardDefaults(bundleIdentifier: String?) -> Bool {
        bundleIdentifier == suiteName
    }

    public var equalizerMode: EqualizerMode {
        EqualizerMode(stored: storage.string(forKey: Self.equalizerModeKey))
    }

    public func setEqualizerMode(_ mode: EqualizerMode) {
        guard storage.string(forKey: Self.equalizerModeKey) != mode.rawValue else { return }
        storage.setString(mode.rawValue, forKey: Self.equalizerModeKey)
    }
}
