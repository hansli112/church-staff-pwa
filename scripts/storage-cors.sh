#!/usr/bin/env bash
# Lets the web app read Storage files (church logos, 備註 pictures). Flutter
# web fetches an Image.network's bytes, and without CORS on the bucket the
# browser refuses them (statusCode: 0), so no logo ever showed on the web.
# Only GET, only from the web app's own origins.
#
#   scripts/storage-cors.sh dev
set -euo pipefail

env_name="${1:?dev or prod}"
root="$(cd "$(dirname "$0")/.." && pwd)"
config="$root/app/config/$env_name.json"
read -r project bucket origin < <(node -p "const c = require('$config'); [c.FIREBASE_PROJECT_ID, c.FIREBASE_STORAGE_BUCKET, c.WEB_ORIGIN].join(' ')")
cors="[{\"origin\":[\"$origin\",\"https://$project.web.app\",\"https://$project.firebaseapp.com\"],\"method\":[\"GET\"],\"maxAgeSeconds\":3600}]"
token="$(CLOUDSDK_ACTIVE_CONFIG_NAME="${MARTHA_GCLOUD_CONFIG:-martha}" gcloud auth print-access-token)"
curl -sSf -X PATCH -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
  "https://storage.googleapis.com/storage/v1/b/$bucket?fields=cors" -d "{\"cors\":$cors}"
echo
