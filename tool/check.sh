#!/usr/bin/env bash
set -euo pipefail
trimmy_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$trimmy_root"
if [[ "$(npm --version)" != '10.9.8' ]]; then
  echo 'Use npm 10.9.8 for the reviewed dependency overrides: npx --yes npm@10.9.8 exec -- bash tool/check.sh' >&2
  exit 1
fi
npm ci
npm run check
bash infra/tests/run-postgres.sh
(
  cd apps/mobile
  flutter pub get --enforce-lockfile
)
npm run test:mobile-sync
cd apps/mobile
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
flutter build web --release -t lib/design_study.dart
