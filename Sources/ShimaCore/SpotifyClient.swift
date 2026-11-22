@MainActor public protocol SpotifyClient: AnyObject {
    var onEvent: (@MainActor (SpotifyEvent) -> Void)? { get set }
    func refresh()
    func send(_ command: SpotifyCommand)
    func invalidate()
}
