#!/bin/sh
# Xcode build phase: sends this build's dSYMs to Crashlytics. Without them
# Crashlytics does not show iOS crashes at all.
#
# The app has no GoogleService-Info.plist (Firebase is configured from
# --dart-define-from-file=config/<env>.json), so the Firebase app ID comes
# from the build's dart defines, which Flutter passes base64-encoded and
# comma-separated in DART_DEFINES.
app_id=""
for define in $(echo "$DART_DEFINES" | tr ',' ' '); do
  pair="$(echo "$define" | base64 --decode 2>/dev/null)"
  case "$pair" in FIREBASE_IOS_APP_ID=*) app_id="${pair#*=}" ;; esac
done
if [ -z "$app_id" ]; then
  echo "note: no FIREBASE_IOS_APP_ID in the dart defines (emulator or demo build); not uploading dSYMs."
  exit 0
fi
exec "$PODS_ROOT/FirebaseCrashlytics/run" -ai "$app_id"
