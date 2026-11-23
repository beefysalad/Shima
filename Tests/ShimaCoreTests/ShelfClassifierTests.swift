import Foundation
import Testing
@testable import ShimaCore

@Suite struct ShelfClassifierTests {
    @Test func fileURLBecomesFile() {
        let url = URL(fileURLWithPath: "/tmp/a.txt")
        #expect(ShelfClassifier.classify(DroppedEntry(fileURL: url)) == .file(url))
    }

    @Test func directoryIsAFile() {
        let url = URL(fileURLWithPath: "/tmp/Folder/", isDirectory: true)
        #expect(ShelfClassifier.classify(DroppedEntry(fileURL: url)) == .file(url))
    }

    @Test func httpsURLBecomesLink() {
        for scheme in ["http", "https"] {
            let url = URL(string: "\(scheme)://example.com/page")!
            #expect(ShelfClassifier.classify(DroppedEntry(url: url)) == .link(url))
        }
    }

    @Test func stringThatParsesAsHttpURLBecomesLink() {
        let string = "https://example.com/page"
        #expect(ShelfClassifier.classify(DroppedEntry(string: string)) == .link(URL(string: string)!))
    }

    @Test func whitespaceAroundHttpURLStringStillBecomesLink() {
        let entry = DroppedEntry(string: "  https://example.com/page\n")
        #expect(ShelfClassifier.classify(entry) == .link(URL(string: "https://example.com/page")!))
    }

    @Test func hugeTextIsTruncatedToTheCap() {
        let huge = String(repeating: "a", count: ShelfClassifier.maxTextLength + 50_000)
        guard case .text(let stored)? = ShelfClassifier.classify(DroppedEntry(string: huge)) else {
            Issue.record("expected text"); return
        }
        #expect(stored.count == ShelfClassifier.maxTextLength)
    }

    @Test func plainStringBecomesText() {
        #expect(ShelfClassifier.classify(DroppedEntry(string: "hello world")) == .text("hello world"))
    }

    @Test func fileURLWinsOverStringAndURL() {
        let file = URL(fileURLWithPath: "/tmp/a.txt")
        let link = URL(string: "https://example.com")!
        #expect(ShelfClassifier.classify(DroppedEntry(fileURL: file, url: link, string: "hello")) == .file(file))
        #expect(ShelfClassifier.classify(DroppedEntry(url: link, string: "hello")) == .link(link))
    }

    @Test func otherSchemeIsIgnored() {
        for string in ["mailto:person@example.com", "ftp://example.com/file"] {
            #expect(ShelfClassifier.classify(DroppedEntry(url: URL(string: string)!)) == nil)
        }
    }

    @Test func emptyAndWhitespaceStringIsIgnored() {
        for string in ["", " ", "\n\t\r  "] {
            #expect(ShelfClassifier.classify(DroppedEntry(string: string)) == nil)
        }
    }

    @Test func nilWhenEntryIsEmpty() {
        #expect(ShelfClassifier.classify(DroppedEntry()) == nil)
    }
}
