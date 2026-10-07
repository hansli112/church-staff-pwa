#!/usr/bin/env bash
# Runs every check CI runs: Flutter analyze and tests, Cloud Functions
# typecheck and tests, and the security-rules tests on the emulators.
#
#   scripts/check.sh            # everything
#   scripts/check.sh app        # only the Flutter app
#   scripts/check.sh functions  # only Cloud Functions
#   scripts/check.sh rules      # only firestore.rules / storage.rules
#   scripts/check.sh contract   # the Backend contract on the emulators, in Chrome
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

# The contract tests (app/test/contract) on FirebaseBackend: all four
# emulators with the built functions, the app's tests in Chrome. The same
# cases run on MemoryBackend in `app`.
run_contract() {
  cd "$root/functions"
  [ -d node_modules ] || npm ci
  npm run build
  cd "$root/app"
  flutter pub get >/dev/null
  # The webhook, calendar and NewebPay functions read secrets; any will do here. A
  # .secret.local of your own is used as it is.
  local secrets="$root/functions/.secret.local"
  if [ ! -f "$secrets" ]; then
    trap "rm -f '$secrets'" EXIT
    {
      echo "CALENDAR_TOKEN_KEY=$(node -e "process.stdout.write(require('crypto').randomBytes(32).toString('base64'))")"
      echo "GOOGLE_OAUTH_CLIENT_ID=contract"
      echo "GOOGLE_OAUTH_CLIENT_SECRET=contract"
      echo "NEWEBPAY_HASH_KEY=contract"
      echo "NEWEBPAY_HASH_IV=contract"
    } >"$secrets"
  fi
  cd "$root"
  npx --prefix functions firebase emulators:exec --only auth,firestore,functions,storage --project demo-martha \
    "cd app && flutter test --no-pub --platform chrome --concurrency=1 test/contract/firebase_contract_test.dart"
}

case "$what" in
  app) run_app ;;
  functions) run_functions ;;
  rules) run_rules ;;
  contract) run_contract ;;
  all) run_app; run_functions; run_rules; run_contract ;;
  *) echo "unknown target: $what" >&2; exit 2 ;;
esac
