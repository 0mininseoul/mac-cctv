#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
if [ "$#" -gt 0 ]; then
  shift
fi
APP_NAME="MacCCTV"
BUNDLE_ID="com.youngminpark.maccctv.ios"
SCHEME="MacCCTV"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/MacCCTV.xcodeproj"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"

if [ ! -d "$PROJECT_PATH" ]; then
  (cd "$ROOT_DIR" && xcodegen generate)
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  -destination "platform=macOS" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  build

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

run_m1_capture() {
  "$APP_BUNDLE/Contents/MacOS/$APP_NAME" --m1-capture "$@"
}

run_m2_capture_upload() {
  "$APP_BUNDLE/Contents/MacOS/$APP_NAME" --m2-capture-upload "$@"
}

run_m2_upload_pending() {
  "$APP_BUNDLE/Contents/MacOS/$APP_NAME" --m2-upload-pending "$@"
}

run_m2_sweep() {
  "$APP_BUNDLE/Contents/MacOS/$APP_NAME" --m2-sweep "$@"
}

run_m2_verify_upload() {
  "$APP_BUNDLE/Contents/MacOS/$APP_NAME" --m2-verify-upload "$@"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --m1-capture|m1-capture)
    run_m1_capture "$@"
    ;;
  --m2-capture-upload|m2-capture-upload)
    run_m2_capture_upload "$@"
    ;;
  --m2-upload-pending|m2-upload-pending)
    run_m2_upload_pending "$@"
    ;;
  --m2-sweep|m2-sweep)
    run_m2_sweep "$@"
    ;;
  --m2-verify-upload|m2-verify-upload)
    run_m2_verify_upload "$@"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--m1-capture|--m2-capture-upload|--m2-upload-pending|--m2-sweep|--m2-verify-upload]" >&2
    exit 2
    ;;
esac
