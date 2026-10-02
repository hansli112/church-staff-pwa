# Browser checks

`smoke.mjs` drives the web build against the Firebase emulators: Google
sign-in (emulator popup), create a church (Cloud Function), arrange a
roster, create an invite, and a second user joining through the link.

```sh
cd functions && npm run build && cd ..
npx --prefix functions firebase emulators:start --only auth,firestore,functions,storage --project demo-martha &
cd app && flutter build web --dart-define=MARTHA_ENV=emulator --dart-define=E2E=true -o build/web-e2e && cd ..
cd tools/e2e && npm install && npm run smoke
```

`E2E=true` turns on Flutter's accessibility tree so the test can find
buttons by name. The smoke test clears the emulators' data first.

`shoot.mjs <webdir> <outdir> /route,/route [--dark] [--engine=webkit] [--pages=N]`
screenshots routes at iPhone size, for design review. Build with
`MARTHA_ENV=demo` to get the in-memory sample church.
