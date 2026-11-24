#!/bin/sh
# Regenerate Resources/AppIcon.icns from the hand-drawn vectors (needs rsvg-convert):
# Resources/AppIcon.svg for 64 px and up, Resources/AppIcon-small.svg (simplified art) for 16 and 32 px.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
set_dir=$(mktemp -d)/AppIcon.iconset
mkdir -p "$set_dir"
render() { # <pixels> <file name>
  art="$root/Resources/AppIcon.svg"
  [ "$1" -le 32 ] && art="$root/Resources/AppIcon-small.svg"
  rsvg-convert -w "$1" -h "$1" "$art" -o "$set_dir/$2"
}
for s in 16 32 128 256 512; do
  render "$s" "icon_${s}x${s}.png"
  render $((s * 2)) "icon_${s}x${s}@2x.png"
done
iconutil -c icns "$set_dir" -o "$root/Resources/AppIcon.icns"
rm -rf "$(dirname "$set_dir")"
printf '%s\n' "$root/Resources/AppIcon.icns"
