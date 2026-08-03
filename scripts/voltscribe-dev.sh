#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="VoltScribeDev"
DISPLAY_NAME="VoltScribe Dev"
APP_BUNDLE_NAME="VoltScribeDev.app"
EXECUTABLE_NAME="VoltScribeDev"
BUNDLE_ID="uk.co.volthosting.voltscribe.dev"
SUPPORT_DIRECTORY_NAME="VoltScribeDev"
INSTALL_DIRECTORY="${VOLTSCRIBE_INSTALL_DIR:-$HOME/Applications}"
ENTITLEMENTS="$ROOT/scripts/MuesliLocalOnly.entitlements"
SCRATCH_PATH="${VOLTSCRIBE_SWIFTPM_SCRATCH_PATH:-$HOME/Library/Caches/muesli-spm/voltscribe-dev/app}"

print_config() {
  printf '%s\n' \
    "app_name=$APP_NAME" \
    "display_name=$DISPLAY_NAME" \
    "app_bundle_name=$APP_BUNDLE_NAME" \
    "executable_name=$EXECUTABLE_NAME" \
    "bundle_id=$BUNDLE_ID" \
    "support_directory_name=$SUPPORT_DIRECTORY_NAME" \
    "install_directory=$INSTALL_DIRECTORY" \
    "telemetry_app_id=" \
    "telemetry_channel=unconfigured" \
    "sparkle_feed_url=" \
    "entitlements=$ENTITLEMENTS" \
    "skip_sign=1" \
    "scratch_path=$SCRATCH_PATH"
}

usage() {
  cat <<'EOF'
Build the isolated, local-only VoltScribe development app.

Usage:
  ./scripts/voltscribe-dev.sh
  ./scripts/voltscribe-dev.sh --build
  ./scripts/voltscribe-dev.sh --print-config

The app is installed without launching to allow bundle and entitlement
verification before macOS privacy permissions are granted.
EOF
}

case "${1:---build}" in
  --print-config)
    print_config
    exit 0
    ;;
  --build)
    ;;
  --help|-h)
    usage
    exit 0
    ;;
  *)
    echo "Unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
esac

mkdir -p "$INSTALL_DIRECTORY" "$SCRATCH_PATH"

print_config

env \
  -u MUESLI_SIGN_IDENTITY \
  -u MUESLI_DISABLE_SWIFTPM_SCRATCH_PATH \
  -u MUESLI_SWIFTPM_SCRATCH_CHANNEL \
  MUESLI_INSTALL_DIR="$INSTALL_DIRECTORY" \
  MUESLI_APP_NAME="$APP_NAME" \
  MUESLI_DISPLAY_NAME="$DISPLAY_NAME" \
  MUESLI_APP_BUNDLE_NAME="$APP_BUNDLE_NAME" \
  MUESLI_EXECUTABLE_NAME="$EXECUTABLE_NAME" \
  MUESLI_BUNDLE_ID="$BUNDLE_ID" \
  MUESLI_SUPPORT_DIR_NAME="$SUPPORT_DIRECTORY_NAME" \
  MUESLI_SKIP_SIGN=1 \
  MUESLI_ENTITLEMENTS="$ENTITLEMENTS" \
  MUESLI_PROVISIONING_PROFILE="" \
  MUESLI_APS_ENVIRONMENT="" \
  MUESLI_ICLOUD_CONTAINER_ENVIRONMENT="" \
  MUESLI_TELEMETRYDECK_APP_ID="" \
  MUESLI_TELEMETRY_CHANNEL="unconfigured" \
  MUESLI_SPARKLE_FEED_URL="" \
  MUESLI_SWIFTPM_SCRATCH_PATH="$SCRATCH_PATH" \
  "$ROOT/scripts/build_native_app.sh" debug

printf '\nBuilt %s/%s\n' "$INSTALL_DIRECTORY" "$APP_BUNDLE_NAME"
printf 'The app was not launched. Verify its signature, identity, and entitlements before opening it.\n'
