# Shelf spikes (2026-11-23)

Throwaway build on branch `shelf-spike` (never merged, worktree removed): a drag destination on `HoverTrackingView`, the hover machine drag inputs wired to it, a logging `draggingUpdated`, and a throwaway chip using SwiftUI `.onDrag` with the island collapsing 250 ms after drag start. Fake Spotify mode, installed Shima quit, real Finder drags, log captured from the `local.shima` spike and hover categories.

## Spike 1: does a drag reach the collapsed, notch-sized panel? PASS

`draggingEntered` fired while the panel was still 179 x 32 (collapsed, notch-sized). No extra idle hot region is needed. The drag types on a Finder file are `public.file-url`, `NSFilenamesPboardType`, `Apple URL pasteboard type` and others.

## Spike 2: can the panel grow while a drag is in flight? PASS

The panel grew from 179 x 32 to 436 x 208 on `dragEntered` while the drag was held. `draggingUpdated` kept arriving for about 9 s after the growth, so the session survives the resize.

Event order observed:
- Drag leaves the island and is released outside: `draggingExited`, then `draggingEnded dropped=false` about 800 ms later. The machine is already in `.collapsing` by then and ignores the second event.
- Drag released inside the expanded island: `performDragOperation`, then `draggingEnded dropped=true`; the machine goes `dragHovering -> expanded` and stays open.
- Esc mid-drag: `draggingExited` and `draggingEnded dropped=false` within 2 ms of each other; the island collapsed.
- **Growth causes an exit and re-enter.** When the panel resizes under the cursor AppKit sends `draggingExited` then `draggingEntered` about 140 ms apart. The 300 ms leave debounce absorbs it; the debounce must stay above about 200 ms.
- A drag entering during `.collapsing` goes to `dragHovering` and the stale collapse completion is ignored (generation logic holds).

The fallback for spike 2 (grow on drop) is not needed.

## Spike 3: can a chip start a drag out of the non-key panel? PASS, with one finding

SwiftUI `.onDrag` started a drag from the non-key panel and the file landed on the Desktop. The island collapsed once the cursor left it.

**Finding: the island receives its own chip drags.** `draggingEntered` fired on our own panel for the chip's drag (types included `public.plain-text` and `public.file-url`), so the machine entered `dragHovering`. Two consequences:
1. The drop veil would show over the island's own chip drag.
2. The planned "collapse 250 ms after drag start" does nothing, because pointer inputs are ignored while `dragActive` is true. The island only collapsed when the cursor left.

**Decision:** the drop destination ignores drags that originate in this app. The chip drag source is an `NSDraggingSource` (as the plan already says) that sets a `selfDragActive` flag on start and clears it in `draggingSession(_:endedAt:operation:)`; `draggingEntered` returns `[]` and sends no hover input while the flag is set. The 250 ms collapse then works through the normal pointer path (`pointer(inside: false)` from `.expanded`).

**Not proven by the spike:** an `NSDraggingSource` drag (as opposed to SwiftUI `.onDrag`) from the non-key panel, and the session-end callback. Task 9 verifies both with a real drag (HUMAN step in the acceptance record).
