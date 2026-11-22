import AppKit
import Observation

/// Non-Sendable-model glue state shared by the island views: the artwork image and the equalizer freeze flag.
@Observable @MainActor
final class IslandMedia {
    var artwork: NSImage? = nil
    var equalizerFrozen = false
}
