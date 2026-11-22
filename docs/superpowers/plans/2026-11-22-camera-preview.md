# Camera implementation plan

1. PURE: tests first for CameraModel lifecycle and permission races; CameraClient protocol, fake, coordinator, selected tab in AppState. Fresh implementer and independent review.
2. GLUE: AVFoundation serial-queue client, preview layer, screen notifications, synchronous lifecycle delivery, header strip and denied/mirror controls. Preserve root layout and gear. Independent review.
3. SCRIPT: camera usage plist key, fake launch mode, event injection hooks, offscreen camera coverage and CGEvent header click proof. Stop if header icons swallow clicks.
4. Verify warning-free swift build, swift test, layout, focus and idle checks. Whole-branch independent review and small explicit-path commits.
5. HUMAN: real camera image and mirroring, first-use system permission prompt, green light off on collapse; record outstanding checks in camera-acceptance.md.
