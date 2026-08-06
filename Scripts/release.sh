#!/usr/bin/env bash
# Build a Release "Hayward Monitor.app", Developer ID sign with Hardened
# Runtime + App Sandbox entitlements, notarize via Apple, staple the ticket,
# and package it as a distributable .dmg with a Sparkle-signed appcast.
#
# ┌──────────────────────────────────────────────────────────────────────────┐
# │ SPARKLE SIGNING KEY — DO NOT REGENERATE                                  │
# │                                                                          │
# │ Updates are EdDSA-signed with the private key in the login keychain      │
# │ under account "HaywardMonitor" (used by sign_update below). Its public   │
# │ half is embedded in the app as SUPublicEDKey in project.yml:             │
# │     wEiO717vayiZ+jMKejHV3TZFsm+Mm7IjKO/1+zJD/VE=                         │
# │                                                                          │
# │ NEVER run `generate_keys` again for this account and NEVER change        │
# │ SUPublicEDKey — every installed app would reject all future updates.     │
# │ Back the key up: generate_keys -x backup.txt --account HaywardMonitor    │
# └──────────────────────────────────────────────────────────────────────────┘
#
# Usage: ./Scripts/release.sh <version>     e.g. ./Scripts/release.sh 1.0.0
#
# Prerequisites:
#   - "Developer ID Application: Vincent LAURIAT (KFLACS69T9)" in the login
#     keychain.
#   - notarytool credentials under the shared keychain profile
#     "AppliMacVincentGithub".
#
# Outputs release/HaywardMonitor-<version>.dmg (notarized, stapled) and
# refreshes appcast.xml at the repo root. Does NOT push to GitHub — prints
# the suggested `gh release create` command.

set -euo pipefail

VERSION="${1:?Usage: ./Scripts/release.sh <version>  (e.g. ./Scripts/release.sh 1.0.0)}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Hayward Monitor"
SCHEME="HaywardMonitor"
DMG_BASENAME="HaywardMonitor"
SPARKLE_ACCOUNT="HaywardMonitor"
ENTITLEMENTS="$ROOT/HaywardMonitor/HaywardMonitor.entitlements"

# 1. Sanity check: project.yml must declare the same MARKETING_VERSION
if ! grep -q "MARKETING_VERSION: \"$VERSION\"" project.yml; then
  echo "✗ MARKETING_VERSION in project.yml does not match $VERSION" >&2
  grep "MARKETING_VERSION" project.yml | sed 's/^/    /' >&2
  echo "  Bump project.yml first, then re-run." >&2
  exit 1
fi

# 2. Regenerate xcodeproj
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "✗ XcodeGen not installed. brew install xcodegen" >&2
  exit 1
fi
echo "→ xcodegen generate"
xcodegen generate >/dev/null

# 3. Build Release
# CODE_SIGNING_ALLOWED=NO works around the macOS `com.apple.provenance`
# xattr that breaks codesign in CLI. We sign manually below after a clean
# xattr scrub.
echo "→ xcodebuild Release"
xcodebuild -project HaywardMonitor.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -5

APP="$ROOT/build/Build/Products/Release/$APP_NAME.app"
if [ ! -d "$APP" ]; then
  echo "✗ Build did not produce $APP" >&2
  exit 1
fi

# 4. Stage to a clean directory (ditto --noextattr scrubs the xattrs that
# make `codesign --force` fail in place), then sign deepest-first.
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Vincent LAURIAT (KFLACS69T9)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AppliMacVincentGithub}"

STAGING_DIR="$(mktemp -d)"
STAGING="$STAGING_DIR/$APP_NAME.app"
echo "→ Staging to $STAGING_DIR"
ditto --norsrc --noextattr --noacl "$APP" "$STAGING"

# Apple's timestamp server is intermittently flaky — retry with backoff.
# Sparkle's nested components carry their own entitlements: preserve them.
codesign_ts() {
  local target="$1"; shift
  local attempt
  for attempt in 1 2 3 4 5; do
    if codesign --force --options runtime --timestamp "$@" --sign "$SIGNING_IDENTITY" "$target" 2>&1; then
      return 0
    fi
    if [ "$attempt" -lt 5 ]; then
      echo "  ↻ codesign failed (attempt $attempt/5), retrying in 5s…"
      sleep 5
    fi
  done
  echo "✗ codesign $target failed after 5 attempts" >&2
  return 1
}

echo "→ Codesigning Sparkle.framework nested binaries (deepest first)"
SPARKLE_FW="$STAGING/Contents/Frameworks/Sparkle.framework"
SPARKLE_VER="$SPARKLE_FW/Versions/B"
codesign_ts "$SPARKLE_VER/Autoupdate" --preserve-metadata=entitlements
codesign_ts "$SPARKLE_VER/XPCServices/Downloader.xpc" --preserve-metadata=entitlements
codesign_ts "$SPARKLE_VER/XPCServices/Installer.xpc" --preserve-metadata=entitlements
codesign_ts "$SPARKLE_VER/Updater.app" --preserve-metadata=entitlements
codesign_ts "$SPARKLE_FW"

echo "→ Codesigning the app with Developer ID + Hardened Runtime + sandbox entitlements"
codesign_ts "$STAGING" --entitlements "$ENTITLEMENTS"
codesign --verify --strict --deep "$STAGING"

RELEASE_DIR="$ROOT/release"
mkdir -p "$RELEASE_DIR"
DMG="$RELEASE_DIR/$DMG_BASENAME-$VERSION.dmg"
rm -f "$DMG"

# 5. DMG: signed .app + /Applications alias.
DMG_LAYOUT_DIR="$STAGING_DIR/dmg-layout"
mkdir -p "$DMG_LAYOUT_DIR"
ditto --norsrc --noextattr --noacl "$STAGING" "$DMG_LAYOUT_DIR/$APP_NAME.app"
ln -s /Applications "$DMG_LAYOUT_DIR/Applications"

echo "→ Creating $DMG"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$DMG_LAYOUT_DIR" \
  -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null

rm -rf "$STAGING_DIR"

# 6. Notarize, then staple so the app launches offline.
echo "→ Submitting $DMG to Apple notary service (this takes 2–5 min)"
xcrun notarytool submit "$DMG" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

echo "→ Stapling notarization ticket to the DMG"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

# 7. Sparkle EdDSA signature + appcast.xml refresh.
SPARKLE_VERSION="2.9.1"
SPARKLE_TOOLS="$ROOT/.sparkle-tools"
if [ ! -x "$SPARKLE_TOOLS/bin/sign_update" ]; then
  echo "→ Fetching Sparkle $SPARKLE_VERSION tools (one-time setup)"
  mkdir -p "$SPARKLE_TOOLS"
  curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
    | tar -xJ -C "$SPARKLE_TOOLS"
fi

echo "→ Signing $DMG with Sparkle EdDSA key"
# sign_update returns: sparkle:edSignature="..." length="<bytes>"
SPARKLE_SIG_LINE=$("$SPARKLE_TOOLS/bin/sign_update" --account "$SPARKLE_ACCOUNT" "$DMG")

# Sparkle compares <sparkle:version> against CFBundleVersion (build number),
# not the marketing version — read the one baked into the built app.
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")

echo "→ Writing $ROOT/appcast.xml (sparkle:version=$BUILD_NUMBER, shortVersionString=$VERSION)"
PUB_DATE=$(date -R)
cat > "$ROOT/appcast.xml" <<APPCAST
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Hayward Monitor</title>
    <link>https://raw.githubusercontent.com/vincentlauriat/HaywardMonitor/main/appcast.xml</link>
    <description>Hayward Monitor release feed</description>
    <language>en</language>
    <item>
      <title>v$VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/vincentlauriat/HaywardMonitor/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <enclosure
        url="https://github.com/vincentlauriat/HaywardMonitor/releases/download/v$VERSION/$DMG_BASENAME-$VERSION.dmg"
        type="application/octet-stream"
        $SPARKLE_SIG_LINE />
    </item>
  </channel>
</rss>
APPCAST

DMG_SIZE=$(ls -lh "$DMG" | awk '{print $5}')
echo ""
echo "✅ Built, signed, notarized, stapled and Sparkle-signed: $DMG ($DMG_SIZE)"
echo "✅ appcast.xml written for v$VERSION"
echo ""
echo "Next steps to publish on GitHub:"
echo "  1. gh release create v$VERSION ./release/$DMG_BASENAME-$VERSION.dmg --title \"v$VERSION\" --notes-file release/release-notes-$VERSION.md"
echo "  2. git add appcast.xml && git commit -m 'docs: appcast for v$VERSION' && git push"
