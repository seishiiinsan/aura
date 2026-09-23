#!/usr/bin/env bash
# Builds Aura.app (release) with SwiftPM — no Xcode project required.
# Usage: scripts/build-app.sh [--install]   (--install copies it to /Applications and launches it)
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Aura.app"
SIGN_ID="${AURA_SIGN_IDENTITY:--}"   # "-" = ad-hoc signature

echo "▸ Compiling (release)…"
swift build -c release --arch arm64 2>&1 | grep -v "ld: warning: search path" || true
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Aura"
[ -x "$BIN" ] || { echo "Build failed"; exit 1; }

echo "▸ Assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Aura"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ ! -f build/AppIcon.icns ] || [ scripts/make-icon.swift -nt build/AppIcon.icns ]; then
  echo "▸ Rendering icon…"
  swift scripts/make-icon.swift build/AppIcon.icns >/dev/null
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Signing ($SIGN_ID)…"
codesign --force --options runtime --timestamp=none \
  --entitlements Resources/Aura.entitlements --sign "$SIGN_ID" "$APP"
codesign --verify --strict "$APP"

if [ "${1:-}" = "--install" ]; then
  echo "▸ Installing to /Applications…"
  pkill -x Aura 2>/dev/null && sleep 1 || true
  rm -rf /Applications/Aura.app
  cp -R "$APP" /Applications/Aura.app
  open /Applications/Aura.app
  echo "✓ Aura installed and running."
else
  echo "✓ Built $APP"
fi
