#!/usr/bin/env bash
# Packages build/*.app into build/Aura.zip (used by the in-app updater) and build/Aura.dmg.
# Optional notarization when APPLE_ID, APPLE_TEAM_ID and APPLE_APP_PASSWORD are set.
set -euo pipefail
cd "$(dirname "$0")/.."

rm -f build/Aura.zip build/Aura.dmg
# Zip containing both apps at its root.
STAGE="$(mktemp -d)"
ditto "build/Aura.app" "$STAGE/Aura.app"
ditto "build/Aura Insights.app" "$STAGE/Aura Insights.app"
(cd "$STAGE" && ditto -c -k --sequesterRsrc . "$OLDPWD/build/Aura.zip")

if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ]; then
  echo "▸ Notarizing…"
  xcrun notarytool submit build/Aura.zip --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" --wait
  xcrun stapler staple "build/Aura.app"
  xcrun stapler staple "build/Aura Insights.app"
  rm -rf "$STAGE"/*.app
  ditto "build/Aura.app" "$STAGE/Aura.app"
  ditto "build/Aura Insights.app" "$STAGE/Aura Insights.app"
  rm -f build/Aura.zip
  (cd "$STAGE" && ditto -c -k --sequesterRsrc . "$OLDPWD/build/Aura.zip")
fi

echo "▸ Creating DMG…"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Aura" -srcfolder "$STAGE" -ov -format UDZO build/Aura.dmg >/dev/null
rm -rf "$STAGE"
echo "✓ build/Aura.zip and build/Aura.dmg"
