#!/bin/sh
# Regenerate Resources/AppIcon.icns from the hand-drawn Resources/AppIcon.svg (needs rsvg-convert).
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
set_dir=$(mktemp -d)/AppIcon.iconset
mkdir -p "$set_dir"
for s in 16 32 128 256 512; do
  rsvg-convert -w "$s" -h "$s" "$root/Resources/AppIcon.svg" -o "$set_dir/icon_${s}x${s}.png"
  rsvg-convert -w $((s * 2)) -h $((s * 2)) "$root/Resources/AppIcon.svg" -o "$set_dir/icon_${s}x${s}@2x.png"
done
iconutil -c icns "$set_dir" -o "$root/Resources/AppIcon.icns"
rm -rf "$(dirname "$set_dir")"
printf '%s\n' "$root/Resources/AppIcon.icns"
