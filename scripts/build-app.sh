#!/usr/bin/env bash
# Builds Aura.app and Aura Insights.app (release) with SwiftPM — no Xcode project required.
# Usage: scripts/build-app.sh [--install]   (--install copies it to /Applications and launches it)
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Aura.app"
INSIGHTS="build/Aura Insights.app"
SIGN_ID="${AURA_SIGN_IDENTITY:--}"   # "-" = ad-hoc signature

echo "▸ Compiling (release)…"
swift build -c release --arch arm64 2>&1 | grep -v "ld: warning: search path" || true
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
BIN="$BIN_DIR/Aura"
[ -x "$BIN" ] && [ -x "$BIN_DIR/AuraInsights" ] || { echo "Build failed"; exit 1; }

echo "▸ Assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Aura"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -n "${AURA_VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $AURA_VERSION" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${AURA_BUILD:-1}" "$APP/Contents/Info.plist"
fi
if [ ! -f build/AppIcon.icns ] || [ scripts/make-icon.swift -nt build/AppIcon.icns ]; then
  echo "▸ Rendering icon…"
  swift scripts/make-icon.swift build/AppIcon.icns >/dev/null
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Assembling $INSIGHTS…"
rm -rf "$INSIGHTS"
mkdir -p "$INSIGHTS/Contents/MacOS" "$INSIGHTS/Contents/Resources"
cp "$BIN_DIR/AuraInsights" "$INSIGHTS/Contents/MacOS/AuraInsights"
cp Resources/Insights-Info.plist "$INSIGHTS/Contents/Info.plist"
if [ -n "${AURA_VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $AURA_VERSION" "$INSIGHTS/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${AURA_BUILD:-1}" "$INSIGHTS/Contents/Info.plist"
fi
if [ ! -f build/InsightsIcon.icns ] || [ scripts/make-icon.swift -nt build/InsightsIcon.icns ]; then
  swift scripts/make-icon.swift build/InsightsIcon.icns --insights >/dev/null
fi
cp build/InsightsIcon.icns "$INSIGHTS/Contents/Resources/InsightsIcon.icns"

echo "▸ Signing ($SIGN_ID)…"
TIMESTAMP="--timestamp=none"
[ "$SIGN_ID" != "-" ] && TIMESTAMP="--timestamp"
codesign --force --options runtime $TIMESTAMP \
  --entitlements Resources/Aura.entitlements --sign "$SIGN_ID" "$APP"
codesign --verify --strict "$APP"
codesign --force --options runtime $TIMESTAMP --sign "$SIGN_ID" "$INSIGHTS"
codesign --verify --strict "$INSIGHTS"

if [ "${1:-}" = "--install" ]; then
  echo "▸ Installing to /Applications…"
  pkill -x Aura 2>/dev/null && sleep 1 || true
  pkill -x AuraInsights 2>/dev/null || true
  rm -rf /Applications/Aura.app "/Applications/Aura Insights.app"
  cp -R "$APP" /Applications/Aura.app
  cp -R "$INSIGHTS" "/Applications/Aura Insights.app"
  open /Applications/Aura.app
  echo "✓ Aura and Aura Insights installed; Aura is running."
else
  echo "✓ Built $APP and $INSIGHTS"
fi
