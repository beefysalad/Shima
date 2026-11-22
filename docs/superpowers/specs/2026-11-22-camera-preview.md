# Camera preview

Click Camera in the existing menu-bar-height header to see the default camera, aspect-fill and mirrored by default. The header is the mockup's: outlined Home (opens Settings), Music and Camera icons upper-left, with no gear on the right. Music is the initial tab and is restored on every collapse, so hovering again cannot start capture without another Camera click. The Camera panel matches `mockup/index.html`: preview on the left; Live, Mirror, Switch camera (cycles cameras, dimmed with one), Close and a note in a column on the right. No recording, effects, or networking.

The pure camera model permits a session only when expanded, Camera selected, permission granted, screen awake and unlocked, user session active, and not quitting. Permission is requested on first Camera opening. Late permission results cannot start a hidden session. Collapse, Music selection, sleep, lock and quit stop it. Quit awaits asynchronous capture cleanup without blocking the main thread. Each opening resolves the current default camera afresh. Permission refreshes on application activation. Session operations run on a serial background queue; idle uses notifications, never polling.

Denied access shows an inline recovery message and Camera privacy settings button. Fake camera mode uses a gradient and local.shima start/stop logs without touching AVFoundation hardware or permission.

Geometry: the island is 400x200; the preview is 258x146 with a 104 pt control column (`NowPlayingLayout.cameraPreview` and friends). `mockup/index.html` is the approved visual reference and the real UI must match it. Prove header clicks using CGEvent and logs; if swallowed, stop and report without relocating icons.

Human verification: actual live image, permission prompt, green indicator off on collapse. Automated verification uses fake clients, event injection, logs and offscreen rendering only.
