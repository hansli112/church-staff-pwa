#!/usr/bin/env bash
# The Firebase CLI as the project owner (see as-owner.sh).
#
#   scripts/firebase.sh marthasit-dev deploy --only hosting
set -euo pipefail
project="${1:?project id}"
shift
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
exec "$root/scripts/as-owner.sh" "$project" npx --prefix functions firebase --project "$project" "$@"
