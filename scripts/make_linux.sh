#!/usr/bin/env bash
#
# Build a versioned Linux release tarball for QuickVPN.
#
# Produces build/quickvpn-v<version>-linux-<arch>.tar.gz containing the Flutter
# bundle plus a .desktop entry, the app icon (logo), and an install.sh that
# registers both so the logo shows in the application menu.
#
# Run this ON Linux — Flutter cannot cross-compile desktop targets from macOS.
#
# Usage: scripts/make_linux.sh

set -euo pipefail

FLUTTER="${FLUTTER:-flutter}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="QuickVPN"
ICON_SRC="$ROOT_DIR/assets/quick_icon_1024.png"
VERSION="$(awk '/^version:/ {split($2, a, "+"); print a[1]; exit}' pubspec.yaml)"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) ARCH="x64" ;;
  aarch64 | arm64) ARCH="arm64" ;;
esac

echo "==> flutter build linux --release"
"$FLUTTER" build linux --release

BUNDLE="$(ls -d build/linux/*/release/bundle 2>/dev/null | head -1 || true)"
[[ -d "$BUNDLE" ]] || { echo "error: build bundle not found under build/linux" >&2; exit 1; }

OUT="build/quickvpn-v${VERSION}-linux-${ARCH}.tar.gz"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/quickvpn-linux.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
PKG="$STAGE/$APP_NAME"
mkdir -p "$PKG"

echo "==> Staging bundle"
cp -R "$BUNDLE/." "$PKG/"

# Logo + desktop entry so the app shows branded in the menu after install.
if [[ -f "$ICON_SRC" ]]; then
  cp "$ICON_SRC" "$PKG/quickvpn.png"
fi
cat > "$PKG/quickvpn.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=QuickVPN
Comment=Fast, minimal OpenVPN client
Exec=quickvpn
Icon=quickvpn
Terminal=false
Categories=Network;Utility;
DESKTOP

cat > "$PKG/install.sh" <<'INSTALL'
#!/usr/bin/env bash
# Install QuickVPN into ~/.local for the current user (no root needed).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.local/share/quickvpn"
mkdir -p "$DEST" "$HOME/.local/bin" "$HOME/.local/share/applications" \
         "$HOME/.local/share/icons/hicolor/512x512/apps"
cp -R "$HERE/." "$DEST/"
ln -sf "$DEST/quickvpn" "$HOME/.local/bin/quickvpn"
[[ -f "$HERE/quickvpn.png" ]] && \
  install -m644 "$HERE/quickvpn.png" \
    "$HOME/.local/share/icons/hicolor/512x512/apps/quickvpn.png"
sed "s|^Exec=quickvpn$|Exec=$DEST/quickvpn|" "$HERE/quickvpn.desktop" \
  > "$HOME/.local/share/applications/quickvpn.desktop"
echo "Installed. Launch 'QuickVPN' from your app menu (or run: quickvpn)."
echo "Note: connecting needs the openvpn client — sudo apt install openvpn (or dnf/pacman)."
INSTALL
chmod +x "$PKG/install.sh"

echo "==> Packaging"
rm -f "$OUT"
tar -C "$STAGE" -czf "$OUT" "$APP_NAME"
echo "==> Built: $OUT"
