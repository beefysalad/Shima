import Observation

@Observable @MainActor public final class AppState {
    public var mode: IslandMode = .collapsed

    public init() {}
}
