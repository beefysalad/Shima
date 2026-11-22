# Camera acceptance — 2026-11-22

Branch: `camera-preview`.

## Scope and geometry

Outlined Home/Music/Camera icons (drawn from the mockup's glyphs) form the header strip upper-left; Home opens Settings and replaces the gear; Music is selected initially and restored on collapse. Every subsequent Camera opening needs a click. Camera shows the system default device through an aspect-fill AVCaptureVideoPreviewLayer, mirrored initially, with the mockup's right column (Live, Mirror, Switch camera, Close, note). Denied access shows inline recovery text and a Camera privacy settings button. No recording or effects. Switch camera cycles the discovered devices and is dimmed with one.

The checkout's existing island is **400 × 200**, not the brief's stated 360 × 165. The camera panel follows the approved `mockup/index.html`: preview 258 × 146 at x14/y40, control column 104 pt wide at x282. The mockup was updated (Home button upper-left, smaller icons) and the playback controls are centred in the text column.

## Automated evidence

- Tests first: missing-type failure captured in `.build/camera-red.log`, then pure camera tests passed. Full `swift test`: **316 tests, 24 suites**, all passed. Covers initial hover, permission denial, late grants after collapse/lock/tab switch/quit, stop and restart, revocation, and synchronous AppState delivery.
- `swift build`: passed, zero warnings. Release bundle build also passed without warnings. Generated Info.plist contains NSCameraUsageDescription.
- `scripts/verify-view-layout.sh`: passed. Offscreen cacheDisplay checks include the fake 258 × 146 camera preview, denied recovery text, collapsed camera invisibility, unchanged island silhouette and unchanged Home button pixels. The preview replacement regression mounts one standalone layer in two successive hosts and proves the old host cannot resize or detach the new host’s layer (no capture session). No window or screenshot capture.
- `scripts/verify-camera.sh`: passed with SHIMA_FAKE_CAMERA=1. Uses scripts/drive.swift CGEvent clicks at the actual header geometry and filters local.shima logs to this checkout's app pid. Both Camera and Music buttons logged active=false. Both initial hover and hover after collapsing from Camera contained no session start. Eight start/stop pairs covered tab switch, simulated lock/unlock and fast user switching, display sleep/system sleep with independent wake gates, permission revocation/return-from-Settings activation refresh, collapse/explicit Camera reopen and delayed permission denial. Mirror toggle logged false.
- `scripts/verify-focus.sh --clicks`: passed; three playback commands logged active=false/key=false; frontmost remained Kaze. Updated the check to select Music first so prior Camera selection cannot swallow its playback clicks.
- `scripts/verify-idle.sh`: passed after the camera and playback interaction checks: **0.000 CPU seconds / 60 s, 56 MB RSS**, static check clean, no timer callbacks in sample. The 60 MB RSS gate is unchanged.

Local raw evidence is in `.build/camera-fixes-{build,tests,layout,interaction,focus,idle}.log` and `.build/camera-verification.log` (untracked). The installed /Applications instance was left running and untouched. Test launch only commands fake Spotify and fake Camera.

## Review

Independent core and glue review found and resolved independent system/display wake state, fake permission/session logging and denied-state coverage gaps. Final whole-branch review passed after adding the own-pid fake-camera probe before any verification clicks and reviewing the bounded brand-image decode. The review correction pass additionally fixed the hover reset, asynchronous termination, preview ownership and device recovery, activation/user-session events, shared screen coordinates, and copied colored menu logo. No merge or new commit was made for these corrections.

## Memory correction

The first post-interaction idle check used 0.000 CPU seconds but failed the unchanged RSS limit at 62 MB. Investigation found about 6.9 MB of decoded brand images: 940 px Spotify PNGs displayed at 12–28 pt. BrandAssets now caches thumbnails capped at 128 px (the largest existing mark is 64 pt at 2x). Original assets are untouched, and offscreen glyph/layout checks still pass. The final idle measurement follows both camera and playback interactions, rather than only a fresh launch.

## Review corrections

- Quit uses AppKit terminateLater and an asynchronous capture-queue completion; no main-thread queue.sync remains. Completion runs in AppKit’s modal run-loop modes. `scripts/verify-camera.sh --quit` verifies that fake capture stops and the checkout process exits; quit commands require a matching PID so other worktrees remain running.
- Stopping removes capture inputs; each reopening resolves the system default again. Device disconnection/runtime errors stop and clear the bad input; an executing-run epoch prevents delayed errors from clearing a newer session. Real reconnection remains a HUMAN check.
- The shared input helper compiles the app’s ScreenLocator and refuses pointer checks when there is no built-in display target.
- The menu logo stays colored; a copy is resized, leaving BrandAssets’ cached object unchanged.
- Collapse reset was tested first: `.build/camera-hover-reset-red.log` records eight failing assertions before the fix, followed by passing `.build/camera-hover-reset-green.log`.

## HUMAN checks

- **Real camera:** launch with a stable SHIMA_SIGN_ID and without SHIMA_FAKE_CAMERA. Hover alone must leave camera off; click Camera, confirm live image, default mirroring, aspect fill, the Mirror tile and Switch camera (needs two cameras).
- **Permission prompt:** first Camera opening requests access. Verify Allow and Deny, inline denied recovery and the Camera privacy settings link. No real system prompt was triggered in automated checks.
- **Green light:** with Camera open, collapse the island and confirm the camera indicator turns off; re-open, switch to Music, lock/sleep and quit to confirm the real hardware stops appropriately.

- **Device recovery and busy quit:** unplug/reconnect an external or Continuity camera, reopen Camera and confirm the current default works; quit while the device is starting and confirm the UI stays responsive. These hardware paths were reviewed but not exercised with a real device.

Real camera image, system permission dialog and hardware indicator remain human verification; automated tests never opened a real camera or requested Screen Recording.
