#!/usr/bin/env bash
set -euo pipefail

# Archives both App Store targets and exports them for App Store Connect
# upload. Requires an "Apple Distribution" (iOS) / "Mac Installer
# Distribution" + "Apple Distribution" (macOS) certificate already installed
# in the local keychain, and the corresponding App Store provisioning
# profiles available to Automatic Signing (Xcode creates these on demand
# when signed into the Apple Developer account in Xcode > Settings > Accounts).
#
# Usage: script/archive_and_export.sh [mac|ios|all]

#
# Signing talks to App Store Connect either through the Apple ID signed into
# Xcode > Settings > Accounts, or — when that session has expired, which shows up
# as "Unable to log in with account" / "No signing certificate found" — through an
# App Store Connect API key. To use the key, export before running:
#
#   ASC_KEY_ID=...  ASC_ISSUER_ID=...  [ASC_KEY_PATH=/path/to/AuthKey_<ID>.p8]
#
# These are credentials: pass them via the environment, never commit them here.

TARGET="${1:-all}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE_DIR="$ROOT_DIR/build/archives"
EXPORT_DIR="$ROOT_DIR/build/export"

AUTH_ARGS=()
if [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ]; then
  AUTH_ARGS=(
    -authenticationKeyPath "${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
    -authenticationKeyID "$ASC_KEY_ID"
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"
  )
fi
# Expands to nothing (rather than erroring under `set -u`) when the key isn't set.
ASC_AUTH=("${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"}")

cd "$ROOT_DIR"
if [ ! -d "MacCCTV.xcodeproj" ]; then
  xcodegen generate
fi

archive_mac() {
  xcodebuild \
    -project MacCCTV.xcodeproj \
    -scheme MacCCTV \
    -configuration Release \
    -archivePath "$ARCHIVE_DIR/MacCCTV.xcarchive" \
    -allowProvisioningUpdates \
    "${ASC_AUTH[@]+"${ASC_AUTH[@]}"}" \
    archive
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_DIR/MacCCTV.xcarchive" \
    -exportPath "$EXPORT_DIR/mac" \
    -exportOptionsPlist "$ROOT_DIR/script/ExportOptions-mac.plist" \
    -allowProvisioningUpdates \
    "${ASC_AUTH[@]+"${ASC_AUTH[@]}"}"
}

archive_ios() {
  xcodebuild \
    -project MacCCTV.xcodeproj \
    -scheme CCTVCompanion \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_DIR/CCTVCompanion.xcarchive" \
    -allowProvisioningUpdates \
    "${ASC_AUTH[@]+"${ASC_AUTH[@]}"}" \
    archive
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_DIR/CCTVCompanion.xcarchive" \
    -exportPath "$EXPORT_DIR/ios" \
    -exportOptionsPlist "$ROOT_DIR/script/ExportOptions-ios.plist" \
    -allowProvisioningUpdates \
    "${ASC_AUTH[@]+"${ASC_AUTH[@]}"}"
}

case "$TARGET" in
  mac) archive_mac ;;
  ios) archive_ios ;;
  all) archive_mac && archive_ios ;;
  *)
    echo "usage: $0 [mac|ios|all]" >&2
    exit 2
    ;;
esac

echo "Exported .pkg/.ipa to $EXPORT_DIR — upload via Transporter.app or:"
echo "  xcrun altool --upload-app -f <file> -t macos|ios --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>"
echo "(or set script/ExportOptions-*.plist destination to 'upload' to have xcodebuild upload directly)"
