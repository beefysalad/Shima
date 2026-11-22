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
