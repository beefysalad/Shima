# Shelf and Home tab: design

**Status:** draft for approval, 2026-11-23. Calls I made without the user are marked **[My call]**; everything else was decided in conversation.

## Intent

Drag a file, a piece of text or a link onto the island, keep it there, and drag it back out somewhere else. A small, free version of the shelf that Dynamic Island clones sell. It is also the foundation for a later AI feature (Summarize, Explain, Extract to-dos on a shelf item), which is why this is built first and kept free of AI.

The real app has no Home tab today. The house icon in the header is the Settings button. The shelf needs a permanent place to show its items, and the header has no room for a fifth icon (the notch starts at x 110.5 and the last icon must end by x 106). So this milestone also turns that house icon into a real Home tab and moves Settings to the empty right wing.

## Goals

1. Dragging anything droppable over the island, from any tab or from collapsed, opens the island and shows a drop veil over the content area.
2. A drop adds items to the shelf. Files are kept as references, text as a snippet, links as a URL.
3. The Home tab shows the shelf as a row of chips, with an empty state, a Clear action and a count.
4. A chip can be dragged back out into Finder, a browser, a mail compose window and so on.
5. Settings keeps working: same window, new button position (right wing).
6. All checks that passed before still pass (alignment, focus, live hover, peek, idle RSS, view layout).

## Non-goals

- AI actions on shelf items (next milestone, plugs into the shelf store).
- Persistence across quits, copying files into an app folder, thumbnails or Quick Look.
- AirDrop, share sheet, multi-select, reordering.
- The rest of the mockup's Home (Up next, Now playing, reminders). Home ships with the shelf and an empty state only.
- Automations (`fire('shelf.dropped')` in the mockup stays a mockup thing).

## Anti-goals

Failures even if the feature works:

- The panel steals focus or activates the app. Dragging needs no activation.
- Any timer or polling while idle, or a measurable RSS rise (the 80 MB bar plus flat growth stays).
- Anything that enlarges the island's root `ZStack`. The veil and Home content are overlays with explicit frames.
- A drag over the island that leaves it stuck open or stuck collapsed (the generation-number class of bugs).
- Regressing hover, peek or the Bluetooth banner.

## Constraints from the project

- SwiftPM only, no third-party dependencies, logic in `ShimaCore` with tests (Swift Testing), AppKit glue in `Shima`, `ShimaCore` must not import AppKit.
- The mockup is the approved UI: `mockup/index.html` changes first and is approved before UI code is written.
- The existing mockup already has a File tray tab with drop and drag-out behaviour. That tab is replaced by Home plus the veil, not kept alongside.
- Checks that need drags use a fake (`SHIMA_FAKE_SHELF=1`), like the other fake services, because real drag injection is not available in the terminal.
- Coverage floors in `CoverageFloorTests` and `scripts/coverage.py` apply to new `ShimaCore` code.

## Approaches considered

1. **Overlay only.** Drop onto a veil on any tab, no place to see items afterwards. Rejected: items could never be dragged back out, so it is not a shelf.
2. **A fifth "Shelf" tab.** Simplest, but a fifth icon overlaps the notch. Rejected.
3. **Real Home tab, Settings moves to the right wing.** Icon count stays four, the shelf gets a permanent home, and Home can grow later. **Chosen by the user.**

## Design

### Header and tabs
- `IslandTab` gains `.home` as the first case: Home, Music, Camera, Calendar. `NowPlayingLayout.tabRect` already places icons on a 24 pt pitch from x 12 once the Settings button leaves the left side (12, 36, 60, 84; last ends at 106). **[My call]** The tab pitch start moves from x 36 to x 12.
- The Settings button becomes a gear in the right wing, **[My call]** at `CGRect(x: 366, y: 5, width: 22, height: 22)`, mirroring the left margin. The builder confirms it clears the island's top-right ear radius and the system menu-bar items.
- **[My call]** Music stays the default tab, and the selected tab still snaps back to Music on collapse (existing behaviour), because the island is mostly a Spotify surface. A drop switches to Home so the new chip is visible. To keep the shelf discoverable, the Home icon shows a small dot while the shelf has items.
- **[My call]** The Settings gear shows only in the expanded header. `verify-alignment.sh --menus` and its `settingsButtonCenter` expectation are updated as a SCRIPT task.

### Drag veil
- While a drag is over the island, an overlay fills the area below the header strip: "Drop to add to shelf", the count, and "Shelf full (20)" in place of the prompt when full.
- The veil is an `.overlay(alignment: .top)` with an explicit frame, like `PeekContent`.

### Shelf model (ShimaCore)
- `ShelfItem`: id, kind (`file(URL)`, `text(String)`, `link(URL)`), display name, added date.
- `ShelfStore` (`@Observable @MainActor`): add items from a dropped batch, remove one, clear, cap of 20. **[My call]** A batch fills the shelf up to the cap and the rest is refused, never evicting older items; the veil then says how many did not fit ("Added 2, 3 did not fit"). Duplicates do not count toward the cap.
- File items are references (`URL`). A reference to a missing file is dimmed and removed when a drag-out of it fails. **[My call]** Duplicate file URLs are ignored.
- **[My call]** Pasteboard precedence per dropped item: file URL (files, folders and packages) becomes a file; an `http(s)` URL becomes a link; a string that parses as an `http(s)` URL becomes a link; any other string becomes text; anything else (other schemes, file promises from Mail or Photos) is ignored in v1. Each pasteboard item becomes one shelf item.
- `ShelfLayout`: pure `CGRect`s for the veil, chip row and Clear button, with tests, following `NowPlayingLayout` and `CalendarLayout`.
- `ShelfText`: all user-visible strings in one place, like `SettingsText`.

### Hover machine: drag-hover
- New phase `dragHovering` and inputs `dragEntered`, `dragExited`, `dragEnded(dropped:)`, following the peek pattern. Reuse the effects `growPanel`, `setHotRegion(.expanded)` and `animateExpand`.
- AppKit tracking areas stay silent during a drag, so `pointer(inside:)` is not used while dragging. `HoverController` gains `drag(...)` wrappers mirroring `pointer(inside:)`.
- `dragExited` runs the existing leave debounce into a normal collapse. `dragEnded` re-syncs the pointer with the one-shot `NSEvent.mouseLocation` read the tracking view already does, so a drop inside the island does not collapse it and a cancelled drag outside does.
- A drag entering during a peek cancels the peek. `reset` clears the new flag. Generation numbers stay the only guard for collapse completions.
- Reducer tests come first, because the hover machine is the riskiest part (the device-popups spec said the same).

### Drop and drag glue (Shima)
- `HoverTrackingView` (the panel's content view) registers for `.fileURL`, `.URL` and `.string` and implements the dragging-destination methods. The drop stays on the AppKit view; the SwiftUI hosting view gets no `.onDrop`.
- Dragging out: each chip is an `NSDraggingSource` through a small `NSViewRepresentable`. **[My call]** Like the mockup ("get out of the way"), the island collapses about 250 ms after the drag starts so the drop target is visible.
- **[My call]** Drag-out copies and the chip stays on the shelf (it is a reference; remove it with its x or Clear). Files go out as file URLs, text as a plain string, links as a URL plus a string. No `.webloc` files in v1.
- The panel stays non-activating throughout. `verify-focus.sh --clicks` must still pass.

### Fakes and checks
- `SHIMA_FAKE_SHELF=1` with `drive.swift "fake-shelf add-file <path>|add-text <s>|add-link <url>|drag-enter|drag-exit|drop|clear"`.
- `verify-view-layout.sh` gets cases for Home empty, Home with chips and the veil. A new `verify-shelf.sh` drives the fake through enter, drop, exit and clear and checks the log and the window list.
- Real drags (Finder to the notch, chip to Finder) are HUMAN tasks in `shelf-acceptance.md`.

## Spikes before the plan is final
Short, throwaway, run on the user's machine with real drags:
1. Does a drag reach a registered destination on the collapsed, notch-sized panel? If not, how much hot region is needed?
2. Can the panel grow while a drag is in flight?
3. Can a chip start a drag out of an `NSHostingView` in a non-key panel, and can the island collapse during that drag session?

The spikes gate the GLUE and UI tasks only. PURE tasks (store, layout, text, reducer inputs and tests) start in parallel. **[My call]** Fallbacks if a spike fails:
- Spike 1 fails: drops are accepted only once the island is already expanded (hover opens it, then you drop). A smaller feature, but still a shelf.
- Spike 3 fails: drag-out works with the island left open instead of collapsing.
- Spike 2 fails: the veil appears at the island's current size and the panel grows on drop.
- `draggingEnded` versus `draggingExited` delivery on a cancelled drag is checked in spike 2 as well. The reducer treats both as "the drag is over" so either one is enough.

The result goes in `docs/superpowers/spikes/2026-11-23-shelf-spikes.md`. The user runs the spikes; they are short and announced.

## Work split
Following the repo's PURE / GLUE / SCRIPT / HUMAN plan format.
- **PURE (Codex, separate worktree under `.worktrees/`, ShimaCore only):** `ShelfItem`, `ShelfStore`, `ShelfLayout`, `ShelfText`, hover-machine drag inputs and tests. Briefs name exact files and forbid committing; the diff is reviewed before staging.
- **UI and GLUE (Claude):** mockup first, then Home view, veil, header and Settings move, drop destination, drag-out source, wiring.
- **SCRIPT:** fake shelf, `verify-shelf.sh`, view-layout cases.
- **Review:** a fresh Claude reviewer per task, one whole-branch review at the end.

## Left to the builder
Exact veil and chip visuals (as approved in the mockup), chip truncation rules, file-type badge colours (reuse the mockup's `EXT_COLOR`), log messages, and the exact gear position within the right wing.
