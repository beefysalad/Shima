# Shima branding

The current identity is the rounded floating island with a small pill cutout,
in neon orange on black. SVGs use real paths with outlined lettering, no fonts
or embedded bitmaps. This direction replaces the earlier violet Kaze studies.

- `shima-mark.svg`: standalone orange mark on transparent background.
- `shima-logo.svg` and `shima-logo-light.svg`: full README logo with attribution.
- `shima-lockup.svg`: compact dark logo without attribution.
- `shima-icon.svg`: 256 × 256 rounded black tile with a thin orange outline.
- `shima-app-icon-macos.svg`: artwork on a 1024 × 1024 canvas, with 100-unit margins.
- `shima-icon-512.png` and `shima.icns`: platform exports from the SVGs.
- `previews/`: imagegen explorations and their prompts; the floating island is concept 8.

The mark is solid `#ff6500`; there is no gradient. Its canonical coordinates
span approximately (0, 7) to (160, 78). The pill is negative space, so it follows
the background. The dark background is `#000000`, lettering `#f5f0eb`, and byline
`#b5a99f`. The light variant uses `#fff8f1`, `#24201d`, and `#73665c` respectively,
with the same orange mark. Keep the geometry identical across variants.

To regenerate the SVGs on macOS, from the repository root:

```sh
swift assets/branding/generate.swift
```

The generator uses CoreText to outline Arial Rounded MT Bold and Menlo Regular.
These fonts are needed only to regenerate lettering, never to display the SVGs.

To regenerate the PNG and macOS ICNS (requires ImageMagick and macOS `iconutil`):

```sh
sh assets/branding/export.sh
```
