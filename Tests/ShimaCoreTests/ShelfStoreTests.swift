import Foundation
import Testing
@testable import ShimaCore

@Suite @MainActor struct ShelfStoreTests {
    private func files(_ range: Range<Int>) -> [DroppedEntry] {
        range.map { DroppedEntry(fileURL: URL(fileURLWithPath: "/tmp/file-\($0).txt")) }
    }

    @Test func addsFileTextAndLink() {
        let store = ShelfStore()
        let file = URL(fileURLWithPath: "/tmp/a.txt")
        let link = URL(string: "https://example.com/page")!
        let now = Date(timeIntervalSince1970: 123)
        let result = store.add([
            DroppedEntry(fileURL: file), DroppedEntry(string: "  Hello  \nSecond line"), DroppedEntry(url: link)
        ], now: now)
        #expect(result.added == 3)
        #expect(result.refused == 0)
        #expect(store.items.map(\.kind) == [.file(file), .text("  Hello  \nSecond line"), .link(link)])
        #expect(store.items.map(\.name) == ["a.txt", "Hello", "example.com/page"])
        #expect(store.items.allSatisfy { $0.added == now })
        #expect(!store.isFull)
    }

    @Test func duplicateFileURLIgnoredAndNotCounted() {
        let store = ShelfStore()
        let entry = files(0..<1)[0]
        #expect(store.add([entry, entry]).added == 1)
        let result = store.add([entry])
        #expect(result.added == 0)
        #expect(result.refused == 0)
        #expect(store.items.count == 1)
        store.add(files(1..<20))
        let overflow = files(20..<21)[0]
        let fullResult = store.add([overflow, overflow, entry])
        #expect(fullResult.added == 0)
        #expect(fullResult.refused == 1)
    }

    @Test func batchFillsToCapAndRefusesRest() {
        let store = ShelfStore()
        store.add(files(0..<18))
        let original = store.items
        let result = store.add(files(18..<23))
        #expect(result.added == 2)
        #expect(result.refused == 3)
        #expect(store.items.count == ShelfStore.cap)
        #expect(store.isFull)
        #expect(Array(store.items.prefix(18)) == original)

        store.clear()
        store.add(files(0..<18))
        let thirty = store.add(files(18..<48))
        #expect(thirty.added == 2)
        #expect(thirty.refused == 28)
        #expect(store.items.count == 20)
    }

    @Test func thirtyFileBatchOntoEmptyStoreAdds20Refuses10() {
        let store = ShelfStore()
        let result = store.add(files(0..<30))
        #expect(result.added == 20)
        #expect(result.refused == 10)
        #expect(store.isFull)
    }

    @Test func refusedCountsOnlyItemsThatDidNotFit() {
        let store = ShelfStore()
        store.add(files(0..<19))
        let newFile = files(19..<20)[0]
        let result = store.add([
            files(0..<1)[0], DroppedEntry(), DroppedEntry(string: ""),
            DroppedEntry(string: "\n \t"), DroppedEntry(url: URL(string: "ftp://example.com")!),
            newFile, newFile, DroppedEntry(string: "does not fit")
        ])
        #expect(result.added == 1)
        #expect(result.refused == 1)
        #expect(store.items.count == 20)
        #expect(store.add([files(0..<1)[0]]).refused == 0)
    }

    @Test func removeAndClear() {
        let store = ShelfStore()
        store.add(files(0..<20))
        let first = store.items[0].id
        let remaining = Array(store.items.dropFirst())
        store.remove(id: first)
        #expect(store.items == remaining)
        #expect(!store.isFull)
        store.remove(id: UUID())
        #expect(store.items == remaining)
        store.clear()
        #expect(store.items.isEmpty)
        #expect(!store.isFull)
    }

    @Test func nameIsBoundedAndNonEmpty() {
        let store = ShelfStore()
        let longText = String(repeating: "🙂", count: 5_000)
        let unicodeName = "文書📁.txt"
        store.add([
            DroppedEntry(string: longText),
            DroppedEntry(fileURL: URL(fileURLWithPath: "/tmp/Folder/", isDirectory: true)),
            DroppedEntry(fileURL: URL(fileURLWithPath: "/tmp/\(unicodeName)")),
            DroppedEntry(string: "\nActual text"),
            DroppedEntry(fileURL: URL(fileURLWithPath: "/")),
            DroppedEntry(url: URL(string: "https://example.com/" + String(repeating: "a", count: 100))!),
            DroppedEntry(fileURL: URL(fileURLWithPath: "/tmp/" + String(repeating: "文", count: 100)))
        ])
        #expect(store.items.count == 7)
        #expect(store.items.allSatisfy { !$0.name.isEmpty && $0.name.count <= 60 })
        #expect(store.items[0].name == String(repeating: "🙂", count: 59) + "…")
        #expect(store.items[1].name == "Folder")
        #expect(store.items[2].name == unicodeName)
    }

    @Test func idsComeFromInjectedFactory() {
        let store = ShelfStore()
        let ids = [UUID(), UUID()]
        var calls = 0
        let entry = files(0..<1)[0]
        store.add([DroppedEntry(), entry, entry, DroppedEntry(string: "text")], makeID: {
            defer { calls += 1 }
            return ids[calls]
        })
        #expect(calls == 2)
        #expect(store.items.map(\.id) == ids)
        store.add(files(1..<19))
        var refusedCalls = 0
        let refused = store.add([DroppedEntry(string: "full")], makeID: {
            refusedCalls += 1
            return UUID()
        })
        #expect(refused.refused == 1)
        #expect(refusedCalls == 0)
    }
}
