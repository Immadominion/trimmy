#!/usr/bin/env bash
# Build and replace the separate native study without uninstalling or clearing data.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: install-seeker-study.sh [DEVICE_SERIAL] [release|debug]

Builds lib/design_study.dart for Android ARM64, installs for user 0 with
--no-streaming -r, and opens Trimmy. It never uninstalls or clears app data.
The current project's release mode uses a local debug signing key, not a
production signing configuration.

Environment overrides:
  TRIMMY_ANDROID_SERIAL   Required when DEVICE_SERIAL is omitted
  TRIMMY_BUILD_MODE       release (default) or debug
  TRIMMY_FLUTTER_BIN      Absolute path to the Flutter executable
  TRIMMY_ADB_BIN          Absolute path to the adb executable

Example from trimmy/:
  bash tool/install-seeker-study.sh YOUR_SEEKER_SERIAL release
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi
if (( $# > 2 )); then
  usage >&2
  exit 2
fi

trimmy_serial="${1:-${TRIMMY_ANDROID_SERIAL:-}}"
trimmy_build_mode="${2:-${TRIMMY_BUILD_MODE:-release}}"
if [[ -z "$trimmy_serial" || "$trimmy_serial" == -* ]]; then
  printf '%s\n' 'Provide the intended Seeker serial explicitly; no device is selected automatically.' >&2
  exit 2
fi
case "$trimmy_build_mode" in
  debug|release) ;;
  *) printf '%s\n' 'Build mode must be release or debug.' >&2; exit 2 ;;
esac

trimmy_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
trimmy_mobile="$trimmy_root/apps/mobile"
trimmy_flutter="${TRIMMY_FLUTTER_BIN:-}"
trimmy_adb="${TRIMMY_ADB_BIN:-}"
if [[ -z "$trimmy_flutter" ]]; then
  trimmy_flutter="$(command -v flutter || true)"
  trimmy_flutter="${trimmy_flutter:-$HOME/Development/flutter/bin/flutter}"
fi
if [[ -z "$trimmy_adb" ]]; then
  trimmy_adb="$(command -v adb || true)"
  trimmy_adb="${trimmy_adb:-$HOME/Library/Android/sdk/platform-tools/adb}"
fi
if [[ ! -x "$trimmy_flutter" || ! -x "$trimmy_adb" ]]; then
  printf '%s\n' 'Flutter or adb is unavailable. Set TRIMMY_FLUTTER_BIN and TRIMMY_ADB_BIN to executable paths.' >&2
  exit 2
fi

trimmy_device_state="$("$trimmy_adb" -s "$trimmy_serial" get-state)"
if [[ "$trimmy_device_state" != "device" ]]; then
  printf '%s\n' 'The selected device is not ready. Unlock it and authorize USB debugging, then retry.' >&2
  exit 1
fi

printf 'Building the separate %s study for device %s.\n' "$trimmy_build_mode" "$trimmy_serial"
cd -- "$trimmy_mobile"
"$trimmy_flutter" pub get --enforce-lockfile
"$trimmy_flutter" build apk "--$trimmy_build_mode" --no-pub \
  --target lib/design_study.dart --target-platform android-arm64

trimmy_apk="$trimmy_mobile/build/app/outputs/flutter-apk/app-$trimmy_build_mode.apk"
if [[ ! -s "$trimmy_apk" ]]; then
  printf 'Expected APK was not produced: %s\n' "$trimmy_apk" >&2
  exit 1
fi

# A failed replacement (including signature mismatch) stops here. Never fall
# back to uninstall, downgrade, data clearing, or installation on another device.
"$trimmy_adb" -s "$trimmy_serial" install --no-streaming --user 0 -r "$trimmy_apk"
"$trimmy_adb" -s "$trimmy_serial" shell am start --user 0 -W \
  -n com.trimmy.trimmy/.MainActivity
printf '%s\n' 'Trimmy opened. Installation success is not a completed interaction or performance review.'
