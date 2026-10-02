#!/usr/bin/env bash
# Runs every check CI runs: Flutter analyze and tests, Cloud Functions
# typecheck and tests, and the security-rules tests on the emulators.
#
#   scripts/check.sh            # everything
#   scripts/check.sh app        # only the Flutter app
#   scripts/check.sh functions  # only Cloud Functions
#   scripts/check.sh rules      # only firestore.rules / storage.rules
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
what="${1:-all}"

run_app() {
  cd "$root/app"
  flutter pub get >/dev/null
  flutter gen-l10n
  dart format --output=none --set-exit-if-changed lib test
  flutter analyze
  flutter test --no-pub
}

run_functions() {
  cd "$root/functions"
  [ -d node_modules ] || npm ci
  npm run typecheck
  npm test
}

run_rules() {
  cd "$root/firestore-tests"
  [ -d node_modules ] || npm ci
  npm test
}

case "$what" in
  app) run_app ;;
  functions) run_functions ;;
  rules) run_rules ;;
  all) run_app; run_functions; run_rules ;;
  *) echo "unknown target: $what" >&2; exit 2 ;;
esac
