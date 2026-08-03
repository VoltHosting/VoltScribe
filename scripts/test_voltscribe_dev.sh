#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/voltscribe-dev.sh"

output="$($SCRIPT --print-config)"

expect_line() {
  local expected="$1"
  if ! grep -Fqx "$expected" <<<"$output"; then
    echo "Missing expected configuration: $expected" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

expect_line "app_name=VoltScribe"
expect_line "display_name=VoltScribe"
expect_line "app_bundle_name=VoltScribe.app"
expect_line "executable_name=VoltScribe"
expect_line "bundle_id=uk.co.volthosting.voltscribe.dev"
expect_line "support_directory_name=VoltScribeDev"
expect_line "install_directory=$HOME/Applications"
expect_line "telemetry_app_id="
expect_line "telemetry_channel=unconfigured"
expect_line "sparkle_feed_url="
expect_line "sparkle_automatic_checks=false"
expect_line "remote_notifications_enabled=false"
expect_line "entitlements=$ROOT/scripts/MuesliLocalOnly.entitlements"
expect_line "skip_sign=1"
expect_line "scratch_path=$HOME/Library/Caches/muesli-spm/voltscribe-dev/app"

printf 'VoltScribe development branding configuration passed.\n'
