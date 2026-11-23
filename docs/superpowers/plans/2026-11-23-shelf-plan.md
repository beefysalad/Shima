# Shelf and Home tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drag files, text and links onto the island, keep them on a shelf shown on a new Home tab, and drag them back out.

**Architecture:** Pure logic (`ShelfStore`, drop classification, hover-machine drag inputs) lives in `ShimaCore` with Swift Testing tests. The panel's content view (`HoverTrackingView`) is the AppKit drag destination and feeds `HoverController` and `ShelfStore`. Home and the drag veil are SwiftUI overlays with explicit frames. Real drags cannot be injected from a terminal, so a fake shelf service drives automated checks and real drags are HUMAN tasks.

**Tech Stack:** Swift 6.4.2, SwiftPM, macOS 14+, SwiftUI + AppKit, Swift Testing (`import Testing`, no XCTest), no new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-23-shelf-design.md`

## Global Constraints

- SwiftPM only, no `.xcodeproj`; no third-party dependencies.
- `ShimaCore` must not import AppKit; logic in `ShimaCore` with tests, glue in `Shima`.
- `mockup/index.html` is the approved UI: it changes first and the user approves it before UI code (Task 6).
- Nothing may enlarge the island's root `ZStack`: Home content and the veil are `.overlay(alignment: .top)` with explicit frames.
- The panel never takes focus; no timers or polling while idle; idle RSS bar is 80 MB plus flat growth over 20 open/close cycles.
- Shelf cap is 20; duplicates (same file URL) are ignored and do not count toward the cap; a batch fills to the cap and the rest is refused.
- Tab order Home, Music, Camera, Calendar; icons on a 24 pt pitch from x 12 (last ends at 106; the notch is x 110.5..289.5). Music is the default tab and collapse snaps back to Music.
- Settings gear: right wing, expanded header only, `CGRect(x: 366, y: 5, width: 22, height: 22)`.
- Never launch or command the user's Spotify; never `pkill -x Shima` (kill by pid); never commit signing identifiers or `.build`/`dist`.
- No tool-attribution trailers except the one the repo hook allows; stage explicit paths, never `git add -A`.
- Codex tasks: Codex does not commit; Claude reviews the diff and commits. Codex runs unsandboxed, so each brief names the exact files it may touch.

## Review Focus

Inputs the spec implies but no happy-path test covers, most likely first. Each has a pinning test in the owning task.

1. A drag enters during a peek: the peek must cancel and the island expand (Task 2).
2. Drag exits and re-enters within the leave debounce, and a stale `collapseFinished` arrives after re-entry: the island must stay open (Task 2).
3. A cancelled drag outside the island, delivering only `dragExited` or only `dragEnded(dropped: false)`: the island must collapse either way (Task 2).
4. The same file dropped twice, a 30-file batch onto 18 stored, and an empty or whitespace-only string: no duplicates, exactly 2 added, nothing added (Task 1).
5. A very long text snippet and a file name with Unicode or a trailing slash (folder): chip name must be bounded and non-empty (Task 1).

---

## Task 1: Shelf model and drop classification (PURE, Codex)

**Files:**
- Create: `Sources/ShimaCore/ShelfItem.swift`, `Sources/ShimaCore/ShelfClassifier.swift`, `Sources/ShimaCore/ShelfStore.swift`
- Test: `Tests/ShimaCoreTests/ShelfClassifierTests.swift`, `Tests/ShimaCoreTests/ShelfStoreTests.swift`

**Interfaces:**
- Produces:
  - `public enum ShelfItemKind: Equatable, Sendable { case file(URL), text(String), link(URL) }`
  - `public struct ShelfItem: Equatable, Identifiable, Sendable { public let id: UUID; public let kind: ShelfItemKind; public let name: String; public let added: Date }`
  - `public struct DroppedEntry: Equatable, Sendable { public var fileURL: URL?; public var url: URL?; public var string: String?; public init(fileURL: URL? = nil, url: URL? = nil, string: String? = nil) }` (one pasteboard item)
  - `public enum ShelfClassifier { public static func classify(_ entry: DroppedEntry) -> ShelfItemKind? }`
  - `public struct ShelfAddResult: Equatable, Sendable { public let added: Int; public let refused: Int }`
  - `@MainActor @Observable public final class ShelfStore { public static let cap = 20; public private(set) var items: [ShelfItem]; public var isFull: Bool; public init(); public func add(_ entries: [DroppedEntry], now: Date = Date(), makeID: () -> UUID = UUID.init) -> ShelfAddResult; public func remove(id: UUID); public func clear() }`

- [ ] **Step 1: Write failing classifier tests.** Names and assertions: `fileURLBecomesFile` (`DroppedEntry(fileURL: URL(fileURLWithPath: "/tmp/a.txt"))` gives `.file`), `directoryIsAFile`, `httpsURLBecomesLink`, `stringThatParsesAsHttpURLBecomesLink`, `plainStringBecomesText`, `fileURLWinsOverStringAndURL`, `otherSchemeIsIgnored` (`mailto:`/`ftp:` gives nil), `emptyAndWhitespaceStringIsIgnored`, `nilWhenEntryIsEmpty`.
- [ ] **Step 2: Run** `swift test --filter ShelfClassifierTests`. Expected: FAIL, symbols not defined.
- [ ] **Step 3: Implement `ShelfClassifier.classify`** with precedence file URL, then `http(s)` URL, then string that parses as an `http(s)` URL, then non-blank string, else nil.
- [ ] **Step 4: Write failing store tests.** `addsFileTextAndLink`, `duplicateFileURLIgnoredAndNotCounted`, `batchFillsToCapAndRefusesRest` (18 stored, add 5 gives `added == 2, refused == 3`), `thirtyFileBatchOntoEmptyStoreAdds20Refuses10`, `refusedCountsOnlyItemsThatDidNotFit`, `removeAndClear`, `nameIsBoundedAndNonEmpty` (a 5,000-character snippet gives a name of at most 60 characters; a `/tmp/Folder/` URL gives `Folder`; a Unicode file name is kept), `idsComeFromInjectedFactory`.
- [ ] **Step 5: Run** `swift test --filter ShelfStoreTests`. Expected: FAIL.
- [ ] **Step 6: Implement `ShelfStore` and `ShelfItem` naming.** Name rule: file/folder last path component; link host plus path; text first line trimmed. Truncate to 60 with an ellipsis.
- [ ] **Step 7: Run** `swift test`. Expected: all pass.
- [ ] **Step 8: Brief and hand off.** Claude writes the brief (exact files above only; no commit; report with `hc send t1d` when done), runs `hc send t1f` from the worktree. Claude reviews `git diff`, runs `swift test`, commits `feat: shelf model and drop classification`.

## Task 2: Hover machine drag inputs (PURE, Codex)

**Files:**
- Modify: `Sources/ShimaCore/HoverMachine.swift`, `Sources/ShimaCore/HoverController.swift`
- Test: `Tests/ShimaCoreTests/HoverMachineTests.swift`, `Tests/ShimaCoreTests/HoverControllerTests.swift`

**Interfaces:**
- Produces: `HoverPhase.dragHovering`; `HoverInput.dragEntered`, `.dragExited`, `.dragEnded(dropped: Bool)`; `HoverController.dragEntered()`, `.dragExited()`, `.dragEnded(dropped: Bool)`. No new effects: reuse `growPanel`, `setHotRegion(.expanded)`, `animateExpand`, `startTimer(.leave)`, `cancelTimer`.
- Behaviour: `dragEntered` from any phase except `dragHovering` cancels any timer, grows the panel if not already large, sets the expanded hot region, animates expand, and enters `.dragHovering` with the pointer treated as inside. `dragExited` and `dragEnded(dropped: false)` enter `.leaving` and start the leave timer. `dragEnded(dropped: true)` enters `.expanded`. `reset` clears the drag state.

- [ ] **Step 1: Write failing reducer tests** (before any implementation, as the device-popups spec required). Names: `dragEnteredFromCollapsedGrowsAndExpands`, `dragEnteredDuringPeekCancelsPeek`, `dragEnteredDuringDwellingExpands`, `dragExitedStartsLeaveDebounce`, `dragReenterWithinDebounceStaysOpen`, `staleCollapseFinishedAfterReenterIsIgnored`, `dragEndedDroppedStaysExpanded`, `dragEndedNotDroppedCollapsesAfterLeaveDebounce`, `onlyDragExitedStillCollapses`, `onlyDragEndedStillCollapses`, `resetClearsDragState`, `pointerEventsDuringDragAreIgnored`. Assertions use `phase` and the returned `[HoverEffect]`, with `ManualScheduler` in the controller tests.
- [ ] **Step 2: Run** `swift test --filter Hover`. Expected: FAIL.
- [ ] **Step 3: Implement the three inputs** in `HoverMachine.handle`, with a private `dragActive` flag so `pointer(inside:)` changes are ignored while it is true.
- [ ] **Step 4: Add the three `HoverController` wrappers** mirroring `pointer(inside:)`.
- [ ] **Step 5: Run** `swift test`. Expected: all pass, including the pre-existing hover tests unchanged.
- [ ] **Step 6: Hand off to Codex** as in Task 1 step 8; commit `feat: hover machine drag-hover inputs`.

## Task 3: Spikes with real drags (GLUE throwaway, then HUMAN)

Gates Tasks 7 to 9, not Tasks 1 and 2. Throwaway code on branch `shelf-spike`, never merged.

**Files:**
- Create: `docs/superpowers/spikes/2026-11-23-shelf-spikes.md`
- Modify (throwaway): `Sources/Shima/HoverTrackingView.swift`

- [ ] **Step 1: Register the view for `.fileURL`, `.URL`, `.string`** and log `draggingEntered`, `draggingExited`, `draggingEnded` and `performDragOperation` through `Log`.
- [ ] **Step 2: Build and run** with `scripts/run.sh` (fake Spotify mode, no real Spotify).
- [ ] **Step 3 (HUMAN, announced, about 2 minutes): spike 1.** User drags a Finder file over the collapsed notch. Expected log: `draggingEntered`. Record yes/no and, if no, how many points of hot region around the notch are needed.
- [ ] **Step 4 (HUMAN): spike 2.** Grow the panel from `draggingEntered` and log whether the drag session continues and which of exited/ended fire on a cancelled drag outside.
- [ ] **Step 5 (HUMAN): spike 3.** A throwaway chip in the island starts an `NSDraggingSource` drag to Finder from the non-key panel; collapse the island 250 ms after drag start and record whether the drop still lands.
- [ ] **Step 6: Write results** into the spikes doc, each marked pass or fail with the matching fallback from the spec; commit the doc only.

## Task 4: Branch and worktree setup (SCRIPT)

- [ ] **Step 1:** `git switch -c shelf` from the current `test-audit` HEAD **[my call: keeps the coverage-floor work]**.
- [ ] **Step 2:** `git worktree add .worktrees/shelf-pure -b shelf-pure shelf`; confirm `.worktrees` is ignored (`git check-ignore .worktrees`).
- [ ] **Step 3:** `swift build` in both; expected: success. Task 1 and 2 briefs point Codex at `.worktrees/shelf-pure`.
- [ ] **Step 4:** After each Codex task is committed on `shelf-pure`, merge it into `shelf`.

## Task 5: Fake shelf service and drive command (SCRIPT, Claude)

**Files:**
- Create: `Sources/Shima/ShelfService.swift`
- Modify: `Sources/Shima/AppDelegate.swift`, `scripts/drive.swift`
- Test: `Tests/ShimaTests/ShelfServiceTests.swift`

**Interfaces:**
- Consumes: `ShelfStore`, `DroppedEntry`, `HoverController.dragEntered/dragExited/dragEnded`.
- Produces: `ShelfService` (NSObject) owning the `ShelfStore`, the hover wiring for drag events, and, when `SHIMA_FAKE_SHELF=1`, a `DistributedNotificationCenter` listener named `local.shima.fake-shelf`. `drive.swift "fake-shelf <cmd>"` with `add-file <path>`, `add-text <s>`, `add-link <url>`, `drag-enter`, `drag-exit`, `drop`, `clear`, `ping`.

- [ ] **Step 1: Write failing tests** `fakeCommandsMutateStore`, `dropWhileFullReportsRefused`, `shutdownRemovesObserver`, following `ServiceLifecycleTests`.
- [ ] **Step 2: Run** `swift test --filter ShelfServiceTests`. Expected: FAIL.
- [ ] **Step 3: Implement `ShelfService`** and wire it in `AppDelegate` next to `calendar` (create, assign to the island controller, `shutdown()` on terminate).
- [ ] **Step 4: Extend `drive.swift`** with the `fake-shelf` verb.
- [ ] **Step 5: Run** `swift test`. Expected: pass. Commit `feat: shelf service with fake driver`.

## Task 6: Mockup first (UI, Claude, user approval gate)

**Files:**
- Modify: `mockup/index.html`

- [ ] **Step 1: Replace the File tray tab with Home** as the first tab (shelf chips row, empty state, count, Clear), add the drag veil on any tab, add the Home-icon dot, move the Settings gear to the right wing of the expanded header, and add "Simulate drag-hover" and "Simulate drop" buttons.
- [ ] **Step 2: Open the mockup and walk through** empty, with-chips, veil, full and "3 did not fit" states.
- [ ] **Step 3: Stop and ask the user to approve the mockup.** No UI code before approval. The approved values (rects, chip size, strings) feed Tasks 7 and 8.

## Task 7: Home tab, header and layout (GLUE, Claude)

**Files:**
- Modify: `Sources/ShimaCore/CameraModel.swift` (`IslandTab` gains `.home` first), `Sources/ShimaCore/NowPlayingLayout.swift` (tab pitch from x 12, `settingsButton` to the right wing), `Sources/Shima/IslandView.swift`, `scripts/verify-alignment.sh`, `scripts/view-layout-check.swift`
- Create: `Sources/ShimaCore/ShelfLayout.swift`, `Sources/ShimaCore/ShelfText.swift`, `Sources/Shima/HomeContent.swift`
- Test: `Tests/ShimaCoreTests/ShelfLayoutTests.swift`, updates to `NowPlayingLayoutTests` and `AppStateTabObserverTests`

**Interfaces:**
- Produces: `ShelfLayout` (pure `CGRect`s for veil, chip row, Clear, count, from the approved mockup), `ShelfText` (all strings), `HomeContent` view reading `ShelfStore`.

- [ ] **Step 1: Write failing layout tests.** `tabRectsEndBeforeNotch` (`tabRect(.calendar).maxX <= 106`), `homeIsFirstTab`, `settingsButtonInRightWing` (equals `CGRect(x: 366, y: 5, width: 22, height: 22)` and does not intersect the notch x 110.5..289.5), `defaultTabIsMusic`, `collapseSnapsToMusic`, and `ShelfLayout` rects inside the 400 x 200 island and below y 32.
- [ ] **Step 2: Run** `swift test`. Expected: FAIL (compile errors from `.home` until switches are updated).
- [ ] **Step 3: Implement `IslandTab.home`, the layout changes and `ShelfLayout`/`ShelfText`**; fix every exhaustive `switch` over `IslandTab`.
- [ ] **Step 4: Build `HomeContent`** as an overlay with explicit frame, the Home icon dot, and the right-wing gear (expanded only). Chips show a file-type badge using the mockup's colours; x on a chip removes it; Clear empties the store.
- [ ] **Step 5: Add `view-layout-check.swift` cases** for Home empty and Home with chips (black 0..32 live, 0..<165 expanded must still hold). Update `verify-alignment.sh --menus` for the new gear position.
- [ ] **Step 6: Run** `swift test` and `scripts/verify-view-layout.sh`. Expected: pass. Commit `feat: home tab, shelf layout and settings gear move`.

## Task 8: Drop destination and veil (GLUE, Claude; after Task 3 passes)

**Files:**
- Modify: `Sources/Shima/HoverTrackingView.swift`, `Sources/Shima/IslandPanelController.swift`, `Sources/Shima/IslandView.swift`
- Create: `Sources/Shima/ShelfVeil.swift`
- Test: `Tests/ShimaTests/HoverTrackingViewDragTests.swift`

**Interfaces:**
- Consumes: `HoverController.dragEntered/dragExited/dragEnded(dropped:)`, `ShelfStore.add`, `DroppedEntry`.
- Produces: `HoverTrackingView.onDrag: (DragEvent) -> Void` where `enum DragEvent { case entered, exited, ended(dropped: Bool) }`, and `onDrop: ([DroppedEntry]) -> ShelfAddResult`.

- [ ] **Step 1: Write failing tests** that call the view's dragging-destination methods with a fake `NSDraggingInfo`: `enteredReportsEntered`, `dropAddsAndSwitchesToHome`, `dropWhenFullShowsRefusedCount`, `exitedReportsExited`, `unsupportedTypesAreRejected`.
- [ ] **Step 2: Run** `swift test --filter HoverTrackingViewDragTests`. Expected: FAIL.
- [ ] **Step 3: Register for `.fileURL`, `.URL`, `.string`** and implement `draggingEntered`, `draggingExited`, `performDragOperation`, `draggingEnded`; read every pasteboard item into a `DroppedEntry`. Keep drops off the SwiftUI hosting view.
- [ ] **Step 4: Add the veil overlay** and the island-controller wiring so `dragEntered` shows it on any tab and a drop selects Home and shows "Added n" or "Added n, m did not fit" for about 2 s (a single scheduled task, none while idle).
- [ ] **Step 5: Run** `swift test`, `scripts/verify-view-layout.sh` (add a veil case) and `scripts/verify-focus.sh --clicks`. Expected: pass; focus unchanged.
- [ ] **Step 6: Commit** `feat: shelf drop destination and veil`.

## Task 9: Drag-out source (GLUE, Claude; after Task 3 passes)

**Files:**
- Create: `Sources/Shima/ShelfChipDragSource.swift`
- Modify: `Sources/Shima/HomeContent.swift`
- Test: `Tests/ShimaTests/ShelfPasteboardTests.swift`

**Interfaces:**
- Produces: `ShelfPasteboard.write(_ item: ShelfItem, to pasteboard: NSPasteboard)` (file → file URL; text → plain string; link → URL plus string) and an `NSViewRepresentable` chip drag source.

- [ ] **Step 1: Write failing tests** `fileWritesFileURL`, `textWritesPlainString`, `linkWritesURLAndString`, `missingFileIsMarkedAndRemoved`.
- [ ] **Step 2: Run** `swift test --filter ShelfPasteboardTests`. Expected: FAIL.
- [ ] **Step 3: Implement `ShelfPasteboard` and the drag source.** Copy semantics; the chip stays. Per the spike 3 result, collapse the island about 250 ms after drag start or leave it open.
- [ ] **Step 4: Run** `swift test`. Expected: pass. Commit `feat: shelf drag-out`.

## Task 10: Automated checks (SCRIPT, Claude)

**Files:**
- Create: `scripts/verify-shelf.sh`
- Modify: `scripts/verify-idle.sh` if the shelf changes its fixtures

- [ ] **Step 1: Write `verify-shelf.sh`:** start a fresh `SHIMA_FAKE_SHELF=1` fake-Spotify process by pid; `drive.swift "fake-shelf drag-enter"` then assert via the window list and log that the panel is large and the phase is `dragHovering`; `drop` after `add-text hello`; assert the log shows Home selected and one item; `drag-exit` then assert collapse after the debounce; `clear`. Capture output before `grep -q` (pipefail gotcha).
- [ ] **Step 2: Run** `scripts/verify-shelf.sh`, `verify-alignment.sh --expanded --menus`, `verify-focus.sh --clicks`, `verify-live-hover.sh`, `verify-peek.sh`, `verify-idle.sh --growth`, `verify-settings.sh`. Expected: all pass. Keep pointer runs under 2 minutes and announce them.
- [ ] **Step 3: Commit** `test: shelf verification script`.

## Task 11: Acceptance and review (HUMAN + review)

**Files:**
- Create: `docs/superpowers/shelf-acceptance.md`

- [ ] **Step 1: One whole-branch review** by a fresh Claude reviewer against the spec; fix findings.
- [ ] **Step 2: Write `shelf-acceptance.md`** with the headings "Automated, passing", "Decisions", "Not run", "Open, needs a human".
- [ ] **Step 3 (HUMAN):** real drags: Finder file to the notch from collapsed, from Music, from Camera; text and a browser link; chip to Finder and to a browser; 20-item cap; cancelled drag outside; Settings still opens from the new gear; installed Shima not overlapping.
- [ ] **Step 4:** Update `CLAUDE.md` Status line (Home tab, shelf) and commit docs.

---

## Order and parallelism

Tasks 1 and 2 (Codex, `.worktrees/shelf-pure`) start immediately after Task 4. Tasks 5 and 6 run in parallel with them. Task 3 (spikes) can run any time after Task 4 and gates 8 and 9. Task 7 starts after the mockup is approved. Tasks 10 and 11 come last.
