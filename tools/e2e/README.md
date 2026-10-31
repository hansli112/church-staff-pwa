# Browser checks

`smoke.mjs` drives the web build against the Firebase emulators: Google
sign-in (emulator popup), create a church (Cloud Function), arrange a
roster, create an invite, a second user joining through the link, and two
more asking to join from the church URL: one let in, one turned down.

```sh
cd functions && npm run build && cd ..
npx --prefix functions firebase emulators:start --only auth,firestore,functions,storage --project demo-martha &
cd app && flutter build web --wasm --dart-define=MARTHA_ENV=emulator --dart-define=E2E=true -o build/web-e2e && cd ..
cd tools/e2e && npm install && npm run smoke
```

`E2E=true` turns on Flutter's accessibility tree so the test can find
buttons by name. `--wasm` as in production: Chromium runs the wasm build
(the test gives it software WebGL; without WebGL it falls back to JS). The smoke test clears the emulators' data first.

`fonts.mjs <webdir>` checks the Chinese fonts are fetched as the app starts,
not when a word first shows: on 邀請 the toast 建立邀請連結 shows must not
ask for a font file, in Chromium (the wasm build, as Chrome and Android) and
WebKit (the JS one, as Safari). Build with `MARTHA_ENV=demo` and `E2E=true`
into `build/web-demo`, then `npm run fonts`. Run it after touching
`app/lib/core/fonts.dart` or upgrading Flutter.

`shoot.mjs <webdir> <outdir> /route,/route [--dark] [--engine=webkit] [--pages=N]`
screenshots routes at iPhone size, for design review. Build with
`MARTHA_ENV=demo` to get the in-memory sample church.
