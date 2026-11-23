/// True while a drag that this app started (a shelf chip) is in flight. The drop destination ignores such
/// drags (spike 3: the island otherwise receives its own chip drags). The chip drag source sets it.
@MainActor enum OwnDrag {
    static var active = false
}
