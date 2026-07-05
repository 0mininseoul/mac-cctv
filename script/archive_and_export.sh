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

TARGET="${1:-all}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE_DIR="$ROOT_DIR/build/archives"
EXPORT_DIR="$ROOT_DIR/build/export"

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
    archive
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_DIR/MacCCTV.xcarchive" \
    -exportPath "$EXPORT_DIR/mac" \
    -exportOptionsPlist "$ROOT_DIR/script/ExportOptions-mac.plist" \
    -allowProvisioningUpdates
}

archive_ios() {
  xcodebuild \
    -project MacCCTV.xcodeproj \
    -scheme CCTVCompanion \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_DIR/CCTVCompanion.xcarchive" \
    -allowProvisioningUpdates \
    archive
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_DIR/CCTVCompanion.xcarchive" \
    -exportPath "$EXPORT_DIR/ios" \
    -exportOptionsPlist "$ROOT_DIR/script/ExportOptions-ios.plist" \
    -allowProvisioningUpdates
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
