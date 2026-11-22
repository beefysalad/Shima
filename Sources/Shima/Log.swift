import os

enum Log {
    static let camera = Logger(subsystem: "local.shima", category: "camera")
    static let hover = Logger(subsystem: "local.shima", category: "hover")
    static let layout = Logger(subsystem: "local.shima", category: "layout")
    static let display = Logger(subsystem: "local.shima", category: "display")
    static let menu = Logger(subsystem: "local.shima", category: "menu")
    static let spotify = Logger(subsystem: "local.shima", category: "spotify")
    static let artwork = Logger(subsystem: "local.shima", category: "artwork")
    static let eq = Logger(subsystem: "local.shima", category: "eq")
    static let focus = Logger(subsystem: "local.shima", category: "focus")
    static let settings = Logger(subsystem: "local.shima", category: "settings")
}
