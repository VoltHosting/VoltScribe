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

if grep -R --include='*.swift' -n 'SyntheticEventPostingGate\.shared\.post(' "$APP_SOURCE" >/dev/null; then
  echo "Synthetic events must use an atomic withAuthorizedSequence transaction" >&2
  grep -R --include='*.swift' -n 'SyntheticEventPostingGate\.shared\.post(' "$APP_SOURCE" >&2 || true
  exit 1
fi

if grep -R --include='*.swift' -nE 'CGEventPost|postToPid|CGDisplayMoveCursorToPoint|IOHID[A-Za-z]*Post' \
  "$APP_SOURCE" >/dev/null; then
  echo "Unapproved synthetic input API bypasses InputSafetyPolicy.swift" >&2
  exit 1
fi

if grep -Fq 'orderFrontRegardless' "$ONBOARDING_CONTROLLER"; then
  echo "Onboarding must not force a non-active accessory window to the front" >&2
  exit 1
fi

grep -Fq 'setActivationPolicy(.regular)' "$ONBOARDING_CONTROLLER"
grep -Fq 'setMainRuntimeEnabled(canRunMainApp, synchronizeMeetingMonitors: false)' \
  "$APP_SOURCE/MuesliController.swift"
grep -Fq 'SyntheticEventPostingGate.shared.setRuntimeEnabled(enabled)' \
  "$APP_SOURCE/MuesliController.swift"
grep -Fq 'let lease = SyntheticEventPostingLease' \
  "$INPUT_SAFETY_POLICY"
grep -Fq 'lease.invalidate()' \
  "$INPUT_SAFETY_POLICY"
grep -Fq 'admissionThreadKey' \
  "$INPUT_SAFETY_POLICY"
grep -Fq 'meetingFeatureMonitorsAllowed = enabled' \
  "$APP_SOURCE/MuesliController.swift"
grep -Fq 'syncCalendarMonitor()' \
  "$APP_SOURCE/MuesliController.swift"
grep -Fq 'syncMeetingDetectionMonitor()' \
  "$APP_SOURCE/MuesliController.swift"
grep -Fq 'setMainRuntimeEnabled(canRunMainApp, synchronizeMeetingMonitors: false)' \
  "$APP_SOURCE/MuesliController.swift"
grep -Fq 'if synchronizeMeetingMonitors {' \
  "$APP_SOURCE/MuesliController.swift"
grep -Fq 'stopInputRuntimeActivity()' \
  "$APP_SOURCE/MuesliController.swift"
grep -Fq 'hotkeyMonitor.stop()' \
  "$APP_SOURCE/MuesliController.swift"
grep -Fq 'computerUseHotkeyMonitor.stop()' \
  "$APP_SOURCE/MuesliController.swift"
grep -Fq 'meetingRecordingHotkeyMonitor.stop()' \
  "$APP_SOURCE/MuesliController.swift"
grep -Fq 'computerUseCommandTask?.cancel()' \
  "$APP_SOURCE/MuesliController.swift"
if [ "$(grep -Fc 'guard meetingFeatureMonitorsAllowed else' "$APP_SOURCE/MuesliController.swift")" -lt 3 ]; then
  echo "Secondary production hotkey helpers must fail closed while runtime monitors are disabled" >&2
  exit 1
fi
grep -Fq 'StatusBarRuntimePolicy.shouldExposeRuntimeActions' \
  "$APP_SOURCE/StatusBarController.swift"
grep -Fq 'runtimeEnabled: SyntheticEventPostingGate.shared.isRuntimeEnabled()' \
  "$APP_SOURCE/StatusBarController.swift"
grep -Fq 'title: "Quit \(AppIdentity.displayName)"' \
  "$APP_SOURCE/StatusBarController.swift"
grep -Fq 'static func shouldShow' \
  "$INPUT_SAFETY_POLICY"
grep -Fq 'FloatingIndicatorRuntimePolicy.action' \
  "$APP_SOURCE/MuesliController.swift"
grep -Fq 'indicator.closeIfIdle()' \
  "$APP_SOURCE/MuesliController.swift"
grep -Fq 'indicator.closeForRuntimeShutdown()' \
  "$APP_SOURCE/MuesliController.swift"
grep -Fq 'FloatingIndicatorPresentationPolicy.canPresent' \
  "$APP_SOURCE/MuesliController.swift"
grep -Fq 'guard presentationAllowed() else { return }' \
  "$APP_SOURCE/FloatingIndicatorController.swift"
grep -Fq 'setMainRuntimeEnabled(false)' \
  "$APP_SOURCE/MuesliController.swift"
grep -Fq 'indicator.close()' \
  "$APP_SOURCE/MuesliController.swift"
grep -Fq 'startOnboardingHotkeyMonitor' \
  "$APP_SOURCE/OnboardingView.swift"
grep -Fq 'hotkeyMonitor.start(policy: policy)' \
  "$APP_SOURCE/MuesliController.swift"
grep -Fq 'ComputerUseRuntimePolicy.canExecute' \
  "$APP_SOURCE/ComputerUseExecutor.swift"
grep -Fq 'try processBox.launch(process)' \
  "$APP_SOURCE/ComputerUseBrowserAutomation.swift"
grep -Fq 'ProcessOutputCaptureBox' \
  "$APP_SOURCE/ComputerUseBrowserAutomation.swift"
grep -Fq 'readers.wait()' \
  "$APP_SOURCE/ComputerUseBrowserAutomation.swift"
grep -Fq 'completeIfNotCancelled' \
  "$APP_SOURCE/ComputerUseBrowserAutomation.swift"
if grep -Fq 'processBox.set(process)' "$APP_SOURCE/ComputerUseBrowserAutomation.swift"; then
  echo "AppleScript process registration and launch must remain atomic" >&2
  exit 1
fi
if [ "$(grep -Fc 'guard runtimeAllowsExecution() else' "$APP_SOURCE/ComputerUseExecutor.swift")" -lt 10 ]; then
  echo "Async computer-use mutations must revalidate runtime after suspension" >&2
  exit 1
fi
grep -Fq 'browserProcessPreLaunchCancellationIsDeterministic' \
  "$ROOT/native/MuesliNative/Tests/MuesliTests/ComputerUseExecutorTests.swift"
grep -Fq 'browserProcessCancellationTerminatesChild' \
  "$ROOT/native/MuesliNative/Tests/MuesliTests/ComputerUseExecutorTests.swift"
grep -Fq 'browserProcessLateCancellationSuppressesCompletion' \
  "$ROOT/native/MuesliNative/Tests/MuesliTests/ComputerUseExecutorTests.swift"
grep -Fq 'browserProcessCompletionLinearizesBeforeCancellation' \
  "$ROOT/native/MuesliNative/Tests/MuesliTests/ComputerUseExecutorTests.swift"
grep -Fq 'browserProcessDrainsLargeOutput' \
  "$ROOT/native/MuesliNative/Tests/MuesliTests/ComputerUseExecutorTests.swift"

printf 'VoltScribe development branding and input-safety configuration passed.\n'
