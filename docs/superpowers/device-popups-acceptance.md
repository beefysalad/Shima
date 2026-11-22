# Device pop-ups and peek: acceptance record

Spec `specs/2026-11-23-device-popups-design.md`, plan `plans/2026-11-23-device-popups-plan.md`, spike `spikes/2026-11-23-device-spikes.md`. Merged to `main` as `34b3500`.

## Automated, passing (2026-11-23, merged build, fake devices)

- `swift test`: 404 tests (whole merged tree).
- `scripts/verify-view-layout.sh`: the 340 x 76 banner for all 8 device kinds (SF Symbol badge, title, name, battery), no battery, long name, low battery red, hidden outside a peek, empty notch strip.
- `scripts/verify-peek.sh`: banner frame 376 x 84 centred; folds after 3.0 to 3.2 s and the panel returns to idle size; a second device replaces the banner with one dismissal; hover opens the island once and a stale peek timer cannot collapse it; a device while the island is open is dropped; the same device within 5 s is dropped; persisted Device pop-ups off drops; the island never became active and the frontmost app never changed.
- Regression: `verify-focus.sh --clicks`, `verify-camera.sh`, `verify-live-hover.sh`, `verify-alignment.sh --expanded`, `verify-idle.sh` all pass.
- Real Bluetooth (spike S1, this Mac): connect notifications fire for AirPods 4 and the Keychron K3; the client's notification identity check holds against the real registration.

## Decisions

- Connections only, no disconnect banner. 3 s banner. Launch grace 3 s (the system replays connected devices at registration), wake grace 10 s, one banner per device per 5 s.
- The Bluetooth permission is required (`NSBluetoothAlwaysUsageDescription`); the prompt appears at the first launch after the update.
- Real island sizes: peek 340 x 76, panel 376 x 84 (the mockup's 460 x 84 is mockup scale).

## Not run

- `scripts/verify-settings.sh`: it stops the installed app to run, which needs the user's go-ahead.

## Open, needs a human

- Real AirPods and the Keychron connect: banner appears, name correct (IOBluetooth reports "AirPods 4 (ANC)"), battery shown for AirPods and absent for the Keychron.
- No banner at launch for devices already connected, none within 10 s of waking the Mac.
- Hovering during a banner opens the island; external display; the Settings toggle in the real window.
- The Bluetooth permission prompt on first launch of the signed install.
