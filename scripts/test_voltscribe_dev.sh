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

APP_SOURCE="$ROOT/native/MuesliNative/Sources/MuesliNativeApp"
ONBOARDING_CONTROLLER="$APP_SOURCE/OnboardingWindowController.swift"
INPUT_SAFETY_POLICY="$APP_SOURCE/InputSafetyPolicy.swift"

if grep -R --include='*.swift' -n '\.post(tap:' "$APP_SOURCE" \
  | grep -Fv "$INPUT_SAFETY_POLICY:" >/dev/null; then
  echo "Synthetic event posting bypasses InputSafetyPolicy.swift" >&2
  grep -R --include='*.swift' -n '\.post(tap:' "$APP_SOURCE" \
    | grep -Fv "$INPUT_SAFETY_POLICY:" >&2 || true
  exit 1
fi

if grep -Fq 'orderFrontRegardless' "$ONBOARDING_CONTROLLER"; then
  echo "Onboarding must not force a non-active accessory window to the front" >&2
  exit 1
fi

grep -Fq 'setActivationPolicy(.regular)' "$ONBOARDING_CONTROLLER"
grep -Fq 'SyntheticEventPostingGate.shared.setRuntimeEnabled(canRunMainApp)' \
  "$APP_SOURCE/MuesliController.swift"
grep -Fq 'StatusBarRuntimePolicy.shouldExposeRuntimeActions' \
  "$APP_SOURCE/StatusBarController.swift"
grep -Fq 'title: "Quit \(AppIdentity.displayName)"' \
  "$APP_SOURCE/StatusBarController.swift"

printf 'VoltScribe development branding and input-safety configuration passed.\n'
