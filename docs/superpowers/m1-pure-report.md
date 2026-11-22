# M1 pure-core handoff

Worktree: `.worktrees/m1-pure`; branch: `m1-pure`. Completed tasks in requested order: 6, 8, 10, 11. Each task used a fresh implementer followed by a separate fresh read-only reviewer; all four reviews approved with no blocking findings. No pushes or merges into main. No changes under `Sources/Shima`, no new dependencies, no Spotify launches or commands, and no real timers/sleeps in tests.

## Commits and verification

| Task | Commit | Tests added | Filtered result | Full `swift test` result |
| --- | --- | --- | --- | --- |
| 6 | `2a690f4` | 13 NowPlaying tests | 13 tests, 1 suite | 72 tests, 8 suites |
| 8 | `4619503` | 22 SpotifyModel tests | 22 tests, 1 suite | 94 tests, 9 suites |
| 10 | `8a6138b` | 19 SpotifyRequestGate tests | 19 tests, 1 suite | 113 tests, 10 suites |
| 11 | `bfb84d6` | 9 IslandLayout tests and 6 NowPlayingLayout tests | 25 tests, 2 suites, including existing layout tests | 128 tests, 11 suites |

Task 6 covers extrapolation, duration clamping, paused/stopped static position, clocks before the sample, unknown duration, negative position, elapsed/remaining/fraction formatting, and fractional floor boundaries. Four tests extend the plan's nine.

Task 8 covers every reducer-table branch: launch/no-op launch, late readings while not running, track start/change/clear, artwork preservation, state transitions without a position, sparse metadata/position anchors, explicit empty/zero field replacement, old-duration projection, script permission recovery, ordered availability/track/state emissions, and content precedence. Nine tests extend the plan's thirteen; one test has two argument cases.

Task 10 covers coalescing, sequence/pid tags, invalidated snapshots and commands, missing/current/old pid, command isolation, dirty follow-ups, same-pid new command issuance, relaunch while a stale snapshot remains in flight, duplicate old completion versus newer snapshot state, repeated invalidation, and all specified Apple Event error mappings. Ten tests extend the plan's nine.

Task 11 covers 33 pt wings, the measured live frame and status-item clearance, unchanged nonlive/expanded geometry, collapsed metrics, the whole live strip as the idle hot rect in small/large panels, a virtual notch, content/control containment and exact geometry, wing arithmetic, and control centers on the measured and offset screens. One offset-screen test extends the plan's fourteen additions; existing layout tests now pass explicit `live: false`.

Every task first recorded its expected missing-type/API compilation failure, then passed its filtered tests and the full suite. Task 11 also passed `swift build`. Passing filtered/full/build logs contain no `warning:` or `error:` lines. Final `git diff --check` passed. Actual full-suite output:

```text
Task 6:  ✔ Test run with 72 tests in 8 suites passed after 0.002 seconds.
Task 8:  ✔ Test run with 94 tests in 9 suites passed after 0.002 seconds.
Task 10: ✔ Test run with 113 tests in 10 suites passed after 0.002 seconds.
Task 11: ✔ Test run with 128 tests in 11 suites passed after 0.003 seconds.
Build complete! (0.33 sec)
```

Local evidence is retained in this worktree's ignored `.build/task6-{red,filtered,full}.log`, `.build/task8-{red,filtered,full}.log`, `.build/task10-{red,boundaries-red,filtered,full}.log`, and `.build/task11-{red,filtered,full,build}.log`. Logs are not committed.

## Blocked tasks

Before checking each remaining task, ran `git merge main` in this worktree; each returned `Already up to date.` Main remained at `3c3703a`. The required file `docs/superpowers/spikes/2026-11-21-m1-spikes.md` was absent at all three checks.

| Task | Status | Required evidence |
| --- | --- | --- |
| 7 | Parsing, artwork URL policy, and `hasDisplayFields` not implemented | Spikes 1–2: payload keys/units, track ID forms, artwork URL form |
| 9 | Not started; no client, fake, coordinator, or AppState additions | Spike 1: notification rate/completeness; completed Task 7 |
| 12 | Not started; hover machine/controller unchanged | Spike 3: live-geometry transition result |

Task 7's spike-independent data types are already present as the Task 8 prerequisite below. No payload keys, units, normalization, or refresh policy were guessed. No spike result contradicted the plan because none was available. Tasks 1–5 and 13–25 remain controller-owned.

## Deviations and specification notes

1. **Dependency/order mismatch:** Task 8 consumes Task 7 types, but the user explicitly ordered Task 8 before blocked Task 7. Commit `4619503` therefore introduces only the exact `ReadingSource` enum and `SpotifyReading` stored fields/public initializer in `SpotifyReading.swift`. Task 7 should extend that existing file with parsing, URL policy, and `hasDisplayFields` after reading the spikes. This split was stated in progress updates.
2. **Task 11 user override:** all new `live` parameters default to `false`; no app call sites changed. This overrides the plan's mandatory flag/replaced-signature instruction and its app edits, keeping current glue compiling. The controller still needs to pass the applied live flag in glue.
3. **Plan wording error:** Task 11 says the controls row y112–144 sits below artwork ending at y132. Those ranges overlap vertically at y112–132; prescribed rectangles are horizontally separated and valid. Implemented the exact coordinates, matching section 8's geometry.
4. **Test totals:** historical plan totals assume a different task order. The actual baseline is 59 tests; this branch adds 69, totaling 128. Extra tests listed above cover meaningful boundaries. No existing test behavior was removed.
5. **Position wording:** Task 6 says playing position is duration-clamped, otherwise position stays static, never negative. Implementation applies the upper clamp only while playing and the zero minimum in all states. Section 8's general clamping sentence is broader; ordinary paused samples within duration agree with both. Controller can clarify out-of-range paused samples if needed.
6. **Undefined numeric domain:** elapsed formatting converts floored nonnegative seconds to `Int`. Nonfinite or out-of-`Int` values have no specified fallback and can trap. No unsolicited sanitization policy was added. The parser/script adapter should validate external numeric values or the controller should define a formatting fallback before accepting malformed numeric inputs.
7. **Request invalidation semantics:** followed the plan literally: `invalidate()` updates `staleThrough` and clears dirty, retaining the active snapshot until completion. A request after relaunch can owe a follow-up, which the stale completion schedules using the current pid while dropping its own result. This is explicitly tested.
8. **Existing M0 interfaces:** no conflicting real-code signatures required further deviations. The existing hover machine and AppState remain unchanged. No section 8 behavior defect was identified beyond the numeric/position ambiguities above.

## Controller follow-up

- Record and commit Spikes 1–3 before resuming Tasks 7, 9, and 12; Task 7 must extend the existing data contract rather than redeclare it.
- Decide whether malformed/nonfinite numeric samples require a defined fallback and whether paused positions beyond duration should clamp.
- Main-actor application, private serial Apple Events, stale results across process relaunch, applied-versus-desired live state during collapse, and the wide-collapse-then-wing-drop rule still need their later coordinator/hover/glue verification. Pure layout tests do not claim to verify those transitions.

The branch is ready for the controller to merge or cherry-pick; it has not been merged into main.

## Resumed work: Tasks 7, 9, and 12 (2026-11-22)

This section supersedes the earlier blocked-task status. All assigned pure-core tasks 6–12 are now complete. Resumed with a clean worktree and fast-forwarded main to `eae3a1c`; read Spike 1 and Spike 2 before Task 7. Before Task 9, merged main again (`Already up to date`) and re-read the notes. The user subsequently authorized Task 12 after Spike 3 landed: merged main including `b2314ba` into this branch (`e9b0e23`, a merge commit because Tasks 7 and 9 were already local commits), then read Spike 3. No changes were merged into main and nothing was pushed.

Each task again used a fresh implementer, a separate fresh read-only reviewer, recorded failing tests before implementation, and passed review without blocking findings. All new implementation changes are under `Sources/ShimaCore`; tests use Swift Testing, injected dates or ManualScheduler, and no real timers/sleeps. No app glue was edited and no Spotify process or command was invoked. Main's glue/scripts/spike-note changes were incorporated only by the authorized merges.

| Task | Commit | Tests added | Filtered result | Full `swift test` result |
| --- | --- | --- | --- | --- |
| 7 | `5de4237` | 15 SpotifyReading tests | 15 tests, 1 suite | 143 tests, 12 suites |
| 9 | `e81b51e` | 30 coordinator/fake tests | 30 tests, 2 suites | 173 tests, 14 suites |
| 12 | `f7a2459` | 9 machine, 2 controller, 2 layout tests | 58 tests, 3 suites, including existing hover/layout tests | 186 tests, 14 suites |

Task 7 extends the existing data contract with notification parsing, `hasDisplayFields`, and the HTTPS artwork helper. Tests cover the seven plan cases plus sparse pause/play metadata, malformed state and optional fields, booleans masquerading as numbers, nonfinite/negative/oversized times, unit-specific inclusive bounds, metadata preservation when times are invalid, and safe direct initializer inputs. Empty strings become nil; artwork fields in notifications are ignored.

Task 9 adds the main-actor client protocol, fake, coordinator and AppState fields. The eighteen plan tests plus twelve additional tests cover owner-controlled event wiring, sparse pause/play merge and refresh, collapsed position updates, callback ordering before synchronous refresh, artwork marking before reentry, Stopped-before-terminate order, applied live-state ownership, real coordinator/fake synchronous wiring, injected-clock pause/resume, wrap/reset while paused, duration clamping, no-op fake invalidation, and initial stopped/paused clocks. The coordinator leaves `AppState.live` unchanged and reports desired live changes through its callback.

Task 12 adds `.idleGeometryChanged` and `HoverController.idleGeometryChanged()`. The rule is exactly `panelLarge ? [] : [.shrinkPanel]`, with no phase, pointer, generation, or timer mutations. Tests cover every phase, small/large dwell, preserving the original dwell deadline, reentry during collapse, stale collapse completion, and pointer deduplication. Two additional layout tests deliberately diverge applied/target live flags: live-on includes a point on the new wing before applied state changes; live-off excludes the old wing before applied state changes. `hotRect(live:)` now documents that its flag is the TARGET geometry state, independent of the rendered wings.

All passing filtered/full/build logs have no `warning:` or `error:` lines; `git diff --check` is clean. Exact terminal summary output:

```text
Task 7:  ✔ Test run with 143 tests in 12 suites passed after 0.003 seconds.
Task 9:  ✔ Test run with 173 tests in 14 suites passed after 0.004 seconds.
Task 12: ✔ Test run with 186 tests in 14 suites passed after 0.004 seconds.
Task 9 build:  Build complete! (0.46 sec)
Task 12 build: Build complete! (0.21 sec)
```

Local logs: `.build/task7-{red,filtered,full}.log`, `.build/task9-{red,filtered,full,build}.log`, and `.build/task12-{red,filtered,full,build}.log`. Task 7's expected red failure references the missing notification initializer/helper APIs rather than a missing type because Task 8 already introduced the struct. Tasks 9 and 12 failed on their missing client/hover APIs as expected. A Task 7 test assertion was rewritten using a local variable to avoid a Swift Testing macro expansion issue; no production behavior changed for that workaround.

### Spike overrides, deviations, and resolved questions

1. **Numeric policy required by the resumed user instruction:** invalid optional times become nil. Valid seconds are finite and within inclusive `0...604800` (seven days); raw duration milliseconds are checked before conversion against `0...604800000` and strictly below `Double(Int.max)`. Negative, NaN, infinity, Boolean NSNumber, and absurd or out-of-Int-range samples are rejected. Seven days is a deliberately generous implementation ceiling, not a measured Spotify limit. The public seconds initializer uses the same validation for future script readings, extending the plan's simple member assignment. Existing mutable properties remain public as specified. This resolves the external-input question in the first report for parser/initializer paths; direct mutation or direct calls to `PlaybackTime` with invalid values remain outside that guarantee.
2. **Spike 1 sparse payload:** pause/play leaves missing title/artist/album nil; the existing reducer retains metadata, and the coordinator refreshes incomplete notifications even if artwork is already known. Stopped-only parsing and Stopped-before-terminate ordering are tested. No after-quit reading can restore state while availability is not running.
3. **Spike 1 rate:** measured zero periodic broadcasts, so the conditional position-only skip rule was not implemented. Collapsed position updates remain applied. Seek notification behavior is still only inferred; no new seek assumptions or code were added. Opening the island refreshes position.
4. **Spike 2:** IDs are unchanged and artwork stays HTTPS-only; no track-ID normalization or HTTP upgrade. Per-property Apple Event reads and their units/timeouts belong to controller-owned Task 16; no Apple Events were added to ShimaCore.
5. **Fake simplification/ambiguity:** next/previous wrap tracks, reset position, and preserve the playback state. Paused-next behavior was not established by the spike. The plan explicitly simplifies previous to moving tracks, whereas the real observed previous command restarted the current track after about three seconds. The fake follows the plan. Positions clamp to track duration without automatic track advance; transitions remain event-driven.
6. **Spike 3 overrides the plan's glue assumption:** `liveFrameStrategy = growThenAnimate`; idle hot rectangles must use the TARGET live flag. The existing compatible `hotRect(..., live:, ...)` API already accepts that value, so its documentation plus regression tests establish the contract without adding a redundant API or touching app glue. Task 14 must pass the target flag when resizing/refreshing the hot rect; tests cannot enforce an unimplemented caller's argument choice.
7. **Reset wording:** preserved M0 reset exactly. Section 8's broad reset-reapplies-frame statement is clarified by plan note 2: when already small, later `place(on:)` glue calls `applyIdleGeometry(animated: false)` after `hover.reset()`. Task 12 does not alter reset to emit extra effects.
8. **Totals/order:** actual test totals supersede the historical plan totals. These resumed tasks add 58 tests to the earlier 128, totaling 186. No existing tests were removed, no dependencies added, and no further public interface deviations were needed.

No assigned pure-core task remains blocked or incomplete. No approval question is pending. Controller follow-up is the target-live hot-rect argument, applied-versus-desired wing timing during collapse, reset reapplication in glue, and the later script-client pid/request-gate wiring. These pure tests do not claim to verify app frame delivery, real Automation, or live UI acceptance. Tasks 1–5 and 13–25 remain outside this engineer's scope.
