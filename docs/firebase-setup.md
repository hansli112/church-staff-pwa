# Firebase 專案設定

dev、prod 兩個專案都放在 Hans 的**個人 Google 帳號**底下，不放進 dwave.cc organization。

| | 專案 ID | 網址 |
|---|---|---|
| dev | `marthasit-dev` | <https://marthasit-dev.web.app> |
| prod | `marthasit` | <https://marthasit.web.app>（網域買好後換成 `marthasit.app`） |

英文名「Martha, sit」，技術識別一律寫 `marthasit`。prod 不加後綴，因為 ID 會出現在網址和 Google 登入畫面上。

## 一次性準備

```sh
gcloud auth login                              # 個人帳號
gcloud config configurations create martha     # 只給這個專案用的設定
gcloud config set account <個人帳號>
```

Firebase CLI 和管理腳本都透過 `scripts/as-owner.sh` 用這個 gcloud 帳號執行（`scripts/firebase.sh` 是 Firebase CLI 的捷徑），不需要另外 `firebase login`，也不會用到這台機器上 `firebase login` 的其他帳號。

- billing account 只能在 console 建：<https://console.cloud.google.com/billing>
  - 帳戶類型選「個人」。台灣稅務身分：沒有統一編號就選 Unregistered individual，存了不能改。
  - 第一次建會是免費試用（US$300、90 天）。試用結束要按「啟用完整帳戶」，否則 Functions 和 Storage 會停。
- 個人帳號的專案配額滿了的話：
  - 刪掉不用的專案。刪除後要等 30 天才釋出配額。
  - 到 <https://support.google.com/code/contact/project_quota_increase> 申請提高配額。
  - 用另一個 Gmail（不是 Workspace 帳號，否則專案會掛進那個組織）建專案，再把個人帳號加成擁有者。目前兩個專案都是這樣建的，建立者是教會帳號。
    - 另開一個 gcloud 設定給那個帳號，執行腳本時用 `MARTHA_GCLOUD_CONFIG=<設定名稱>` 指定。
    - 擁有者不能用 gcloud 加（`SOLO_MUST_INVITE_OWNERS`）：在 console 的 IAM 頁邀請，個人帳號收信接受。
    - 接受後其餘步驟都用個人帳號，最後把建立者從 IAM 移除（兩個專案都已移除）。

## 建立或補齊專案

```sh
scripts/firebase-project.sh dev  marthasit-dev [BILLING_ACCOUNT_ID]
scripts/firebase-project.sh prod marthasit     [BILLING_ACCOUNT_ID]
```

腳本可以重跑，每一步都會先檢查。加 `--dry-run` 只印出指令。它做的事：
- 建專案，並確認專案沒有 parent organization。
- 連結 billing account（Blaze）。
- 開需要的 API，加入 Firebase。
- 建 Firestore，地區 `asia-east1`。
- 開 email＋密碼登入，設定同一 email 只能有一個帳號。
- 註冊 Web、Android、iOS App，寫出 `app/config/<env>.json`。
- 建 Storage bucket。
- 部署 rules 和 indexes。
- 有 billing 時：
  - 開需要付費方案的 API（Functions、Cloud Run、排程、Secret Manager…）。
  - 給 Google 服務帳號 Functions 部署需要的角色。`firebase deploy` 自己加有時會失敗（"We failed to modify the IAM policy"）。
  - 建 Functions 用的 secret，值不會印出來：`CALENDAR_TOKEN_KEY` 隨機產生；行事曆的 OAuth client 先放佔位值，部署和其他功能不受影響，只有連接行事曆會失敗。
  - 照片辨識走 Vertex AI 上的 Gemini，用 Functions 的服務帳號（給 `roles/aiplatform.user`），不用 API key。費用算在專案的 Cloud Billing（試用帳戶也能呼叫）。AI Studio 的 Gemini API 是另外的預付額度，Cloud 試用金明文不能付。
  - 設 budget alert：NT$300 / 月，50%、90%、100% 各通知一次，寄給 billing 擁有者。

腳本最後會列出要手動做的步驟。這些 Google 沒有 API：
- 在 console 開 Google 登入，並把 Web client ID 填到 config 的 `GOOGLE_SERVER_CLIENT_ID`。
- 產生 Web Push 金鑰，填到 `FCM_VAPID_KEY`。
- 設定 OAuth 同意畫面，建一個「網頁應用程式」OAuth client，用 `gcloud secrets versions add` 換掉兩個佔位 secret。

Function 改掉不用某個 secret 時，`firebase deploy` 不會拿掉已部署版本上的 secret 綁定。要先 `scripts/firebase.sh <id> functions:delete <名稱> --region asia-east1` 再部署一次，確認綁定拿掉之後才能刪 secret，不然新的 instance 起不來。

`GOOGLE_SERVER_CLIENT_ID` 和 `FCM_VAPID_KEY` 填過之後，重跑腳本會保留。`GOOGLE_IOS_CLIENT_ID` 由腳本從 iOS app 的 `GoogleService-Info.plist` 讀出來；要先開 Google 登入，Firebase 才會建這個 client，所以開完要重跑一次腳本。iOS 的 Google 登入另外要把它反過來的 `com.googleusercontent.apps.…` 列在 `app/ios/Runner/Info.plist` 的 `CFBundleURLTypes`，dev 和 prod 兩個都列。網頁推播還需要 `app/web/firebase-messaging-sw.js`：它從 Hosting 的 `/__/firebase/init.js` 讀專案設定，所以 dev 和 prod 共用同一個檔案。

## 建置

```sh
cd app
flutter build web --dart-define-from-file=config/dev.json
flutter build apk --dart-define-from-file=config/dev.json
```

`config/*.json` 裡放的是專案識別資訊，不是密碼，但也不放進 git。

iOS 要在 Mac 上 build，最低版本是 iOS 15（Firebase 的要求）。Xcode 的「Upload Crashlytics symbols」會把 dSYM 傳到這次 build 的 Firebase app。app ID 從 dart define 讀，所以直接在 Xcode 按 Archive 時，傳去的是最近一次 `flutter build` 用的環境。上架用的 build 用 `shorebird release ios`（見下一節），它一樣跑 Xcode 的 archive，dSYM 照常上傳。

### 上架與熱更新（Shorebird）

上架的 Android、iOS 版用 Shorebird 建置，之後緊急的 bug 可以直接推修補，不用等商店審查（#79）。Shorebird 的 app 是 `app/shorebird.yaml` 的 `app_id`，帳號是個人的 Shorebird 帳號（`~/.shorebird/bin/shorebird login`）。

**上架**：取代 `flutter build appbundle` / `flutter build ipa`，產生的 AAB / IPA 一樣自己上傳到商店。`--flutter-version` 跟本機的 Flutter 一樣（`flutter --version`）：

```sh
cd app
~/.shorebird/bin/shorebird release android --flutter-version=3.41.0 --dart-define-from-file=config/prod.json
~/.shorebird/bin/shorebird release ios --flutter-version=3.41.0 --export-options-plist=ios/ExportOptions.plist --dart-define-from-file=config/prod.json
```

每一版都要這樣建，之後才能對它推修補；直接用 `flutter build` 上架的版本收不到修補。

**iOS 簽章與上傳**（不用 Xcode 登入）：Release 用手動簽章，憑證「Apple Distribution: Hsueh Han Lee」和描述檔「Martha sit App Store」都是用 App Store Connect API 金鑰建的（見 `app/ios/ExportOptions.plist`）。私鑰在 Mac 的登入鑰匙圈，備份在 `~/.appstoreconnect/signing/`；換電腦要把那裡的 `distribution.p12` 匯入鑰匙圈，描述檔放進 `~/Library/MobileDevice/Provisioning Profiles/`。第一次簽章時 macOS 會問 codesign 能不能用這把鑰匙，輸入 Mac 密碼按「永遠允許」。用上面的 `shorebird release ios` 建好，再上傳到 TestFlight：

```sh
xcrun altool --upload-app -t ios -f build/ios/ipa/*.ipa --apiKey <金鑰 ID> --apiIssuer <Issuer ID>
```

兩個都在 2027-10 到期，到期前用 API（同一把金鑰簽的 JWT）重建：
1. `openssl genrsa` 產生新私鑰和 CSR，`POST /v1/certificates`（`certificateType: DISTRIBUTION`）拿到憑證，和私鑰包成 `.p12` 用 `security import … -T /usr/bin/codesign` 匯入登入鑰匙圈。鑰匙圈要有 Apple WWDR G3 中繼憑證（apple.com/certificateauthority），否則 `security find-identity -v -p codesigning` 看不到它。
2. `POST /v1/profiles`（`profileType: IOS_APP_STORE`，名稱一樣叫 Martha sit App Store，bundle ID `app.marthasit`，用新憑證），把回傳的描述檔存成 `<UUID>.mobileprovision` 放進上面的資料夾。描述檔要有推播和 Sign in with Apple（App ID 開著，就會帶進去）。

API 金鑰放在 `~/.appstoreconnect/private_keys/AuthKey_<金鑰 ID>.p8`，altool 會自己找到。`Info.plist` 寫了 `ITSAppUsesNonExemptEncryption = false`（只用 HTTPS），上傳後不用每次回答出口合規。

**App Store 截圖**（`store/ios/<語言>-<iphone|ipad>-<n>.png`）：示範模式加 `--dart-define=DEMO_ROUTE=<頁面>` 會直接開在那一頁，不用點。`flutter build ios --simulator --debug --dart-define=MARTHA_ENV=demo --dart-define=DEMO_ROUTE=/rosters`，裝到 iPhone 17 Pro Max（6.9 吋）和 iPad Pro 13 吋模擬器，`xcrun simctl status_bar <裝置> override --time 9:41 …`，每種語言先 `xcrun simctl spawn <裝置> defaults write app.marthasit AppleLanguages -array <語言>` 再重開 App，`xcrun simctl io <裝置> screenshot` 拍。現在是兩張：`/rosters/sunday/<日期>` 和 `/rosters`。用 API 的 `appScreenshotSets`（`APP_IPHONE_67`、`APP_IPAD_PRO_3GEN_129`）上傳。

**建好馬上上傳，或先複製一份**：之後跑 `shorebird patch` 會用修補的程式碼重建，蓋掉 `app/build/app/outputs/bundle/release/app-release.aab`。`shorebird preview` 下載到 `~/.shorebird/bin/cache/previews/` 的 AAB 也被改過，Play 會說簽章無效，不能上傳。1.0.0+13 就是這樣作廢的，所以從 +14 開始上架。

**什麼能熱更新**：只有 Dart 程式碼，例如修 bug、改文字、調畫面。圖片、字型、原生程式碼、新套件、權限、App 圖示都要重新上架。只拿來修小 bug：iOS 上修補改到的函式要用直譯器跑，大約慢 100 倍，大改畫面或吃運算的地方會卡。新功能照常上架。

改文字時 `shorebird patch` 會說資源有改動而停下來：`lib/l10n/*.arb` 也列在 pubspec 的 assets，但只有網頁版預載字型時讀（`lib/core/fonts.dart`），手機 App 的文字來自產生的 Dart 程式碼。所以**只有 ARB 改動**時，可以加 `--allow-asset-diffs`；改到其他資源就一定要重新上架。

**推修補**：先推到 staging，只有用 `shorebird preview` 裝的手機收得到。preview 裝的版本簽章跟商店版不同，Google 登入會失敗（`invalid-cert-hash`），只能看不用登入的畫面；要測登入後的畫面，改用 Shorebird Console 的百分比推送先給少數人。確認沒問題再改成 stable。App 打開時在背景下載修補，**下一次打開才生效**，所以大家要再開一次 App 才換到修補版：

```sh
~/.shorebird/bin/shorebird patch android --release-version=1.0.0+14 --track=staging --dart-define-from-file=config/prod.json
~/.shorebird/bin/shorebird preview --release-version=1.0.0+14 --track=staging   # 接上測試手機或模擬器
~/.shorebird/bin/shorebird patches set-track --release-version=1.0.0+14 --patch-number=1 --track=stable
```

推錯了：`~/.shorebird/bin/shorebird patches rollback --release-version=… --patch-number=…`，已經套用的人重開 App 後換回來，可能要重開兩次（一次得知撤回、一次生效）。

**注意**：

- Play 封閉測試、TestFlight 的分組沒辦法用來分批推修補，要分批用上面的 staging，或 Shorebird Console 的百分比推送。
- Shorebird 只支援 Flutter 穩定版，新的季版本最多 5 個工作天才支援。升級 Flutter 前先看 `~/.shorebird/bin/shorebird flutter versions list` 有沒有。
- iOS 不要開 `--obfuscate`，Shorebird 不支援。
- Crashlytics：我們沒有用 `--obfuscate` 或 `--split-debug-info`，Dart 的錯誤堆疊本來就看得懂，修補版不用另外上傳符號。當機報告的 custom key `shorebird_patch_number` 是當時跑的修補（0 是沒有），「我的」的版本也會寫「修正 N」，回報問題時看得出有沒有拿到修補。
- App 每次打開都會連 Shorebird，隱私權政策第 3.8 節寫了送出什麼。
- 網頁版不用 Shorebird，部署完就更新。

### 檢查 Crashlytics 與 GA4

- **Crashlytics**：dev 版「我的」→「開發」→「測試當機」。App 會直接當掉，重開之後才會送出報告，幾分鐘內出現在 Firebase console 的 Crashlytics。
- **GA4**：專案要先在 Firebase console 的「專案設定」→「整合」連結 Google Analytics，`church_id` 才收得到。看 DebugView 要先開除錯模式：
  - Android：`adb shell setprop debug.firebase.analytics.app app.marthasit`
  - iOS：在 Xcode 的 Runner scheme 加上啟動參數 `-FIRDebugEnabled`
- Android 沒有 `google-services.json`，GA4 在 Dart 之前就啟動，讀不到 `main.dart` 給的 Firebase 設定，所以 `android/app/build.gradle.kts` 從 `--dart-define-from-file` 取 `FIREBASE_ANDROID_APP_ID` 寫成 `google_app_id` 資源。少了它 GA4 不會報錯，只在 logcat 寫 `Missing google_app_id. Firebase Analytics disabled`（1.0.0+14 以前的版本都是這樣）。有了 app ID，Android 會在 Dart 之前用這些資源建立預設的 Firebase app，所以 API key、project ID、sender ID、storage bucket 也要一起寫，和 `env.dart` 給的一樣；只寫 app ID 時 `Firebase.initializeApp` 會丟 `duplicate-app`，App 停在啟動畫面（1.0.0+15 就是這樣，沒有上架）。確認：`adb logcat -s FA FA-SVC` 要看到 `Logging event` 和 `upload successful`。

## 部署

```sh
scripts/deploy.sh dev                  # 建 Web 版，部署 Functions 和 Hosting
scripts/deploy.sh prod --only hosting  # 只更新網頁
```

- 專案取自 `app/config/<env>.json`，所以 dev 的 Web build 不會部署到 prod。
- 新專案第一次部署 Functions，常因 Eventarc 權限還沒生效而失敗。腳本會等 3 分鐘重試一次。
- `playBillingNotifications` 失敗會自動重試，第一次部署到某個專案時，Firebase CLI 要確認這件事，非互動模式會停下來。先單獨部署它一次：`scripts/firebase.sh <專案> deploy --only functions:playBillingNotifications --non-interactive --force`，再跑 `deploy.sh`。不要直接給 `deploy.sh` 加 `--force`：它也會刪掉程式碼裡沒有的 Functions。
- Functions 的套件（Firestore SDK 等）要 Node 22 以上才會裝。用 ssh 在別台機器執行時，先載入 nvm 選 Node 22+，否則 `npm ci` 會略過這些套件，部署時 TypeScript 編譯失敗。
- 部署後設定 Functions 舊映像的清理規則，不然每月會有一點費用。映像庫第一次部署後才存在，所以放在這裡。
- rules 和 indexes 由 `firebase-project.sh` 部署，或 `scripts/firebase.sh <id> deploy --only firestore,storage`。

Hosting 部署前，`scripts/hosting-predeploy.sh` 用 `scripts/build-site.mjs` 把網站放進 Web build（需要 Node；第一次會在 `landing/` 跑 `npm ci`）。網站各頁共用的頁首、頁尾在 `build-site.mjs` 裡，`landing/` 的頁面用 `<!-- site-header -->`、`<!-- site-footer -->` 標位置。

字型改寫完成後，`fingerprint-web.mjs` 把 `main.dart.js` 與 deferred JS 改成帶內容 hash 的檔名，並透過 loader 的 `config.assetBase` 指向 `asset-bundles/<內容 hash>/assets/`：同版的字型 manifest、字型、圖片與其他 Flutter assets 一起保留，舊 bootstrap 不會讀到新版少了圖示的字型。asset tree 不變就共用同一個 bundle；歷史 loose 字型不算進新版的 tree。這些版本化檔案快取一年；HTML、`flutter_bootstrap.js`、穩定的 `assets/` 與保留給舊 bootstrap 的 `main.dart.js` 不改網址（manifest 與入口仍 `no-cache`）。`deploy.sh` 用 `flutter build web --wasm`：同一份 build 有 wasm 版與 JS 版，Chrome／Android 跑 wasm，Safari、iOS 上所有瀏覽器與 Firefox 由 Flutter 的 loader 改跑 JS。wasm 版的 `main.dart.wasm` 和它的 JS 模組 `main.dart.mjs` 一樣各自改成帶內容 hash 的檔名、留在 archive，舊名同樣保留給舊 bootstrap；只有 wasm、沒有 JS 版的 build 會在修改產物前被拒絕。`release-web.mjs` 讓 loader 固定用單執行緒的 skwasm（多執行緒要 COOP/COEP，會擋掉 Google 登入彈窗）。App 殼第一次離線安裝時，三個主程式入口和引擎一樣只快取這個瀏覽器用到的那組；手動更新才整版下載。所以同一支手機若之後改跑另一組（例如 WebGL 被停用而退回 JS），在下載到之前離線開不起來。「更新並重新開啟」由頁面告訴 worker 目前的路徑：worker 看得到的分頁網址是分頁一開始開啟的那頁（App 從 `/home` 開始），不是 App 之後切換到的頁面。

**保留 `.firebase/web-assets/`**：每個 Firebase 專案分開累積已準備部署的 hashed JS／wasm 入口、Flutter asset bundles 與相容舊網址的字型，下一次部署一併上傳。新檔案／bundle 先寫到暫存位置並驗證，再原子改名；中斷留下的暫存檔不會發布，重跑也不覆寫已驗證相同的完整檔案。`deploy.sh` 建置前只清掉產物 `app/build/web` 與 Flutter 的建置快取 `app/.dart_tool/flutter_build`，避免 dev／prod 的舊 hash 或舊的產生碼混入（快取曾留下換套件前的 web plugin registrant，部署出舊套件）；archive 不受影響。手動建置／部署也要使用乾淨的 Web 產物；腳本會拒絕沿用另一個專案的產物。失敗或重試不會刪掉舊版本，也不自動清理；空間會隨改版增加。換部署電腦／worktree 時，要先移轉這個目錄；沒有它就無法保留先前部署的 hash。這不是完整網站備份。腳本測試：`node --test scripts/test/*.test.mjs`（需現有的 `landing/node_modules`）。

- `/`：landing page。Flutter 的 `index.html` 改名成 `app.html`，其他路徑都 rewrite 到它，所以網頁版從 `/home` 開始（manifest 的 `start_url`）。舊的 `/about` 轉到 `/`。
- `/support`：支持頁。顯示這個月的雲端費用和每一項費用（不用登入就讀 `platform/funding`），以及網站的線上支持按鈕。線上支持預設關著（只寫「線上支持即將開放」，沒有按鈕），部署時加 `SUPPORT_PAYMENTS=on` 才有選金額和付款，見〈線上支持（綠界）〉。`/support/pay` rewrite 到 `ecpayStart`。
- `/blog/`：教學文章。每篇是 `landing/blog/<網址>.md`，開頭寫 `title`、`date`、`description`，會變成 `/blog/<網址>/`。
- `/privacy`、`/terms`：App 會打開這兩頁，所以它們沒有網站的頁首、頁尾，也不連到首頁，從 App 點不到支持頁（商店不准 App 把人帶去外部付款）。

本機預覽網站：`node scripts/build-site.mjs <資料夾> --origin http://localhost:8090`，再用任何靜態伺服器打開那個資料夾。

改成這個配置後第一次部署，Functions 與 Hosting 要一起部署（`deploy.sh` 預設就是）。只部署 Hosting 的話，舊版 `churchPage` 會去抓 `index.html`，拿到 landing page；新版只接受 `app.html` 裡的 Flutter 頁。

OAuth 同意畫面的首頁網址填 `/`，隱私權政策填 `/privacy`：Google 不接受只有登入畫面的首頁。

## 雲端費用進度（商店付款通知）

支持頁的進度條由後端自動加總收入。平台營運者只在「平台後台」→ 存錢筒圖示裡填費用清單，價格變了才需要改。每天 00:10（台北時間）`fundingDaily` 會開新的月份、更新匯率。

- **Apple**（要先付年費，#38）：
  1. App Store Connect → App 資訊 →「App Store 伺服器通知」選 Version 2：
     - 正式環境網址：`https://asia-east1-marthasit.cloudfunctions.net/appStoreNotifications`
     - 沙盒網址：`https://asia-east1-marthasit-dev.cloudfunctions.net/appStoreNotifications`。TestFlight 和沙盒的付款只會進 dev。prod 會拒收 sandbox 通知，dev 也會拒收正式環境的，網址設反了不會把測試的錢算進去。
  2. App Store Connect 上的 Apple ID（`6823826952`）已經填進 `functions/src/fundingApple.ts` 的 `APPLE_APP_ID`。少了它，正式環境的通知驗證會失敗，Apple 會一直重送。
  3. 加入 App Store Small Business Program，抽成才是 15%。收入估算用的是 15%。
- **Google Play**（Play Console 建好 App 之後）：
  1. 部署 prod 時會自動建立 Pub/Sub 主題 `play-billing`。在 GCP console 把 `google-play-developer-notifications@system.gserviceaccount.com` 加成這個主題的「Pub/Sub 發布者」。
  2. Play Console →「營利設定」→「即時開發人員通知」，主題填 `projects/marthasit/topics/play-billing`，按「傳送測試通知」。
  3. Play Console →「使用者和權限」邀請 Functions 的服務帳號（`<專案編號>-compute@developer.gserviceaccount.com`），權限勾「查看財務資料」。查訂單（`orders.get`）要這個權限。
  - 一個 App 只能設一個主題，所以 Google 的通知只進 prod。授權測試帳號的購買會被略過，不算進收入。
- 匯率來自 `open.er-api.com`，每天抓一次，抓不到就沿用上次的匯率（超過 7 天會記錯誤 log）。免費方案要求在用到匯率的頁面註明來源，支持頁已加上。

## 線上支持（綠界）

網站支持頁的一次性付款，走綠界全方位金流 AIO（規格在綠界開發者網站 developers.ecpay.com.tw：產生訂單 ?p=2862、檢查碼機制 ?p=2902、付款結果通知 ?p=2878、測試介接資訊 ?p=2856）。流程和資料見 `docs/design.md`〈金流〉。三支 Function：

| Function | 網址 | 誰呼叫 |
|---|---|---|
| `ecpayStart` | `<網站>/support/pay`（Hosting rewrite） | 支持頁，開單並拿到要送去綠界的表單 |
| `ecpayNotify` | `https://asia-east1-<專案>.cloudfunctions.net/ecpayNotify` | 綠界在背景通知付款結果（ReturnURL），回 `1\|OK` |
| `ecpayReturn` | `https://asia-east1-<專案>.cloudfunctions.net/ecpayReturn` | 付款人的瀏覽器付完回來（OrderResultURL），轉到 `/support?paid=1` |

綠界的名稱和我們的 Function 對不太上：綠界的 **ReturnURL 是背景通知**（`ecpayNotify`），**OrderResultURL 才是付款人的瀏覽器回來**（`ecpayReturn`）。這兩個和 ClientBackURL（綠界頁面上的「返回商店」，`<網站>/support`，其他語言是 `<網站>/<語言>/support`）每筆交易都由 `ecpayStart` 帶給綠界，不用在綠界後台設定。

設定分三處，三處都齊了才會開單，少一樣 `ecpayStart` 就回「暫時無法使用」：
- **金鑰**（Secret Manager）：`ECPAY_HASH_KEY`、`ECPAY_HASH_IV`（各 16 字元），在綠界廠商後台 → 系統開發管理 → 系統介接設定。`firebase-project.sh` 先建好佔位值；佔位值長度不對，等於關著。
- **特店編號和環境**：`functions/.env.<專案 ID>`（不進 git，部署的那台電腦要有），例如 `functions/.env.marthasit-dev`：
  ```
  ECPAY_MERCHANT_ID=3002607
  ECPAY_ENV=test
  ```
  `ECPAY_ENV` 是 `test`（送到 `payment-stage.ecpay.com.tw`）或 `production`（送到 `payment.ecpay.com.tw`）。prod（`marthasit`）只接受 `production`，測試付款不會算進正式的進度。
- **網站**：Hosting 部署時加 `SUPPORT_PAYMENTS=on`，支持頁才出現選金額和付款按鈕（`hosting-predeploy.sh` → `build-site.mjs --payments on`）。同一個開關也讓網頁版 App 的「我的」出現「支持馬大別忙」，連到網站的支持頁（`deploy.sh` → `--dart-define=SUPPORT_PAYMENTS=on`）。沒加就只寫「線上支持即將開放」、網頁版 App 沒有這一列，每次部署 Hosting 都要加。

**第一次部署前**：Functions 宣告了這兩個 secret，專案裡沒有的話 `firebase deploy` 會停下來。已經建好的專案重跑一次 `scripts/firebase-project.sh`（只會補上缺的佔位 secret），或手動建：
```sh
printf placeholder | gcloud secrets create ECPAY_HASH_KEY --project <專案> --replication-policy=automatic --data-file=-
printf placeholder | gcloud secrets create ECPAY_HASH_IV  --project <專案> --replication-policy=automatic --data-file=-
```

**dev 用綠界公開的測試特店**（大家共用，不是秘密）：特店編號 `3002607`，HashKey、HashIV 在〈測試介接資訊〉（?p=2856）。
1. 換掉佔位 secret（值照抄測試介接資訊）：
   ```sh
   printf %s '<測試 HashKey>' | gcloud secrets versions add ECPAY_HASH_KEY --project marthasit-dev --data-file=-
   printf %s '<測試 HashIV>'  | gcloud secrets versions add ECPAY_HASH_IV  --project marthasit-dev --data-file=-
   ```
2. 寫 `functions/.env.marthasit-dev`（上面的格式）。
3. 部署：`SUPPORT_PAYMENTS=on scripts/deploy.sh dev`。secret 和 `.env` 都是部署時讀的，改了要再部署 Functions。
4. 測試：開 `https://marthasit-dev.web.app/support` 付一筆，測試卡號 `4311-9522-2222-2222`（有效期限要晚於今天、末三碼隨便填，3D 驗證碼 `1234`）。確認：付完回到支持頁顯示謝謝；`fundingPayments/ecpay_<訂單號碼>` 出現；支持頁的金額變多。Function 的 log 搜尋 `ECPay`。綠界測試後台的「模擬付款」送來的通知帶 `SimulatePaid=1`，不算進度。

**正式上線（prod）**：
1. 綠界廠商後台 → 系統開發管理 → 系統介接設定：複製特店編號、HashKey、HashIV。只在自己的終端機貼，不要貼到對話或檔案裡：
   ```sh
   gcloud secrets versions add ECPAY_HASH_KEY --project marthasit --data-file=-
   ```
   （貼上 HashKey，按 Enter 再按 Ctrl-D；HashIV 同樣做一次，名稱換成 `ECPAY_HASH_IV`。）
2. `printf 'ECPAY_MERCHANT_ID=<正式特店編號>\nECPAY_ENV=production\n' > functions/.env.marthasit`
3. `SUPPORT_PAYMENTS=on scripts/deploy.sh prod`
4. 正式付一筆小額確認，再到綠界後台退款（退款不會自動從進度扣掉）。
5. 隱私權政策和服務條款講綠界的段落跟著 `SUPPORT_PAYMENTS=on` 出現（五種語言的 `privacy.html`、`terms.html` 裡的 `payments:on`）。正式打開的那次，把這兩頁五種語言的「最後更新」改成當天。

**從測試換到正式**：測試特店和正式特店的編號和兩把金鑰都不一樣。三樣一起換（secret 加新版本、`.env` 的 `ECPAY_MERCHANT_ID` 和 `ECPAY_ENV=production`），再部署 Functions。

**從藍新換過來的專案**（2026-10-16 以前建的）：`deploy.sh` 不會自己刪 Function，先刪掉舊的三支再部署，部署完把舊 secret 也刪掉：
```sh
npx --prefix functions firebase functions:delete newebpayStart newebpayNotify newebpayReturn --region asia-east1 --project <專案> --force
gcloud secrets delete NEWEBPAY_HASH_KEY --project <專案> --quiet
gcloud secrets delete NEWEBPAY_HASH_IV --project <專案> --quiet
```
新的 secret 也要先建（見上面的「第一次部署前」）。

關掉線上支持：Hosting 部署時不加 `SUPPORT_PAYMENTS=on`（支持頁回到「線上支持即將開放」）；要連後端一起停，把 `.env` 的 `ECPAY_MERCHANT_ID` 拿掉再部署 Functions。

## 平台營運者

```sh
scripts/as-owner.sh marthasit-dev npx --prefix functions tsx functions/scripts/grant-operator.ts --project marthasit-dev <email>
```

設定後要重新登入才會生效。之後「我的」頁會出現「平台後台」。

## 要求更新手機 App（最低版本）

`platform/app` 的 `minBuild.android`、`minBuild.ios` 是商店 App 最低能用的 build number（`pubspec.yaml` 的 `+N`）。比它舊的 App 一打開（或回到前景時）就整個畫面要求更新，按鈕打開 Google Play / App Store。沒有這份文件、或是 0，什麼都不擋。網頁版不受影響，它自己會更新。

先確認新版已經在商店上架、大家更新得到，再調高。`ios` 的按鈕用 `app/lib/state/app_build.dart` 的 `appleAppId`（App Store Connect →「App 資訊」的 Apple ID）打開 App Store，App 上架之前那一頁打不開。


```sh
PROJECT=marthasit   # 或 marthasit-dev
curl -sS -X PATCH \
  -H "Authorization: Bearer $(CLOUDSDK_ACTIVE_CONFIG_NAME=martha gcloud auth print-access-token)" \
  -H 'Content-Type: application/json' \
  "https://firestore.googleapis.com/v1/projects/$PROJECT/databases/(default)/documents/platform/app?updateMask.fieldPaths=minBuild" \
  -d '{"fields":{"minBuild":{"mapValue":{"fields":{"android":{"integerValue":"12"},"ios":{"integerValue":"12"}}}}}}'
```

或在 Firebase Console 的 Firestore 直接改。App 不能寫這份文件（`firestore.rules`）。

## iOS 推播與 Sign in with Apple

兩個都要付費開發者帳號（#38）。`app/ios/Runner/Runner.entitlements` 已經有 `aps-environment` 和 `com.apple.developer.applesignin`。Xcode 封存上架時，會自動把 `aps-environment` 換成 `production`。

**推播（APNs）**
1. Apple Developer → Identifiers → `app.marthasit`：勾 Push Notifications、Sign in with Apple。
2. Keys → 新增一把金鑰，勾 Apple Push Notifications service（APNs），下載 `.p8`，記下 Key ID 和 Team ID。`.p8` 只能下載一次，要另外備份，不進 git。
3. 兩個 Firebase 專案 → 專案設定 → Cloud Messaging → Apple 應用程式設定：上傳同一把 `.p8`，填 Key ID、Team ID。
4. 實機測：關掉 App，從另一個帳號改服事表，鎖定畫面要收到通知。模擬器收不到 APNs 推播。

**Sign in with Apple**
1. 兩個 Firebase 專案 → Authentication → 登入方式 → 開 Apple。只用 iOS 原生登入時，這樣就夠了。
2. 網頁和 Android 走 Apple 的網頁登入，還要：
   - Apple Developer → Identifiers → Services IDs：新增一個，例如 `app.marthasit.signin`，勾 Sign in with Apple，Primary App ID 選 `app.marthasit`。Domains 填 `marthasit.com`、`marthasit.firebaseapp.com`、`marthasit-dev.firebaseapp.com`。Return URL 填 `https://<專案>.firebaseapp.com/__/auth/handler`，dev、prod 各一個。
   - Keys → 新增一把金鑰，勾 Sign in with Apple。這把金鑰和 APNs 那把可以是同一把。
   - Firebase 的 Apple 登入填 Services ID、Team ID、Key ID 和金鑰內容。
   - 填好之後，建置加 `--dart-define=APPLE_SIGN_IN=true`，網頁和 Android 的登入頁才會出現 Apple 按鈕。iOS 一律會出現。
3. **Apple 的隱藏 email**（`…@privaterelay.appleid.com`）只轉寄 Apple 認得的寄件網域。到 Apple Developer → Services → Sign in with Apple for Email Communication，加入 Firebase 寄信的網域：Authentication → 範本裡的寄件者，預設是 `noreply@<專案>.firebaseapp.com`。Apple 會檢查 SPF，Firebase 的網域本來就有。改用自己的網域寄信時，也要把那個網域加進去。
4. **刪除帳號**：用 Apple 登入的帳號在 iOS 上刪除時，App 會請使用者再用 Apple 確認一次，然後撤銷 Apple 的 token（App Store 5.1.1(v)）。網頁和 Android 不能撤銷（firebase_auth 只在 Apple 平台提供），只刪除帳號。
5. 同一個 email 已經有帳號時，Firebase 會拒絕 Apple 登入（`account-exists-with-different-credential`）。App 請使用者先用原本的方式登入，登入後自動連上 Apple。用隱藏 email 的 Apple 帳號不會撞到其他帳號，會是另一個新帳號。

## App Links / Universal Links（教會網址與邀請連結直接開 App）

開 App 的路徑都在 `/c/` 底下：教會網址 `/c/<教會 id>`，邀請連結 `/c/<教會 id>/join/<邀請碼>`。host 等網域買好後一起換（#37）。

推播點開的連結也是教會網址：`/c/<教會 id>?to=<頁面>`，先切到那間教會再開該頁。網頁推播要完整網址，Functions 用 `APP_URL`（沒設就是 `https://<專案>.web.app`）；換成自己的網域時，記得在 Functions 設 `APP_URL`。

`firebase-messaging-sw.js` 只在 Hosting 上能用（要讀 `/__/firebase/init.js`）。用 `flutter run` 在本機跑時，網頁推播不會註冊成功，這是預期的。

網頁推播的顯示規則寫在這個檔案裡：app 的分頁正在使用（有 focus）時，交給 app 用 toast 顯示；其他情況一律顯示系統通知。不照 Firebase SDK 原本「分頁看得見就不顯示」的規則，否則分頁被別的視窗擋住時，Chrome 會另外跳一則「This site has been updated in the background」。點通知時如果已經有分頁開著，SDK 只會切到那個分頁並傳訊息給它，導頁由 app 處理（`push_clicks_web.dart`）。

用 Playwright 接著瀏覽器測推播時，頁面會一直被當成在前景，要先斷開連線，才能測背景通知。

- Hosting 忽略點開頭的檔案，只放行 `.well-known`。`firebase.json` 的 `ignore` 不支援 `!` 例外，所以用 `**/.!(well-known)`。
- **Android**：`AndroidManifest.xml` 的 intent filter 是 `pathPrefix="/c/"`。網站從 `app/web/.well-known/assetlinks.json` 提供簽章憑證的 SHA-256，dev 和 prod 共用這個檔案。
  - 取得 SHA-256：`keytool -list -v -keystore <keystore>`。debug 金鑰在 `~/.android/debug.keystore`，密碼 `android`。
  - 每台 build 的電腦 debug 金鑰都不同，目前只列了一台開發用的 Mac。
  - 上架用的是上傳金鑰（upload key）：`~/.martha/upload-keystore.jks`，密碼在 `app/android/key.properties`（不進 git）。release build 有這個檔就用它簽，沒有就用 debug 金鑰。金鑰和密碼要另外備份；遺失了要到 Play Console 申請重設上傳金鑰。
  - 上傳金鑰的 SHA 已列在 assetlinks 和兩個專案的 Firebase。從 Play 商店安裝的 App 是 Play App Signing 的金鑰簽的（在 Play Console 的「應用程式完整性」查），它的 SHA-1、SHA-256 也要加進這兩處。
  - 原生 Google 登入也看簽章：同一組 SHA-1、SHA-256 要加到 Firebase 的 Android app（`apps:android:sha:create`）。
- **iOS**：要付費開發者帳號，才能開 Associated Domains。
  - 在 `Runner.entitlements` 加上 `applinks:<網域>`。
  - 網站提供 `/.well-known/apple-app-site-association`，`components` 只放 `{"/": "/c/*"}`。
  - 這部分在 M7 處理。

## 照片辨識匯入（self-host → 代管）

見 `functions/scripts/import-selfhost.ts` 開頭的說明。順序：
1. 先 `--dry-run`，只看筆數。
2. 匯入 dev，對照筆數和內容。
3. 匯入 prod。
4. 執行 `.local/auth-import.sh` 搬帳號。執行完刪掉這個檔案，裡面有密碼雜湊金鑰。
