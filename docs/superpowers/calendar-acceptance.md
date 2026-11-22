# Calendar and Reminders tab: acceptance record

Spec `specs/2026-11-23-calendar-reminders-design.md`, plan `plans/2026-11-23-calendar-reminders-plan.md`. Merged to `main` as `4e5dd36`.

## Automated, passing (2026-11-23, merged build, fake calendar)

- `swift test`: 404 tests (whole merged tree).
- `scripts/verify-view-layout.sh`: calendar tab silhouette, header icon, empty notch zone, today's number in the accent colour, rows inside y 90..186, six-week grid by y 186, denied notices.
- `scripts/verify-calendar.sh` (fresh `SHIMA_FAKE_CALENDAR=1` process): Music gating (no requests while Music is selected), permission order and denial, month arrows, store and day changes, collapse and reopen, click-owner guard.
- `scripts/verify-idle.sh`: 0.000 s CPU in 60 s, no timers; RSS 62 MB. `--growth`: 0 MB growth over 20 open/close cycles (63 MB flat).

## Decisions

- Browsing to a month whose grid does not contain the selected day moves the selection to today (if in that month) or the 1st, so the left column always has data (found by the mockup comparison).
- Today is the accent-coloured number, no circle (user, 2026-11-23). The blue dot means "has events".
- Idle memory bar raised from 60 to 80 MB plus the growth check (user approved 2026-11-23). One run measured 1.39 s CPU straight after the first calendar check on a fresh process; it did not reproduce in three later runs (0.040, 0.000, 0.000). Unexplained, watch for it.

## Open, needs a human

- First opening the Calendar tab shows the Calendar prompt, then the Reminders prompt.
- Real events and reminders appear (including Google events if that account is in macOS Calendar).
- Completing a reminder shows done in Reminders.
- Denying then allowing in System Settings recovers on return to shima.
- No Calendar or Reminders access happens while on Music.
