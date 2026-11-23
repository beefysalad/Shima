import AppKit
import Testing
@testable import Shima
@testable import ShimaCore

@MainActor private final class Board {
    let pb = NSPasteboard(name: NSPasteboard.Name("local.shima.test.\(UUID().uuidString)"))
    isolated deinit { pb.releaseGlobally() }

    func text(_ s: String) {
        pb.clearContents()
        pb.writeObjects([s as NSString])
    }
    func files(_ paths: [String]) {
        pb.clearContents()
        pb.writeObjects(paths.map { URL(fileURLWithPath: $0) as NSURL })
    }
}

@MainActor private struct Rig {
    let view = HoverTrackingView(frame: CGRect(x: 0, y: 0, width: 436, height: 208))
    let store = ShelfStore()
    var events: Events

    @MainActor final class Events { var list: [ShelfDragEvent] = []; var locations: [CGPoint?] = [] }

    init() {
        let events = Events()
        self.events = events
        view.onDragEvent = { events.list.append($0) }
        view.onDragLocation = { events.locations.append($0) }
        let store = self.store
        view.onDrop = { store.add($0) }
    }
}

@MainActor @Suite(.serialized) struct HoverTrackingViewDragTests {
    @Test func enteredReportsEntered() {
        let rig = Rig(); let b = Board(); b.text("hello")
        #expect(rig.view.handleEntered(pasteboard: b.pb) == .copy)
        #expect(rig.events.list == [.entered])
        #expect(rig.view.handleUpdated(viewPoint: CGPoint(x: 218, y: 108)) == .copy)
        #expect(rig.events.locations.last == CGPoint(x: 200, y: 100))
    }

    @Test func dropAddsItemsAndReturnsResult() {
        let rig = Rig(); let b = Board(); b.files(["/tmp/shima-drag-a.txt", "/tmp/shima-drag-b.txt"])
        _ = rig.view.handleEntered(pasteboard: b.pb)
        #expect(rig.view.handlePerform(pasteboard: b.pb))
        #expect(rig.store.items.count == 2)
    }

    @Test func dropWhenFullReportsRefused() {
        let rig = Rig(); let b = Board()
        rig.store.add((0..<ShelfStore.cap).map { DroppedEntry(string: "t\($0)") })
        b.text("one more")
        _ = rig.view.handleEntered(pasteboard: b.pb)
        #expect(rig.view.handlePerform(pasteboard: b.pb)) // refused > 0 still counts as handled
        #expect(rig.store.items.count == ShelfStore.cap)
    }

    @Test func exitedReportsExited() {
        let rig = Rig(); let b = Board(); b.text("x")
        _ = rig.view.handleEntered(pasteboard: b.pb)
        rig.view.handleExited()
        #expect(rig.events.list == [.entered, .exited])
        #expect(rig.events.locations.last! == nil)
    }

    @Test func endedReportsDroppedFlagOnce() {
        let rig = Rig(); let b = Board(); b.text("x")
        _ = rig.view.handleEntered(pasteboard: b.pb)
        _ = rig.view.handlePerform(pasteboard: b.pb)
        rig.view.handleEnded()
        rig.view.handleEnded()
        #expect(rig.events.list == [.entered, .ended(dropped: true)])
        // A new session starts clean: a cancelled drag reports dropped false.
        _ = rig.view.handleEntered(pasteboard: b.pb)
        rig.view.handleEnded()
        #expect(rig.events.list.last == .ended(dropped: false))
    }

    @Test func unsupportedTypesAreRejected() {
        let rig = Rig(); let b = Board()
        b.pb.clearContents()
        b.pb.setData(Data([1, 2, 3]), forType: NSPasteboard.PasteboardType("com.example.opaque"))
        #expect(rig.view.handleEntered(pasteboard: b.pb) == [])
        #expect(rig.events.list.isEmpty)
        #expect(!rig.view.handlePerform(pasteboard: b.pb))
        #expect(rig.store.items.isEmpty)
    }

    @Test func ownChipDragIsIgnored() {
        let rig = Rig(); let b = Board(); b.text("chip")
        OwnDrag.active = true
        defer { OwnDrag.active = false }
        #expect(rig.view.handleEntered(pasteboard: b.pb) == [])
        OwnDrag.active = false // the flag clearing mid-session must not revive the session
        rig.view.handleExited()
        #expect(!rig.view.handlePerform(pasteboard: b.pb))
        rig.view.handleEnded()
        #expect(rig.events.list.isEmpty)
        #expect(rig.store.items.isEmpty)
    }

    @Test func refusedEntryResetsStaleSessionState() {
        let rig = Rig(); let b = Board(); b.text("hello")
        // A previous session was dropped but its draggingEnded never arrived.
        #expect(rig.view.handleEntered(pasteboard: b.pb) == .copy)
        #expect(rig.view.handlePerform(pasteboard: b.pb))
        rig.events.list.removeAll()
        // The next drag is refused (own chip drag); stale state must not leak into later events.
        OwnDrag.active = true
        defer { OwnDrag.active = false }
        #expect(rig.view.handleEntered(pasteboard: b.pb) == [])
        rig.view.handleExited()
        rig.view.handleEnded()
        #expect(rig.events.list.isEmpty)
    }

    @Test func dragFromThisAppSourceIsRefusedEvenWithoutTheFlag() {
        let rig = Rig(); let b = Board(); b.text("chip")
        OwnDrag.active = false
        #expect(rig.view.handleEntered(pasteboard: b.pb, fromThisApp: true) == [])
        #expect(rig.events.list.isEmpty)
    }

    @Test func registersForDragTypesInAWindow() {
        let rig = Rig()
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = rig.view
        #expect(rig.view.registeredDraggedTypes.contains(.fileURL))
        #expect(rig.view.registeredDraggedTypes.contains(.URL))
        #expect(rig.view.registeredDraggedTypes.contains(.string))
    }
}

@MainActor struct DroppedEntryReaderTests {
    @Test func oneEntryPerPasteboardItem() {
        let b = Board()
        b.pb.clearContents()
        let file = NSPasteboardItem(); file.setString(URL(fileURLWithPath: "/tmp/a.pdf").absoluteString, forType: .fileURL)
        let link = NSPasteboardItem()
        link.setString("https://example.com/x", forType: .URL); link.setString("https://example.com/x", forType: .string)
        let text = NSPasteboardItem(); text.setString("hello", forType: .string)
        b.pb.writeObjects([file, link, text])
        let entries = DroppedEntryReader.entries(from: b.pb)
        #expect(entries.count == 3)
        #expect(entries[0].fileURL == URL(fileURLWithPath: "/tmp/a.pdf"))
        #expect(entries[1].url == URL(string: "https://example.com/x") && entries[1].string == "https://example.com/x")
        #expect(entries[2] == DroppedEntry(string: "hello"))
    }

    @Test func emptyAndUnsupportedItemsYieldNothing() {
        let b = Board()
        b.pb.clearContents()
        #expect(DroppedEntryReader.entries(from: b.pb).isEmpty)
        b.pb.setData(Data([1]), forType: NSPasteboard.PasteboardType("com.example.opaque"))
        #expect(DroppedEntryReader.entries(from: b.pb).isEmpty)
    }
}
