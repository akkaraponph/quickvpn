#!/usr/bin/env bash
#
# Build a branded macOS .dmg installer for Quick.
#
# Produces a styled "drag to Applications" window: dark hero background art,
# positioned icons, and a custom volume icon. Driven by the Makefile `dmg`
# target, but can also be run standalone after `make build-macos`.
#
# Usage: scripts/make_dmg.sh <App.app path> <output.dmg> [volume name]

set -euo pipefail

APP_SRC="${1:?path to the built .app is required}"
DMG_OUT="${2:?output .dmg path is required}"
VOL_NAME="${3:-Quick}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BG_SVG="$ROOT_DIR/assets/dmg/background.svg"
ICON_SRC="$ROOT_DIR/assets/quick_icon_1024.png"

APP_NAME="$(basename "$APP_SRC")"          # e.g. quickvpn.app
WIN_W=640; WIN_H=400; ICON_SIZE=128

WORK="$(mktemp -d "${TMPDIR:-/tmp}/quickvpn-dmg.XXXXXX")"
STAGE="$WORK/stage"
RW_DMG="$WORK/rw.dmg"
MOUNT_DEV=""

cleanup() {
  if [[ -n "$MOUNT_DEV" ]] && hdiutil info | grep -q "$MOUNT_DEV"; then
    hdiutil detach "$MOUNT_DEV" -quiet -force || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

command -v rsvg-convert >/dev/null || { echo "error: rsvg-convert not found (brew install librsvg)" >&2; exit 1; }
[[ -d "$APP_SRC" ]] || { echo "error: app not found: $APP_SRC" >&2; exit 1; }

echo "==> Rendering installer background"
mkdir -p "$STAGE/.background"
rsvg-convert -w "$WIN_W"            -h "$WIN_H"            "$BG_SVG" -o "$WORK/bg.png"
rsvg-convert -w "$((WIN_W * 2))"    -h "$((WIN_H * 2))"    "$BG_SVG" -o "$WORK/bg@2x.png"
# Combine into one HiDPI-aware TIFF so Retina displays get the crisp 2x art.
tiffutil -cathidpicheck "$WORK/bg.png" "$WORK/bg@2x.png" -out "$STAGE/.background/background.tiff" >/dev/null

echo "==> Building volume icon"
if [[ -f "$ICON_SRC" ]]; then
  ICONSET="$WORK/VolumeIcon.iconset"; mkdir -p "$ICONSET"
  for sz in 16 32 128 256 512; do
    sips -z "$sz"            "$sz"            "$ICON_SRC" --out "$ICONSET/icon_${sz}x${sz}.png"     >/dev/null
    sips -z "$((sz * 2))"    "$((sz * 2))"    "$ICON_SRC" --out "$ICONSET/icon_${sz}x${sz}@2x.png"  >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$STAGE/.VolumeIcon.icns"
fi

echo "==> Staging payload"
cp -R "$APP_SRC" "$STAGE/$APP_NAME"
ln -s /Applications "$STAGE/Applications"

echo "==> Creating read/write image"
# Size to content plus slack so Finder can write its .DS_Store / attributes.
SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) + 40 ))
hdiutil create -srcfolder "$STAGE" -volname "$VOL_NAME" -fs HFS+ \
  -format UDRW -size "${SIZE_MB}m" -ov "$RW_DMG" >/dev/null

echo "==> Mounting"
MOUNT_INFO="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG")"
MOUNT_DEV="$(echo "$MOUNT_INFO" | grep -E '^/dev/' | head -1 | awk '{print $1}')"
VOL_PATH="/Volumes/$VOL_NAME"

echo "==> Applying window layout"
osascript - "$VOL_NAME" "$APP_NAME" <<APPLESCRIPT
on run argv
  set volName to item 1 of argv
  set appName to item 2 of argv
  tell application "Finder"
    tell disk volName
      open
      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      set the bounds of container window to {400, 140, ${WIN_W} + 400, ${WIN_H} + 140}
      set opts to the icon view options of container window
      set arrangement of opts to not arranged
      set icon size of opts to ${ICON_SIZE}
      set text size of opts to 12
      set background picture of opts to file ".background:background.tiff"
      set position of item appName of container window to {176, 190}
      set position of item "Applications" of container window to {464, 190}
      close
      open
      update without registering applications
      delay 1.5
    end tell
  end tell
end run
APPLESCRIPT

# Mark the volume so the custom .VolumeIcon.icns is used.
if [[ -f "$VOL_PATH/.VolumeIcon.icns" ]]; then
  SetFile -a C "$VOL_PATH" || true
fi

sync
hdiutil detach "$MOUNT_DEV" -quiet
MOUNT_DEV=""

echo "==> Compressing"
rm -f "$DMG_OUT"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_OUT" >/dev/null

echo "==> Built: $DMG_OUT"
