# Pure-core handoff

## Settings window: Tasks 1-5

Implemented in requested order on branch `settings-pure`, worktree `.worktrees/settings-pure`. Base: main `3625dbc` (includes the approved plan `59475eb` and the controller's script Task 6). Read `CLAUDE.md`, the approved settings design, the plan's Goal, Global Constraints, Review Focus, parallel-work section, Plan notes / deviations, and Tasks 1–5 in full.

Each task had a fresh implementer and a separate fresh read-only reviewer. All five reviews approved without blocking findings; no fix/re-review cycle was required. Tests were written before implementation and the filtered run failed on the expected missing API. After implementation each filtered run and full `swift test` passed with zero warnings. Task 5 also passed `swift build`. Only these SwiftPM verification commands were run; no app, script, Spotify interaction, process stop, registration, real UserDefaults access, or real timer/sleep was used. Tests use in-memory preferences and fake login services.

### Commits and test counts

| Task | Commit | Tests added | Filtered result | Full suite |
| --- | --- | --- | --- | --- |
| 1: Equalizer mode/policy and AppState | `83190a4` | 12 | 12 tests, 1 suite | 237 tests, 17 suites |
| 2: Preference storage and SettingsStore | `dd875ed` | 8 | 8 tests, 1 suite | 245 tests, 18 suites |
| 3: Settings text, links, fixed geometry | `5b6706d` | 19 | 19 tests, 2 suites | 264 tests, 20 suites |
| 4: Shared SettingsModel and login service seam | `e46989c` | 17 | 17 tests, 1 suite | 281 tests, 21 suites |
| 5: Island gear/title geometry | `5789529` | 4 | 10 tests, 1 suite, including existing layout tests | 285 tests, 21 suites |

Task 1 includes the eleven prescribed tests plus one complete policy matrix covering 16 visibility and 192 animation combinations. It covers default/raw values and titles, collapsed live visibility, expanded track visibility independent of live, all three modes, and paused/frozen precedence. The equalizer is explicitly allowed in the open island, as the user confirmed.

Task 2 includes the six prescribed tests plus uncached storage reads and missing-default no-write/read-then-set behavior. It covers fallback without rewriting unknown values, exact raw-value writes, redundant-write suppression, and the pure bundle-identifier selection rule. No test constructs a real UserDefaults adapter.

Task 3 includes the eleven prescribed text and three layout tests plus five boundary tests: strict thirty-day warning threshold, exact expiry instant, whole-day flooring including the final partial day, certificate identity privacy after the colon, and empty build strings. Layout tests pin all script click points and ensure fourteen rectangles fit without overlapping.

Task 4 includes the eleven prescribed tests plus six regressions: toggling from fresh service status rather than cached status, failed unregister/retry semantics, no preference reload on refresh, persistence/model/AppState updates before mode callbacks, login-state Observation, and nested Spotify AppState Observation without refresh. Prescribed coverage includes register failure/unavailability, requires-approval handling, URL/quit callbacks, once-only signing reads, and stored-mode loading.

Task 5 includes the three prescribed tests plus global gear-center conversion on a screen with negative horizontal and vertical offsets. It pins title `(116,44,200,18)`, gear `(322,38,24,24)`, the six-point gap, and nonintersection with artwork and playback controls. Existing column and control geometry is unchanged.

### Evidence

Exact full-run summary output:

```text
Task 1: ✔ Test run with 237 tests in 17 suites passed after 0.005 seconds.
Task 2: ✔ Test run with 245 tests in 18 suites passed after 0.006 seconds.
Task 3: ✔ Test run with 264 tests in 20 suites passed after 0.008 seconds.
Task 4: ✔ Test run with 281 tests in 21 suites passed after 0.008 seconds.
Task 5: ✔ Test run with 285 tests in 21 suites passed after 0.009 seconds.
Build complete! (0.35 sec)
```

Local ignored logs: `.build/settings1-{red,filtered,full}.log` through `.build/settings4-{red,filtered,full}.log`, and `.build/settings5-{red,filtered,full,build}.log`. Red logs show missing EqualizerPolicy, SettingsStore, SettingsText, LoginItemService, and NowPlayingLayout.settingsButton respectively. Passing logs have no `warning:` or `error:` matches. `git diff --check` passed. The first Task 1 red invocation could not redirect output because `.build` did not exist yet; the directory was created inside the worktree and the actual red test then ran and failed for the expected missing API.

### Deviations and ambiguities

1. **Additional tests / historical totals:** added 60 tests to the actual 225-test baseline, versus the plan's 45 additions, so the final total is 285 rather than 270; suite count remains 21. Extra coverage is enumerated above. No prescribed test was removed, and implementation code follows the plan's supplied code and signatures.
2. **Branch base:** used `git worktree add ... main` exactly as requested. Main had advanced to `3625dbc` beyond the plan commit, including the controller-owned script task. No main working-tree changes, including the user's uncommitted branding and bundle-script changes, were staged, edited, or reverted. No further merge was needed or performed.
3. **Report exception:** the plan's parallel-work section says not to edit `docs/`; the user's explicit final-report instruction authorizes this one new report file. All implementation/test changes otherwise stay under `Sources/ShimaCore` and `Tests/ShimaCoreTests`. No changes under `Sources/Shima` or `scripts/`.
4. **Signing countdown wording:** supplied Task 3 code emits `in 1 days` and `in 0 days`. Preserved verbatim rather than silently editing approved strings. Warning uses strictly fewer than thirty whole remaining days; exactly thirty days has no countdown. Expiry at `notAfter == now` is already expired. Added tests make these choices explicit.
5. **Signing text freshness:** Task 4 caches both the signature read and the formatted text on the first refresh, including its reference time. This follows the supplied implementation, but the countdown/expired wording can become stale in a process that remains running for days. If the controller wants fresh wording on every window open, cache the SigningSummary and reformat on refresh in a follow-up; no timer is needed. No such behavior change was made here.
6. **Gear wording:** the design says outside the now-playing column, but the exact requested rect is inside the full column's horizontal span. Task 5/note 2 resolves this by narrowing only the title and placing the gear beside it, below the menu bar; artist/progress/controls retain the full column. Followed exact plan coordinates and public signatures.
7. **Persistence wording:** followed plan note 3 over the design's literal suite wording: bundled `local.shima` chooses standard defaults; other bundle identifiers choose the `local.shima` suite. Tests verify the selection function only and never touch the real preference domain. Unknown values remain unchanged on reads; explicitly setting the default can normalize an unknown raw value without emitting a mode-change callback when the model already has that mode.
8. **Permission wording:** followed plan note 4: running does not prove Automation permission was granted. The text explicitly says allowed or not asked yet. No new Spotify permission probe was added.
9. **Public row construction:** the provided SpotifyStatusRow has public immutable fields but an internal synthesized memberwise initializer. Preserved that declaration; app glue can receive/read public rows via SettingsText and SettingsModel without constructing them. No public API addition was necessary.
10. **Real-code compatibility:** no conflicting existing ShimaCore signatures required a deviation. Existing login-menu failure semantics, AppState artwork hooks, NowPlayingLayout column/control geometry, and all existing tests remain intact.

No assigned task remains blocked or incomplete. No approval question is pending. All changes are committed on `settings-pure`; nothing was pushed or merged into main. The controller owns the app glue, real UserDefaults/ServiceManagement/Security adapters, one-window/focus/idle checks, rendered root-size/gear checks, and integration acceptance. Pure tests do not claim those UI checks passed. The user's permission for scripts to stop installed Shima by pid was not exercised by this engineer.
