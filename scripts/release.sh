#!/bin/bash
# Build, sign, notarize and publish a Grains release, then update the Sparkle appcast.
# Ported from Steam Shelf's scripts/release.sh (decision D19).
#
#   scripts/release.sh 0.2.0                  # full release: notarize, staple, appcast, tag, push, GitHub release
#   scripts/release.sh 0.2.0 --dry-run        # build + sign + appcast locally; no notarize/upload/push
#   scripts/release.sh 0.2.0 --skip-notarize  # local Developer ID-signed build + zip only; no notarize,
#                                             # no appcast change, nothing published
#
# One-time setup (needs an app-specific password from appleid.apple.com):
#   xcrun notarytool store-credentials grains-notary --apple-id you@example.com --team-id 9JHK4XRFW5
# If no grains-notary profile exists, the existing steam-shelf-notary profile (same team) is used.
set -euo pipefail

usage() { echo "usage: release.sh X.Y.Z [--dry-run] [--skip-notarize]"; exit 1; }
VERSION="${1:-}"; [[ -n "$VERSION" ]] || usage; shift
DRY_RUN=""; SKIP_NOTARIZE=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --skip-notarize) SKIP_NOTARIZE=1 ;;
    *) usage ;;
  esac
done
# Anything that is not a full release publishes nothing.
LOCAL_ONLY=""; [[ -n "$DRY_RUN$SKIP_NOTARIZE" ]] && LOCAL_ONLY=1

REPO="begemotike/grains"
NOTARY_PROFILE="grains-notary"
NOTARY_FALLBACK_PROFILE="steam-shelf-notary"
SPARKLE_KEY_ACCOUNT="grains"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/release/$VERSION"
SPARKLE_BIN="$ROOT/build/SourcePackages/artifacts/sparkle/Sparkle/bin"
APP_NAME="Grains"
TOOL_NAME="grains-mcp"
ZIP="$APP_NAME-$VERSION.zip"

cd "$ROOT"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must be X.Y.Z"; exit 1; }
if [[ -z "$LOCAL_ONLY" ]]; then
  [[ -z "$(git status --porcelain)" ]] || { echo "commit or stash your changes first"; exit 1; }
  git tag | grep -qx "v$VERSION" && { echo "tag v$VERSION already exists"; exit 1; }
fi

# A keychain profile "exists" unless notarytool says it has no keychain item for it. `history` exits 0
# when it works; any other failure (e.g. a 403 about an unsigned agreement) still means the profile
# loaded, so only the explicit "No Keychain password item found" error counts as missing.
notary_profile_exists() {
  local out
  if out="$(xcrun notarytool history --keychain-profile "$1" 2>&1)"; then return 0; fi
  [[ "$out" != "Error: No Keychain password item found"* ]]
}
if [[ -z "$DRY_RUN$SKIP_NOTARIZE" ]]; then
  if ! notary_profile_exists "$NOTARY_PROFILE"; then
    if notary_profile_exists "$NOTARY_FALLBACK_PROFILE"; then
      echo "▶ Notary profile $NOTARY_PROFILE not found; using $NOTARY_FALLBACK_PROFILE"
      NOTARY_PROFILE="$NOTARY_FALLBACK_PROFILE"
    else
      echo "✖ No notary profile ($NOTARY_PROFILE or $NOTARY_FALLBACK_PROFILE). Run:"
      echo "  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id you@example.com --team-id 9JHK4XRFW5"
      exit 1
    fi
  fi
fi

# Build number: monotonically increasing commit count (Sparkle compares CFBundleVersion).
BUILD="$(git rev-list --count HEAD)"
echo "▶ Grains $VERSION (build $BUILD)"

xcodegen generate --quiet
xcodebuild -resolvePackageDependencies -project $APP_NAME.xcodeproj -scheme $APP_NAME -derivedDataPath build -quiet
[[ -x "$SPARKLE_BIN/generate_appcast" ]] || { echo "Sparkle tools missing at $SPARKLE_BIN"; exit 1; }

rm -rf "$OUT"; mkdir -p "$OUT"
echo "▶ Archiving (Release, Developer ID, hardened runtime)"
xcodebuild -project $APP_NAME.xcodeproj -scheme $APP_NAME -configuration Release \
  -derivedDataPath build -archivePath "$OUT/$APP_NAME.xcarchive" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
  archive -quiet
APP="$OUT/$APP_NAME.xcarchive/Products/Applications/$APP_NAME.app"
[[ -d "$APP" ]] || { echo "archive did not produce $APP"; exit 1; }
TOOL="$APP/Contents/MacOS/$TOOL_NAME"
[[ -x "$TOOL" ]] || { echo "embedded tool missing at $TOOL"; exit 1; }

echo "▶ Re-signing Sparkle's nested helpers and $TOOL_NAME with Developer ID (inside out)"
IDENTITY="Developer ID Application"
SPARKLE_FW="$APP/Contents/Frameworks/Sparkle.framework"
# identifier is preserved so the bare grains-mcp binary keeps net.outofajam.Grains.mcp rather than
# falling back to its file name.
resign() { codesign -f --timestamp -o runtime --preserve-metadata=identifier,entitlements -s "$IDENTITY" "$1"; }
resign "$SPARKLE_FW/Versions/B/XPCServices/Installer.xpc"
resign "$SPARKLE_FW/Versions/B/XPCServices/Downloader.xpc"
resign "$SPARKLE_FW/Versions/B/Autoupdate"
resign "$SPARKLE_FW/Versions/B/Updater.app"
resign "$SPARKLE_FW"
resign "$TOOL"
resign "$APP"

echo "▶ Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"
for bin in "$SPARKLE_FW/Versions/B/Updater.app" "$SPARKLE_FW/Versions/B/Autoupdate" \
           "$SPARKLE_FW/Versions/B/XPCServices/Installer.xpc" "$SPARKLE_FW/Versions/B/XPCServices/Downloader.xpc" \
           "$TOOL"; do
  codesign -dvv "$bin" 2>&1 | grep "Authority=Developer ID Application" >/dev/null || { echo "nested binary not Developer ID signed: $bin"; exit 1; }
done
codesign -dvv "$TOOL" 2>&1 | grep -E "flags=.*runtime" >/dev/null || { echo "$TOOL_NAME lacks hardened runtime"; exit 1; }
codesign -dvv "$APP" 2>&1 | grep -E "Authority=Developer ID Application" >/dev/null || { echo "not signed with Developer ID"; exit 1; }

echo "▶ Zipping"
ditto -c -k --keepParent "$APP" "$OUT/$ZIP"

if [[ -n "$SKIP_NOTARIZE" && -z "$DRY_RUN" ]]; then
  echo "▶ Signed-only build complete (not notarized, appcast untouched, nothing published): $OUT/$ZIP"
  exit 0
fi

if [[ -z "$LOCAL_ONLY" ]]; then
  echo "▶ Notarizing with profile $NOTARY_PROFILE (this takes a few minutes)"
  xcrun notarytool submit "$OUT/$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait | tee "$OUT/notarize.log"
  if ! grep -q "status: Accepted" "$OUT/notarize.log"; then
    ID=$(grep -m1 "id:" "$OUT/notarize.log" | awk '{print $2}')
    echo "✖ Notarization was not accepted. Details:"
    xcrun notarytool log "$ID" --keychain-profile "$NOTARY_PROFILE" | head -40
    exit 1
  fi
  echo "▶ Stapling"
  xcrun stapler staple "$APP"
  rm -f "$OUT/$ZIP"; ditto -c -k --keepParent "$APP" "$OUT/$ZIP"
  spctl --assess --type execute --verbose=2 "$APP"
else
  echo "▶ Dry run: skipping notarization"
fi

echo "▶ Building appcast"
# generate_appcast signs the zip with the EdDSA key from the login keychain and merges into appcast.xml.
# Grains has its own key pair, stored under the keychain account "grains" (not Steam Shelf's default).
mkdir -p "$OUT/appcast"; cp "$OUT/$ZIP" "$OUT/appcast/"
[[ -f appcast.xml ]] && cp appcast.xml "$OUT/appcast/appcast.xml"
"$SPARKLE_BIN/generate_appcast" \
  --account "$SPARKLE_KEY_ACCOUNT" \
  --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
  --link "https://github.com/$REPO/releases" \
  -o "$OUT/appcast/appcast.xml" "$OUT/appcast"
cp "$OUT/appcast/appcast.xml" appcast.xml
echo "appcast.xml updated:"; grep -E "sparkle:version|sparkle:shortVersionString|enclosure" appcast.xml | head -6

if [[ -n "$LOCAL_ONLY" ]]; then
  echo "▶ Dry run complete: $OUT/$ZIP (appcast.xml modified in working tree; discard with git checkout appcast.xml)"
  exit 0
fi

echo "▶ Publishing GitHub release v$VERSION"
git add appcast.xml
git commit -m "Release $VERSION (build $BUILD)" -q
git tag "v$VERSION"
git push origin main "v$VERSION"
# The tag already exists on GitHub now, so the release attaches to it instead of creating its own.
gh release create "v$VERSION" "$OUT/$ZIP" --repo "$REPO" --title "Grains $VERSION" --generate-notes
echo "✔ Released $VERSION. Older builds will be offered it within a day, or via Check for Updates…"
