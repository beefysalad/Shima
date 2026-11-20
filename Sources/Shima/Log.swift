import os

enum Log {
    static let hover = Logger(subsystem: "local.shima", category: "hover")
    static let layout = Logger(subsystem: "local.shima", category: "layout")
    static let display = Logger(subsystem: "local.shima", category: "display")
    static let menu = Logger(subsystem: "local.shima", category: "menu")
}
