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

`GOOGLE_SERVER_CLIENT_ID` 和 `FCM_VAPID_KEY` 填過之後，重跑腳本會保留。網頁推播還需要 `app/web/firebase-messaging-sw.js`：它從 Hosting 的 `/__/firebase/init.js` 讀專案設定，所以 dev 和 prod 共用同一個檔案。

## 建置

```sh
cd app
flutter build web --dart-define-from-file=config/dev.json
flutter build apk --dart-define-from-file=config/dev.json
```

`config/*.json` 裡放的是專案識別資訊，不是密碼，但也不放進 git。

## 部署

```sh
scripts/deploy.sh dev                  # 建 Web 版，部署 Functions 和 Hosting
scripts/deploy.sh prod --only hosting  # 只更新網頁
```

- 專案取自 `app/config/<env>.json`，所以 dev 的 Web build 不會部署到 prod。
- 新專案第一次部署 Functions，常因 Eventarc 權限還沒生效而失敗。腳本會等 3 分鐘重試一次。
- 部署後設定 Functions 舊映像的清理規則，不然每月會有一點費用。映像庫第一次部署後才存在，所以放在這裡。
- rules 和 indexes 由 `firebase-project.sh` 部署，或 `scripts/firebase.sh <id> deploy --only firestore,storage`。

Hosting 部署前，會把 landing page 和法律文件複製進 Web build：
- `/about`
- `/privacy`
- `/terms`

## 平台營運者

```sh
scripts/as-owner.sh marthasit-dev npx --prefix functions tsx functions/scripts/grant-operator.ts --project marthasit-dev <email>
```

設定後要重新登入才會生效。之後「我的」頁會出現「平台後台」。

## App Links / Universal Links（教會網址與邀請連結直接開 App）

開 App 的路徑都在 `/c/` 底下：教會網址 `/c/<教會 id>`，邀請連結 `/c/<教會 id>/join/<邀請碼>`。host 等網域買好後一起換（#37）。

推播點開的連結也是教會網址：`/c/<教會 id>?to=<頁面>`，先切到那間教會再開該頁。網頁推播要完整網址，Functions 用 `APP_URL`（沒設就是 `https://<專案>.web.app`）；換成自己的網域時，記得在 Functions 設 `APP_URL`。

`firebase-messaging-sw.js` 只在 Hosting 上能用（要讀 `/__/firebase/init.js`）。用 `flutter run` 在本機跑時，網頁推播不會註冊成功，這是預期的。

- Hosting 設定忽略 `**/.*`，`.well-known` 會被擋掉，要在 `firebase.json` 的 `ignore` 例外放行。
- **Android**：`AndroidManifest.xml` 的 intent filter 是 `pathPrefix="/c/"`。Web build 要提供 `/.well-known/assetlinks.json`，內容包含簽章憑證的 SHA-256。
  - 取得 SHA-256：`keytool -list -v -keystore <keystore>`。
  - debug 和 release 的金鑰不同，兩個都要列進去。
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
