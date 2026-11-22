# Camera acceptance — 2026-11-22

Branch: `camera-preview`.

## Scope and geometry

Music/Camera buttons extend the existing HeaderTabIcon strip; Music is selected initially. Camera shows the system default device through an aspect-fill AVCaptureVideoPreviewLayer, mirrored initially, with one mirror toggle. Denied access shows inline recovery text and a Camera privacy settings button. No recording or device selection.

The checkout's existing island is **400 × 200**, not the brief's stated 360 × 165. The existing root geometry and gear were preserved; the camera content is 332 × 118 at x14/y36. This discrepancy was raised with the user during implementation. No mockup changes.

## Automated evidence

- Tests first: missing-type failure captured in `.build/camera-red.log`, then pure camera tests passed. Full `swift test`: **314 tests, 24 suites**, all passed. Covers initial hover, permission denial, late grants after collapse/lock/tab switch/quit, stop and restart, revocation, and synchronous AppState delivery.
- `swift build`: passed, zero warnings. Release bundle build also passed without warnings. Generated Info.plist contains NSCameraUsageDescription.
- `scripts/verify-view-layout.sh`: passed. Offscreen cacheDisplay checks include the fake 332 × 118 camera preview, denied recovery text, collapsed camera invisibility, unchanged island silhouette and unchanged gear pixels. No window or screenshot capture.
- `scripts/verify-camera.sh`: passed with SHIMA_FAKE_CAMERA=1. Uses scripts/drive.swift CGEvent clicks at the actual header geometry and filters local.shima logs to this checkout's app pid. Both Camera and Music buttons logged active=false. Hover-only segment contained no session start. Seven start/stop pairs covered tab switch, simulated lock/unlock, display sleep/system sleep with independent wake gates, permission revocation/recovery, collapse/reopen and delayed permission denial. Mirror toggle logged false.
- `scripts/verify-focus.sh --clicks`: passed; three playback commands logged active=false/key=false; frontmost remained Kaze. Updated the check to select Music first so prior Camera selection cannot swallow its playback clicks.
- `scripts/verify-idle.sh`: passed after the camera and playback interaction checks: **0.000 CPU seconds / 60 s, 57 MB RSS**, static check clean, no timer callbacks in sample. The 60 MB RSS gate is unchanged.

Local raw evidence is in `.build/camera-{build,tests,layout,verification,focus,idle}.log` (untracked). The installed /Applications instance was left running and untouched. Test launch only commands fake Spotify and fake Camera.

## Review

Independent core and glue review found and resolved independent system/display wake state, fake permission/session logging and denied-state coverage gaps. Final whole-branch review passed after adding the own-pid fake-camera probe before any verification clicks and reviewing the bounded brand-image decode. No remaining source findings.

## Memory correction

The first post-interaction idle check used 0.000 CPU seconds but failed the unchanged RSS limit at 62 MB. Investigation found about 6.9 MB of decoded brand images: 940 px Spotify PNGs displayed at 12–28 pt. BrandAssets now caches thumbnails capped at 128 px (the largest existing mark is 64 pt at 2x). Original assets are untouched, and offscreen glyph/layout checks still pass. The final idle measurement follows both camera and playback interactions, rather than only a fresh launch.

## HUMAN checks

- **Real camera:** launch with a stable SHIMA_SIGN_ID and without SHIMA_FAKE_CAMERA. Hover alone must leave camera off; click Camera, confirm live image, default mirroring, aspect fill and mirror toggle.
- **Permission prompt:** first Camera opening requests access. Verify Allow and Deny, inline denied recovery and the Camera privacy settings link. No real system prompt was triggered in automated checks.
- **Green light:** with Camera open, collapse the island and confirm the camera indicator turns off; re-open, switch to Music, lock/sleep and quit to confirm the real hardware stops appropriately.

Real camera image, system permission dialog and hardware indicator remain human verification; automated tests never opened a real camera or requested Screen Recording.
