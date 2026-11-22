import Testing
@testable import ShimaCore

@Suite @MainActor struct SettingsStoreTests {
    @Test func devicePopupsDefaultOnForMissingAndUnknownValues() {
        #expect(SettingsStore(storage: InMemoryPreferenceStorage()).devicePopups)
        let storage = InMemoryPreferenceStorage(["devicePopups": "unknown"])
        #expect(SettingsStore(storage: storage).devicePopups)
        #expect(storage.writes == 0)
    }

    @Test func devicePopupsRoundTripThroughStorage() {
        let storage = InMemoryPreferenceStorage()
        let store = SettingsStore(storage: storage)
        store.setDevicePopups(false)
        store.setDevicePopups(false)
        #expect(storage.values == ["devicePopups": "off"] && storage.writes == 1)
        #expect(!SettingsStore(storage: storage).devicePopups)
        store.setDevicePopups(true)
        #expect(storage.values == ["devicePopups": "on"] && storage.writes == 2)
        #expect(SettingsStore(storage: storage).devicePopups)
    }

    @Test func defaultsToAnimatedWhenEmpty() {
        #expect(SettingsStore(storage: InMemoryPreferenceStorage()).equalizerMode == .animated)
    }

    @Test func readsStoredMode() {
        #expect(SettingsStore(storage: InMemoryPreferenceStorage(["equalizerMode": "whenOpen"])).equalizerMode == .whenOpen)
    }

    @Test func setWritesRawValueUnderTheKey() {
        let storage = InMemoryPreferenceStorage()
        let store = SettingsStore(storage: storage)
        store.setEqualizerMode(.off)
        #expect(storage.values == ["equalizerMode": "off"] && storage.writes == 1 && store.equalizerMode == .off)
    }

    @Test func settingTheSameModeDoesNotWrite() {
        let storage = InMemoryPreferenceStorage(["equalizerMode": "off"])
        SettingsStore(storage: storage).setEqualizerMode(.off)
        #expect(storage.writes == 0)
    }

    @Test func unknownStoredValueReadsAsDefaultAndIsReplacedOnlyOnSet() {
        let storage = InMemoryPreferenceStorage(["equalizerMode": "loud"])
        let store = SettingsStore(storage: storage)
        #expect(store.equalizerMode == .animated && storage.writes == 0)
        store.setEqualizerMode(.animated)
        #expect(storage.values["equalizerMode"] == "animated" && storage.writes == 1)
    }

    @Test func onlyTheShimaBundleUsesStandardDefaults() {
        #expect(SettingsStore.suiteName == "local.shima" && SettingsStore.equalizerModeKey == "equalizerMode")
        #expect(SettingsStore.usesStandardDefaults(bundleIdentifier: "local.shima"))
        #expect(!SettingsStore.usesStandardDefaults(bundleIdentifier: nil))
        #expect(!SettingsStore.usesStandardDefaults(bundleIdentifier: "com.apple.dt.xctest.tool"))
    }

    @Test func readsCurrentStorageWithoutCachingOrWriting() {
        let storage = InMemoryPreferenceStorage(["equalizerMode": "whenOpen"])
        let store = SettingsStore(storage: storage)
        #expect(store.equalizerMode == .whenOpen)
        storage.setString("off", forKey: "equalizerMode")
        #expect(store.equalizerMode == .off)
        storage.setString("unknown", forKey: "equalizerMode")
        #expect(store.equalizerMode == .animated)
        #expect(storage.writes == 2)
        #expect(storage.values == ["equalizerMode": "unknown"])
    }

    @Test func missingDefaultIsWrittenOnlyWhenExplicitlySet() {
        let storage = InMemoryPreferenceStorage()
        let store = SettingsStore(storage: storage)
        #expect(store.equalizerMode == .animated)
        #expect(store.equalizerMode == .animated)
        #expect(storage.values.isEmpty && storage.writes == 0)
        store.setEqualizerMode(.animated)
        #expect(storage.values == ["equalizerMode": "animated"] && storage.writes == 1)
        store.setEqualizerMode(.animated)
        #expect(storage.writes == 1)
    }
}
