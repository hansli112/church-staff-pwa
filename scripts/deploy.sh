#!/usr/bin/env bash
# Builds the web app for one environment and deploys it with Cloud Functions.
# The project comes from app/config/<env>.json, so a dev build never lands on
# prod.
#
#   scripts/deploy.sh dev
#   scripts/deploy.sh prod [--only hosting]
set -euo pipefail

env_name="${1:?dev or prod}"
shift
only="functions,hosting"
if [ "${1:-}" = "--only" ]; then only="${2:?what to deploy}"; fi

root="$(cd "$(dirname "$0")/.." && pwd)"
config="$root/app/config/$env_name.json"
[ -f "$config" ] || { echo "No $config: run scripts/firebase-project.sh first" >&2; exit 1; }
project="$(node -p "require('$config').FIREBASE_PROJECT_ID")"
echo "Deploying $only to $project ($env_name)"

if [[ ",$only," == *",hosting,"* ]]; then
  ( cd "$root/app" && flutter build web --dart-define-from-file="config/$env_name.json" )
fi

firebase() { "$root/scripts/firebase.sh" "$project" "$@"; }
deploy() { firebase deploy --only "$only" --non-interactive; }

# Delete old Functions images, or they add a small monthly bill. Without this
# policy the deploy reports an error even when every function deployed. The
# image repository exists only after the first Functions deploy, so before
# that this does nothing.
policy() {
  [[ ",$only," == *",functions,"* ]] || return 0
  firebase functions:artifacts:setpolicy --location asia-east1 --non-interactive --force || true
}

policy
# On a new project the first Functions deploy can fail while Eventarc
# permissions propagate ("Retry the deployment in a few minutes").
if ! deploy; then
  echo "Deploy failed; retrying once in 3 minutes (new projects need this)" >&2
  policy
  sleep 180
  deploy
fi
