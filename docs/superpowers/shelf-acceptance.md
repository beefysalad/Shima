# Shelf and Home tab: acceptance record

Branch `shelf`, 2026-11-23. Spec `specs/2026-11-23-shelf-design.md`, plan `plans/2026-11-23-shelf-plan.md`, spikes `spikes/2026-11-23-shelf-spikes.md`, approved mockup `mockup/index.html`.

## Automated, passing

- `swift test`: 494 ShimaCore tests and 91 Shima app tests pass.
- `scripts/verify-view-layout.sh`: Home empty, Home with chips, the drag veil (normal, over the tile, full) and every pre-existing view pass; header strip and notch zone stay empty.
- `scripts/verify-shelf.sh` (fake shelf, new): 15 checks pass. Collapsed drag-enter grows the island to the expanded frame (`collapsed -> dragHovering`); a drop of 3 items reports `added=3 refused=0 items=3` and stays expanded (`dragHovering -> expanded`); drag-exit collapses after 0.34 s (debounce); exit then re-enter 140 ms later stays open; drop-cancel adds nothing and collapses; a 22-file batch fills to the cap (`added=20 refused=2 items=20`); clear empties the store; the frontmost app never changed and the island never became active.
- `verify-alignment.sh` (idle) and `--expanded`: pass. `verify-focus.sh --clicks`: pass. `verify-live-hover.sh`: pass (dwell 117 ms, debounce 352 ms). `verify-peek.sh`: all items pass, so the hover-machine changes did not disturb the device banner.
- `verify-idle.sh` and `--growth`: static check finds no timers, event monitors or display links; RSS 58 MB, 0 MB growth over 20 open/close cycles; 0.000 CPU seconds in 60 s.
- Spikes with real Finder drags (see the spikes doc): a drag reaches the collapsed notch-sized panel; the panel can grow while the drag is held; drag-out from the non-key panel works; cancelled drags deliver exit then end.

## Decisions

- Real Home tab, Settings gear moved to the right wing (expanded only); Music stays the default tab and collapse snaps back to Music; a dot on the Home icon shows while the shelf has items.
- Drop veil is a row of tiles (DynaDrop style) with one real tile, "Shelf"; AirDrop and other tiles are deliberately not in v1 (AirDrop sharing can take focus).
- Cap 20; a batch fills to the cap and the rest is refused ("Added 2, 3 did not fit"); duplicate file URLs ignored. Files are references, no persistence across quits.
- Drop precedence: file URL, then http(s) URL, then a string that parses as an http(s) URL (whitespace trimmed), then other text; other schemes and file promises are ignored.
- Drag-out copies; the chip stays. A file deleted while shelved removes its chip instead of starting a drag.
- The drop destination ignores the app's own chip drags (`OwnDrag`), found by the spike.
- Branch cut from `test-audit` to keep the coverage-floor work.

## Whole-branch review (fresh reviewer, read-only)

No important findings and no project-rule violations. Fixed after the review, each with a failing test first:
- A snippet that starts with a newline is named by its first real line, not "Text" (the existing test asserted too little).
- Duplicate files are decided on the standardized path (`/a/../b/x`, trailing slash).
- A dropped snippet is capped at 100,000 characters.
- A refused drag (own chip, unsupported) now clears stale `acceptedSession`/`dropped`, so a missed `draggingEnded` cannot mislabel the next session.
- `OwnDrag.active` is set before the drag session starts, expires after 120 s, and the destination also refuses any drag whose `draggingSource` is non-nil, so a missed end callback cannot make the island refuse external drops until relaunch.

Left as is: `fileSize` reads file attributes in the Home view body (only while Home is open; a stalled network volume could stall it; cache at add time if it ever matters); a drag cancelled with Esc inside the island collapses it (observed in the spike, treated as intended); the `.URL` pasteboard type carries the URL string (check in step 5 below that Safari and Notes accept a dragged-out link).

## Not run, or not trustworthy

- `verify-alignment.sh --menus` needs a status menu open and was not run.
- `verify-settings.sh` is unreliable in this environment and says nothing reliable about this feature. The equalizer-segment clicks (E1, E2, E4, E5, G1, G3, G6, G7) fail identically on the pre-shelf commit `53a2cc5`; their hard-coded click points appear stale after the Settings window changed. The open-window and gear checks (A to C) passed on some runs and failed on others on both branches. In the runs where the harness worked, the new right-wing gear opened Settings (C1 to C3 passed). F4 (Automation button) failed once on this branch and passed once on the baseline: unexplained. Follow-up: repair the script's click points; it is not part of this milestone.
- The thin AppKit drag overrides (`draggingEntered` and friends) are covered by the spikes and `verify-shelf.sh` through the same hover path, but the real `NSDraggingSource` chip drag is not covered by any script.

## Open, needs a human

Real drags, with the installed Shima quit and a build from this branch running (fake Spotify is fine):
1. Finder file onto the collapsed notch: veil appears, tile turns blue under the cursor, drop adds a chip, island switches to Home with "Added 1".
2. The same from the Music, Camera and Calendar tabs.
3. A selected piece of text and a browser link dropped onto the island: text chip and link chip.
4. A 20-item shelf and a further drop: "Shelf full (20)" on the veil, then "Added 0, n did not fit" semantics as in the mockup.
5. A chip dragged to Finder (a copy lands, the chip stays), to a browser or text field (link gives the URL, text gives the text); the island collapses about 250 ms after the drag starts.
6. A chip dragged onto the island itself is ignored (no veil); a cancelled chip drag (Esc) leaves the island droppable afterwards (`OwnDrag` cleared).
7. A file deleted while shelved: its chip disappears when you try to drag it.
8. The chip's x and Clear still click; the drag image looks acceptable; a horizontal swipe over the chips scrolls the row while a drag drags the chip.
9. Settings opens from the right-wing gear; the Home dot appears and disappears with the shelf.
10. The island never steals focus during any of the above.
11. The x on a chip is always visible (the mockup shows it on hover only): decide whether that is fine.
12. After a chip drag-out that you release outside the app, and again after one cancelled with Esc, drop a Finder file onto the notch: it must still be accepted (the own-drag flag is cleared or expired).
