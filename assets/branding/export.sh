#!/bin/sh
# Run from any directory. Requires ImageMagick and macOS iconutil.
set -eu
branding_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
iconset_dir=$(mktemp -d "${TMPDIR:-/tmp}/shima-branding.XXXXXX")
trap 'rm -rf "$iconset_dir"' EXIT HUP INT TERM
mkdir "$iconset_dir/shima.iconset"
magick -background none -density 384 "$branding_dir/shima-icon.svg" -resize 512x512 "$branding_dir/shima-icon-512.png"
for size in 16 32 128 256 512; do
    magick -background none -density 96 "$branding_dir/shima-app-icon-macos.svg" -resize "${size}x${size}" "$iconset_dir/shima.iconset/icon_${size}x${size}.png"
    double_size=$((size * 2))
    magick -background none -density 96 "$branding_dir/shima-app-icon-macos.svg" -resize "${double_size}x${double_size}" "$iconset_dir/shima.iconset/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$iconset_dir/shima.iconset" -o "$branding_dir/shima.icns"
