#!/usr/bin/env bash
# Runs a command with the gcloud configuration's account as Application
# Default Credentials for one project, e.g. the Firebase CLI or an admin
# script. Nothing from `firebase login` or other ADC on this machine is used.
#
#   scripts/as-owner.sh marthasit-dev npx tsx functions/scripts/grant-operator.ts --project marthasit-dev you@gmail.com
#
# MARTHA_GCLOUD_CONFIG picks the configuration (default "martha").
set -euo pipefail

project="${1:?project id}"
shift
export CLOUDSDK_ACTIVE_CONFIG_NAME="${MARTHA_GCLOUD_CONFIG:-martha}"
account="$(gcloud config get-value account 2>/dev/null)"
creds="${CLOUDSDK_CONFIG:-$HOME/.config/gcloud}/legacy_credentials/$account/adc.json"
[ -f "$creds" ] || { echo "No gcloud credentials for '$account': run gcloud auth login" >&2; exit 1; }

# An empty config dir hides any `firebase login`, so the Firebase CLI falls
# back to these credentials. Google APIs refuse user credentials without a
# quota project; the CLI leaves it off where it does not belong (source uploads).
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
XDG_CONFIG_HOME="$tmp" GOOGLE_APPLICATION_CREDENTIALS="$creds" GOOGLE_CLOUD_QUOTA_PROJECT="$project" "$@"
