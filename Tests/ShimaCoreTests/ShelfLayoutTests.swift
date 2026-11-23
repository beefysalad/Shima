import Foundation
import CoreGraphics
import Testing
@testable import ShimaCore

struct ShelfLayoutTests {
    private let island = CGRect(x: 0, y: 0, width: IslandLayout.expanded.width, height: IslandLayout.expanded.height)

    @Test func rectsMatchTheApprovedMockup() {
        #expect(ShelfLayout.veil == CGRect(x: 0, y: 32, width: 440, height: 168))
        #expect(ShelfLayout.veilTileRow == CGRect(x: 0, y: 52, width: 440, height: 96))
        #expect(ShelfLayout.veilTile == CGRect(x: 140, y: 52, width: 160, height: 96))
        #expect(ShelfLayout.veilTileRadius == 14)
        #expect(ShelfLayout.veilIcon == CGRect(x: 206, y: 70, width: 28, height: 28))
        #expect(ShelfLayout.veilCaption == CGRect(x: 140, y: 110, width: 160, height: 16))
        #expect(ShelfLayout.veilCount == CGRect(x: 12, y: 156, width: 416, height: 16))
        #expect(ShelfLayout.chipRow == CGRect(x: 14, y: 44, width: 412, height: 64))
        #expect(ShelfLayout.chipSize == CGSize(width: 116, height: 64))
        #expect(ShelfLayout.chipRadius == 10)
        #expect(ShelfLayout.chipGap == 8)
        #expect(ShelfLayout.emptyState == CGRect(x: 14, y: 44, width: 412, height: 88))
        #expect(ShelfLayout.statusLine == CGRect(x: 14, y: 116, width: 412, height: 16))
        #expect(ShelfLayout.countLabel == CGRect(x: 14, y: 166, width: 200, height: 20))
        #expect(ShelfLayout.clearButton == CGRect(x: 366, y: 166, width: 60, height: 22))
    }

    @Test func everyRectIsInsideTheIsland() {
        let rects = [ShelfLayout.veil, ShelfLayout.veilTileRow, ShelfLayout.veilTile, ShelfLayout.veilIcon, ShelfLayout.veilCaption,
                     ShelfLayout.veilCount, ShelfLayout.chipRow, ShelfLayout.emptyState, ShelfLayout.statusLine,
                     ShelfLayout.countLabel, ShelfLayout.clearButton, ShelfLayout.chipRemove(chipX: 14, chipY: 44)]
        for r in rects { #expect(island.contains(r)) }
    }

    @Test func chipRemoveButtonSitsInTheChipCorner() {
        let chip = CGRect(x: 14, y: 44, width: 116, height: 64)
        let x = ShelfLayout.chipRemove(chipX: chip.minX, chipY: chip.minY)
        #expect(x == CGRect(x: 110, y: 48, width: 16, height: 16))
        #expect(chip.contains(x))
    }

    @Test func homeContentSitsBelowTheHeaderStrip() {
        for r in [ShelfLayout.chipRow, ShelfLayout.emptyState, ShelfLayout.statusLine, ShelfLayout.countLabel, ShelfLayout.clearButton] {
            #expect(r.minY > 32)
        }
        #expect(ShelfLayout.countLabel.maxX <= ShelfLayout.clearButton.minX)
    }

    @Test func tabsEndByX106AndGearClearsTheNotch() {
        #expect(NowPlayingLayout.tabRect(.calendar).maxX == 106)
        let notch = CGRect(x: 130.5, y: 0, width: 179, height: 32)
        #expect(!NowPlayingLayout.settingsButton.intersects(notch))
        for tab in IslandTab.allCases { #expect(!NowPlayingLayout.tabRect(tab).intersects(notch)) }
    }

    @Test func dotSitsAtTheTopRightOfTheHomeIcon() {
        let dot = ShelfLayout.homeDot
        let home = NowPlayingLayout.tabRect(.home)
        #expect(dot.width == 6 && home.contains(dot))
        #expect(dot.maxX == home.maxX - 3 && dot.minY == home.minY + 3)
    }
}

struct ShelfTextTests {
    @Test func fixedStrings() {
        #expect(ShelfText.emptyState == "Drop files, text or links here")
        #expect(ShelfText.veilCaption == "Drop to add to shelf")
        #expect(ShelfText.veilCaptionFull == "Shelf full (20)")
        #expect(ShelfText.clear == "Clear")
        #expect(ShelfText.remove == "Remove")
        #expect(ShelfText.cleared == "Shelf cleared")
        #expect(ShelfText.homeDotTooltip == "Shelf has items")
    }

    @Test func veilCount() {
        #expect(ShelfText.veilCount(0) == "0 of 20")
        #expect(ShelfText.veilCount(7) == "7 of 20")
    }

    @Test func homeCountPluralises() {
        #expect(ShelfText.homeCount(0) == "No items")
        #expect(ShelfText.homeCount(1) == "1 item")
        #expect(ShelfText.homeCount(2) == "2 items")
        #expect(ShelfText.homeCount(20) == "20 items")
    }

    @Test func addedMessage() {
        #expect(ShelfText.added(added: 3, refused: 0) == "Added 3")
        #expect(ShelfText.added(added: 2, refused: 5) == "Added 2, 5 did not fit")
        #expect(ShelfText.added(added: 0, refused: 4) == "Added 0, 4 did not fit")
    }

    @Test func fileSizes() {
        #expect(ShelfText.fileSize(512) == "512 B")
        #expect(ShelfText.fileSize(2048) == "2.0 KB")
        #expect(ShelfText.fileSize(20480) == "20 KB")
        #expect(ShelfText.fileSize(5 * 1_048_576) == "5.0 MB")
    }

    @Test func badgeAndSubline() throws {
        let file = ShelfItem(kind: .file(URL(fileURLWithPath: "/tmp/report.PDF")))
        let text = ShelfItem(kind: .text("hello"))
        let link = ShelfItem(kind: .link(try #require(URL(string: "https://example.com/a"))))
        #expect(ShelfText.badge(file) == "pdf")
        #expect(ShelfText.badge(text) == "text")
        #expect(ShelfText.badge(link) == "link")
        #expect(ShelfText.badge(ShelfItem(kind: .file(URL(fileURLWithPath: "/tmp/Makefile")))) == "file")
        #expect(ShelfText.subline(text, fileSize: nil) == "Text")
        #expect(ShelfText.subline(link, fileSize: nil) == "example.com")
        #expect(ShelfText.subline(file, fileSize: 2048) == "2.0 KB")
        #expect(ShelfText.subline(file, fileSize: nil) == "0 B")
    }
}

struct ShelfLayoutVeilHitTests {
    @Test func veilTileHitTestInsideOutsideAndEdges() {
        #expect(ShelfLayout.isOverVeilTile(CGPoint(x: 220, y: 100)))
        #expect(ShelfLayout.isOverVeilTile(CGPoint(x: 140, y: 52)))
        #expect(ShelfLayout.isOverVeilTile(CGPoint(x: 299.9, y: 147.9)))
        #expect(!ShelfLayout.isOverVeilTile(CGPoint(x: 300, y: 100)))
        #expect(!ShelfLayout.isOverVeilTile(CGPoint(x: 220, y: 148)))
        #expect(!ShelfLayout.isOverVeilTile(CGPoint(x: 139.9, y: 100)))
        #expect(!ShelfLayout.isOverVeilTile(CGPoint(x: 220, y: 51.9)))
        #expect(!ShelfLayout.isOverVeilTile(CGPoint(x: 10, y: 10)))
    }

    @Test func panelPointConvertsToIslandSpace() {
        let size = CGSize(width: 476, height: 208)
        // Non-flipped: y counts from the bottom, so the panel's top edge is island y 0.
        #expect(ShelfLayout.islandPoint(fromPanelPoint: CGPoint(x: 18, y: 208), panelSize: size, flipped: false) == .zero)
        #expect(ShelfLayout.islandPoint(fromPanelPoint: CGPoint(x: 238, y: 108), panelSize: size, flipped: false) == CGPoint(x: 220, y: 100))
        #expect(ShelfLayout.islandPoint(fromPanelPoint: CGPoint(x: 238, y: 100), panelSize: size, flipped: true) == CGPoint(x: 220, y: 100))
        #expect(ShelfLayout.islandPoint(fromPanelPoint: CGPoint(x: 0, y: 208), panelSize: size, flipped: false) == CGPoint(x: -18, y: 0))
    }

    @Test func panelCentreMapsToTheIslandCentre() {
        let e = IslandLayout.expanded
        let size = CGSize(width: e.width + 2 * e.earRadius + 2 * IslandLayout.hoverMargin, height: e.height + IslandLayout.hoverMargin)
        #expect(size == CGSize(width: 476, height: 208))
        let p = ShelfLayout.islandPoint(fromPanelPoint: CGPoint(x: size.width / 2, y: 50), panelSize: size, flipped: true)
        #expect(p == CGPoint(x: 220, y: 50))
    }
}
