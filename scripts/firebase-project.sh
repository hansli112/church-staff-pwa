#!/usr/bin/env bash
# Creates (or finishes setting up) a 馬大別忙 Firebase project under Hans's
# personal Google account. Safe to re-run: every step checks first.
#
#   scripts/firebase-project.sh dev  marthasit-dev  [BILLING_ACCOUNT_ID] [--dry-run]
#   scripts/firebase-project.sh prod marthasit      [BILLING_ACCOUNT_ID] [--dry-run]
#
# Needs: gcloud signed in as the personal account in a configuration named
# "martha" (gcloud config configurations create martha), and `npx firebase
# login` as the same account for the deploy step. MARTHA_GCLOUD_CONFIG picks
# another configuration, e.g. a second account that creates the project and
# then invites the personal account as owner. Steps Google offers no API
# for are printed at the end (docs/firebase-setup.md has the details).
set -euo pipefail

env_name="${1:?dev or prod}"
project="${2:?project id}"
billing="${3:-}"
dry=false
for a in "$@"; do [ "$a" = "--dry-run" ] && dry=true; done
[ "$billing" = "--dry-run" ] && billing=""

export CLOUDSDK_ACTIVE_CONFIG_NAME="${MARTHA_GCLOUD_CONFIG:-martha}"
root="$(cd "$(dirname "$0")/.." && pwd)"
region=asia-east1
bundle=app.marthasit

run() {
  echo "+ $*"
  if ! $dry; then "$@"; fi
}

api() { # method url [json]
  local method=$1 url=$2 body=${3:-}
  echo "+ $method $url" >&2
  $dry && { echo '{}'; return; }
  curl -sS -X "$method" "$url" \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    -H "x-goog-user-project: $project" \
    -H 'Content-Type: application/json' ${body:+-d "$body"}
}

account="$(gcloud config get-value account 2>/dev/null)"
case "$account" in
  *@dwave.cc|"") echo "gcloud account is '$account': switch the martha configuration to the personal account" >&2; exit 1 ;;
esac
echo "Account: $account  Project: $project ($env_name)"

# 1. Project, outside any organization.
if gcloud projects describe "$project" >/dev/null 2>&1; then
  parent="$(gcloud projects describe "$project" --format='value(parent.type)')"
  [ -n "$parent" ] && { echo "Project has a parent ($parent); expected none" >&2; exit 1; }
else
  run gcloud projects create "$project" --name="Martha $env_name"
fi

# 2. Billing (Blaze): needed for Cloud Functions and Storage.
if [ -n "$billing" ]; then
  run gcloud billing projects link "$project" --billing-account="$billing"
fi

# 3. APIs. The second group needs billing.
run gcloud services enable --project "$project" \
  firebase.googleapis.com firestore.googleapis.com identitytoolkit.googleapis.com \
  firebasestorage.googleapis.com storage.googleapis.com \
  fcm.googleapis.com firebaseinstallations.googleapis.com monitoring.googleapis.com \
  logging.googleapis.com clouderrorreporting.googleapis.com calendar-json.googleapis.com \
  generativelanguage.googleapis.com firebasehosting.googleapis.com
if [ -n "$billing" ]; then
  run gcloud services enable --project "$project" \
    cloudfunctions.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com \
    run.googleapis.com eventarc.googleapis.com pubsub.googleapis.com cloudscheduler.googleapis.com \
    secretmanager.googleapis.com
fi

# 4. Add Firebase.
if ! api GET "https://firebase.googleapis.com/v1beta1/projects/$project" | grep -q '"projectId"'; then
  api POST "https://firebase.googleapis.com/v1beta1/projects/$project:addFirebase" '{}'
  $dry || sleep 20
fi

# 5. Firestore in asia-east1.
if ! gcloud firestore databases describe --project "$project" --database='(default)' >/dev/null 2>&1; then
  run gcloud firestore databases create --project "$project" --location="$region" --type=firestore-native
fi

# 6. Auth: email + password on, one account per email.
api PATCH "https://identitytoolkit.googleapis.com/admin/v2/projects/$project/config?updateMask=signIn.email,signIn.allowDuplicateEmails,authorizedDomains" \
  "{\"signIn\":{\"email\":{\"enabled\":true,\"passwordRequired\":true},\"allowDuplicateEmails\":false},\"authorizedDomains\":[\"localhost\",\"$project.firebaseapp.com\",\"$project.web.app\"]}" >/dev/null

# 7. Apps (web, Android, iOS) and the app's build config.
# One at a time: creating them together can silently drop one.
for kind in web android ios; do
  case $kind in
    web) body='{"displayName":"馬大別忙 Web"}' ;;
    android) body="{\"displayName\":\"馬大別忙 Android\",\"packageName\":\"$bundle\"}" ;;
    ios) body="{\"displayName\":\"馬大別忙 iOS\",\"bundleId\":\"$bundle\"}" ;;
  esac
  if ! api GET "https://firebase.googleapis.com/v1beta1/projects/$project/${kind}Apps" | grep -q '"appId"'; then
    api POST "https://firebase.googleapis.com/v1beta1/projects/$project/${kind}Apps" "$body" >/dev/null
    $dry || sleep 15
  fi
done
if ! $dry; then
  web_id="$(api GET "https://firebase.googleapis.com/v1beta1/projects/$project/webApps" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).apps[0].appId))')"
  android_id="$(api GET "https://firebase.googleapis.com/v1beta1/projects/$project/androidApps" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log((JSON.parse(s).apps??[])[0]?.appId??""))')"
  ios_id="$(api GET "https://firebase.googleapis.com/v1beta1/projects/$project/iosApps" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log((JSON.parse(s).apps??[])[0]?.appId??""))')"
  api GET "https://firebase.googleapis.com/v1beta1/projects/$project/webApps/$web_id/config" \
    | ENV="$env_name" ANDROID="$android_id" IOS="$ios_id" node -e '
      let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
        const c = JSON.parse(s);
        const out = {
          MARTHA_ENV: process.env.ENV,
          FIREBASE_PROJECT_ID: c.projectId,
          FIREBASE_API_KEY: c.apiKey,
          FIREBASE_WEB_APP_ID: c.appId,
          FIREBASE_ANDROID_APP_ID: process.env.ANDROID,
          FIREBASE_IOS_APP_ID: process.env.IOS,
          FIREBASE_SENDER_ID: c.messagingSenderId,
          FIREBASE_STORAGE_BUCKET: c.storageBucket ?? `${c.projectId}.firebasestorage.app`,
          FIREBASE_AUTH_DOMAIN: c.authDomain,
          FIREBASE_MEASUREMENT_ID: c.measurementId ?? "",
          GOOGLE_SERVER_CLIENT_ID: "",
          FCM_VAPID_KEY: "",
          WEB_ORIGIN: `https://${c.projectId}.web.app`,
        };
        require("fs").writeFileSync(`'"$root"'/app/config/${process.env.ENV}.json`, JSON.stringify(out, null, 2) + "\n");
        console.log(`wrote app/config/${process.env.ENV}.json`);
      });'
fi

# 8. Default Storage bucket (Blaze only).
if [ -n "$billing" ]; then
  api POST "https://firebasestorage.googleapis.com/v1beta/projects/$project/defaultBucket" "{\"location\":\"$region\"}" >/dev/null || true
fi

# 9. Rules and indexes (Functions need Blaze and the secrets below).
( cd "$root" && run npx --prefix functions firebase deploy --project "$project" \
    --only firestore:rules,firestore:indexes${billing:+,storage} )

# 10. Budget alert to the account owner.
if [ -n "$billing" ]; then
  if ! gcloud billing budgets list --billing-account="$billing" --format='value(displayName)' 2>/dev/null | grep -qx "martha-$env_name"; then
    run gcloud billing budgets create --billing-account="$billing" --display-name="martha-$env_name" \
      --budget-amount=300TWD --threshold-rule=percent=0.5 --threshold-rule=percent=0.9 --threshold-rule=percent=1.0 \
      --filter-projects="projects/$project"
  fi
fi

cat <<EOF

Done with the automatic part. By hand, once (docs/firebase-setup.md):
  1. Firebase console › Authentication › Sign-in method › Google: enable.
     Copy the Web client ID into app/config/$env_name.json as GOOGLE_SERVER_CLIENT_ID.
  2. Cloud Messaging › Web Push certificates: generate; copy into FCM_VAPID_KEY.
  3. Secrets for Cloud Functions:
       npx --prefix functions firebase functions:secrets:set GEMINI_API_KEY --project $project
       npx --prefix functions firebase functions:secrets:set GOOGLE_OAUTH_CLIENT_ID --project $project
       npx --prefix functions firebase functions:secrets:set GOOGLE_OAUTH_CLIENT_SECRET --project $project
       openssl rand -base64 32 | npx --prefix functions firebase functions:secrets:set CALENDAR_TOKEN_KEY --data-file=- --project $project
  4. Deploy functions and hosting:
       npx --prefix functions firebase deploy --project $project --only functions,hosting
  5. Platform operator: npx --prefix functions tsx functions/scripts/grant-operator.ts --project $project <your email>
EOF
