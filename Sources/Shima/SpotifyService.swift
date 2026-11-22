import AppKit
import ShimaCore

/// Owns the Spotify client and coordinator. This task: fake mode only (SHIMA_FAKE_SPOTIFY).
@MainActor
final class SpotifyService: NSObject {
    var onLiveChange: (@MainActor (Bool) -> Void)?
    var onFakeEqualizerMode: (@MainActor (EqualizerMode) -> Void)?

    private let state: AppState
    private let media: IslandMedia
    private let environment: [String: String]
    private var fake: FakeSpotifyClient?
    private var observers: SpotifyObservers?
    private var coordinator: SpotifyCoordinator?

    init(state: AppState, media: IslandMedia,
         environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.state = state
        self.media = media
        self.environment = environment
        super.init()
    }

    func start() {
        guard let initial = FakeSpotifyMode.initialState(environment["SHIMA_FAKE_SPOTIFY"]) else {
            startReal()
            return
        }
        let client = FakeSpotifyClient(state: initial)
        client.onEvent = { [weak self] in self?.receive($0) }
        attach(client)
        fake = client
        Log.spotify.info("spotify mode fake state=\(String(describing: initial), privacy: .public)")
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(fakeControl(_:)), name: .init("local.shima.fake-spotify"),
            object: nil, suspensionBehavior: .deliverImmediately)
        receive(.launched)
        client.refresh()
    }

    /// Real mode. Observers first, so a launch between here and the running check is not missed.
    /// No Apple Event is sent unless Spotify is already running.
    private func startReal() {
        let client = SpotifyAppleEventClient()
        client.onEvent = { [weak self] in self?.receive($0) }  // before the first refresh()
        attach(client)
        let observers = SpotifyObservers(onEvent: { [weak self] in self?.receive($0) })
        observers.start()
        self.observers = observers
        let running = SpotifyAppleEventClient.spotifyPID() != nil
        Log.spotify.info("spotify mode real running=\(running, privacy: .public)")
        if running {
            receive(.launched)
            client.refresh()
        }
    }

    private func attach(_ client: any SpotifyClient) {
        let coordinator = SpotifyCoordinator(client: client, state: state, scheduler: DispatchScheduler())
        coordinator.onLiveChange = { [weak self] live in
            Log.spotify.info("spotify live \(live, privacy: .public)")
            self?.onLiveChange?(live)
        }
        coordinator.onChanges = { changes in
            Log.spotify.info("spotify changes \(String(describing: changes), privacy: .public)")
        }
        self.coordinator = coordinator
    }

    func islandOpened() { coordinator?.islandOpened() }

    func perform(_ command: SpotifyCommand) { coordinator?.perform(command) }

    /// The single funnel for client and observer events: log (never title or artist), then apply.
    func receive(_ event: SpotifyEvent) {
        switch event {
        case .launched: Log.spotify.info("spotify event launched")
        case .terminated: Log.spotify.info("spotify event terminated")
        case .permissionDenied: Log.spotify.info("spotify event permissionDenied")
        case .refreshFailed: Log.spotify.info("spotify event refreshFailed")
        case let .commandSucceeded(command): Log.spotify.info("spotify event commandSucceeded \(command.rawValue, privacy: .public)")
        case let .reading(reading, source, _):
            let src = source == .notification ? "notification" : "script"
            Log.spotify.info("spotify event reading src=\(src, privacy: .public) state=\(String(describing: reading.state), privacy: .public) track=\(reading.trackID ?? "none", privacy: .public)")
        }
        coordinator?.handle(event)
    }

    @objc nonisolated private func fakeControl(_ note: Notification) {
        let cmd = (note.object as? String) ?? ""
        MainActor.assumeIsolated { handleFake(cmd) }
    }

    private func handleFake(_ cmd: String) {
        switch cmd {
        case "ping": Log.spotify.info("fake ping")
        case "playing": Log.spotify.info("fake playing"); fake?.setState(.playing)
        case "paused": Log.spotify.info("fake paused"); fake?.setState(.paused)
        case "next": Log.spotify.info("fake next"); fake?.send(.next)
        case "previous": Log.spotify.info("fake previous"); fake?.send(.previous)
        case "quit": Log.spotify.info("fake quit"); receive(.terminated)
        case "launch": Log.spotify.info("fake launch"); receive(.launched)
        case "eq-frozen": Log.spotify.info("fake eq-frozen"); media.equalizerFrozen = true
        case "eq-animating": Log.spotify.info("fake eq-animating"); media.equalizerFrozen = false
        case "denied": Log.spotify.info("fake denied"); receive(.permissionDenied)
        case "allowed": Log.spotify.info("fake allowed"); fake?.refresh()
        case let c where c.hasPrefix("eq-mode-"):
            if let mode = EqualizerMode(rawValue: String(c.dropFirst("eq-mode-".count))) {
                Log.spotify.info("fake \(c, privacy: .public)")
                onFakeEqualizerMode?(mode)
            } else {
                Log.spotify.info("fake unknown \(c, privacy: .public)")
            }
        default: Log.spotify.info("fake unknown \(cmd, privacy: .public)")
        }
    }
}
