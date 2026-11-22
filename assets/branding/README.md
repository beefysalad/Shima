# Shima branding

The current identity is a split-current **S**: two opposing ribbons, curved on
the outside and cut diagonally at their ends. A channel of negative space runs
between them. The half-turn symmetry gives the mark a sense of motion while
keeping a compact silhouette. The palette stays neon orange on black.
SVGs use real paths with outlined lettering, no fonts or embedded bitmaps.

- `shima-mark.svg`: standalone orange mark on transparent background.
- `shima-logo.svg` and `shima-logo-light.svg`: full README logo with attribution.
- `shima-lockup.svg`: compact dark logo without attribution.
- `shima-icon.svg`: 256 × 256 rounded black tile with a subtle neutral edge.
- `shima-app-icon-macos.svg`: artwork on a 1024 × 1024 canvas, with 100-unit margins.
- `shima-icon-512.png` and `shima.icns`: platform exports from the SVGs.
- `previews/`: archived explorations and prompts from earlier directions.

The mark is solid `#ff6500`; there is no gradient. Its canonical grid is
160 × 160, with two identical paths related by a half-turn about (80, 80).
The gap is transparent and follows the background. The dark background is
`#000000`, lettering `#f5f0eb`, and byline
`#b5a99f`. The light variant uses `#fff8f1`, `#24201d`, and `#73665c` respectively,
with the same orange mark. Keep the geometry identical across variants.

To regenerate the SVGs on macOS, from the repository root:

```sh
swift assets/branding/generate.swift
```

The generator uses CoreText to outline Avenir Next Demi Bold and Menlo Regular.
These fonts are needed only to regenerate lettering, never to display the SVGs.

To regenerate the PNG and macOS ICNS (requires ImageMagick and macOS `iconutil`):

```sh
sh assets/branding/export.sh
```

Exports use a temporary directory inside the repository's ignored `.build/`.
`scripts/bundle.sh` includes `shima.icns` as the macOS application icon.

Spotify icons are the original assets from Spotify’s official developer kit:
https://developer.spotify.com/images/guidelines/design/2024-spotify-logo-icon.zip
SVG originals are retained here; the unmodified PNGs are bundled in Sources/Shima/Resources. Spotify trademarks belong to Spotify.
ShimaBrand.png is copied from the canonical shima-icon-512.png export.
ShimaMark.png is a raster export of the canonical shima-mark.svg for the menu bar.
