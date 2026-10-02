# Firebase 專案設定

dev、prod 兩個專案都放在 Hans 的**個人 Google 帳號**底下，不放進 dwave.cc organization。

## 一次性準備

```sh
gcloud auth login                              # 個人帳號
gcloud config configurations create martha     # 只給這個專案用的設定
gcloud config set account <個人帳號>
npx --prefix functions firebase login          # 同一個帳號
```

- billing account 只能在 console 建：<https://console.cloud.google.com/billing>
- 個人帳號的專案配額滿了的話，有兩個辦法：
  - 刪掉不用的專案。刪除後要等 30 天才釋出配額。
  - 到 <https://support.google.com/code/contact/project_quota_increase> 申請提高配額。

## 建立或補齊專案

```sh
scripts/firebase-project.sh dev  martha-app-dev [BILLING_ACCOUNT_ID]
scripts/firebase-project.sh prod martha-app     [BILLING_ACCOUNT_ID]
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
- 設 budget alert：NT$300 / 月，50%、90%、100% 各通知一次，寄給 billing 擁有者。

腳本最後會列出要手動做的步驟。這些 Google 沒有 API：
- 在 console 開 Google 登入，並把 Web client ID 填到 config 的 `GOOGLE_SERVER_CLIENT_ID`。
- 產生 Web Push 金鑰，填到 `FCM_VAPID_KEY`。
- 設定 Functions 用的 secret：`GEMINI_API_KEY`、OAuth client、`CALENDAR_TOKEN_KEY`。

## 建置

```sh
cd app
flutter build web --dart-define-from-file=config/dev.json
flutter build apk --dart-define-from-file=config/dev.json
```

`config/*.json` 裡放的是專案識別資訊，不是密碼，但也不放進 git。

## 部署

```sh
cd functions && npm run build && cd ..
npx --prefix functions firebase deploy --project martha-app-dev
```

Hosting 部署前，會把 landing page 和法律文件複製進 Web build：
- `/about`
- `/privacy`
- `/terms`

## 平台營運者

```sh
cd functions && npx tsx scripts/grant-operator.ts --project martha-app-dev <email>
```

設定後要重新登入才會生效。之後「我的」頁會出現「平台後台」。

## App Links / Universal Links（邀請連結直接開 App）

- **Android**：Web build 要提供 `/.well-known/assetlinks.json`，內容包含簽章憑證的 SHA-256。
  - 取得 SHA-256：`keytool -list -v -keystore <keystore>`。
  - debug 和 release 的金鑰不同，兩個都要列進去。
- **iOS**：要付費開發者帳號，才能開 Associated Domains。
  - 在 `Runner.entitlements` 加上 `applinks:<網域>`。
  - 網站提供 `/.well-known/apple-app-site-association`。
  - 這部分在 M7 處理。

## 照片辨識匯入（self-host → 代管）

見 `functions/scripts/import-selfhost.ts` 開頭的說明。順序：
1. 先 `--dry-run`，只看筆數。
2. 匯入 dev，對照筆數和內容。
3. 匯入 prod。
4. 執行 `.local/auth-import.sh` 搬帳號。執行完刪掉這個檔案，裡面有密碼雜湊金鑰。
