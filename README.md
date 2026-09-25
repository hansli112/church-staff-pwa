# 教會同工助手 · Church Staff PWA

以 Flutter Web 製作的繁體中文教會同工工具，提供服事表、帳號及權限管理，可選接 Google Calendar、照片匯入與通知。各教會自行持有並管理自己的 **Firebase 專案與 Cloudflare Pages 專案**，不共用上游的帳號、資料庫、日曆或憑證。

原始程式碼採 [MIT License](LICENSE)，著作權人為 Hans Lee。這是可自行部署的開源專案，**不是代管服務；不承諾客服、維運、回應時間或第三方免費額度**。

## 第一版範圍

- 服事表：設定每週固定聚會的星期、顯示名稱及穩定 ID，分配同工、編輯服事項目、換班與特殊活動標記。
- **沒有單週新增聚會、改期、停辦或任意日期的例外排程**；特殊活動標籤不會改變週期。
- 帳號：Firebase Auth Email/Password 登入，Firestore `users/{uid}` 儲存角色、牧區與編輯群組。
- 一個部署使用一個 IANA 時區，例如 `Asia/Taipei`；不要把 UTC offset 當時區，也不要只因標籤改名就改資料 ID。
- 行事曆選用 **Google Calendar**；沒有內建 Firestore 行事曆，也沒有設定日曆時的假資料替代品。未啟用或缺讀取設定時隱藏入口。
- PWA：可加入主畫面，提供靜態資源快取及版本更新；**不代表所有功能可離線使用**，行事曆寫入等操作需要網路。
- 照片辨識、推播、LINE webhook 及每日靈糧都是選用功能，範例設定預設關閉。

## 非工程背景：用安裝精靈

[![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.svg)](https://shell.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https%3A%2F%2Fgithub.com%2Fhansli112%2Fchurch-staff-pwa&cloudshell_git_branch=main&cloudshell_tutorial=docs%2Finstall-cloud-shell.md&show=terminal)

在自己的 Google Cloud Shell 開啟私人安裝精靈：連接 Google 與 Cloudflare 帳號、填寫教會資料，確認後自動建立**全新的**核心功能網站（登入、同工管理、服事表）。不需安裝開發工具或 GitHub 帳號，不會自動綁定付費方案，也不接管既有網站。步驟說明見 **[安裝教學](docs/install-cloud-shell.md)**。按下按鈕後 Cloud Shell 會先跳出 Google 官方的「授權 Cloud Shell」視窗，請按「授權」。第一版的真實雲端流程仍在驗證中。

想先看介面、不連任何雲端：`node scripts/install-core.mjs --demo`，再開啟終端機顯示的連結。

## 第一次部署（工程師路線）

完整順序、首位管理員及舊站切換注意事項見 **[部署指南](docs/deployment.md)**。既有網站升級、選用整合與自訂網域請走這條路線。

1. Fork 原始碼；安裝 Flutter（CI 使用 `3.41.0`、Dart 需求見 `pubspec.yaml`）、Node.js 22+、Firebase CLI、Google Cloud CLI 與 Wrangler。
2. 建立自己的 Firebase 專案，啟用 Email/Password 與 Firestore `(default)` 資料庫；建立自己的 Cloudflare Pages 專案。
3. 複製 `config/church.example.json` 到 **gitignored** 的 `.local/church.json`，填自己的公開顯示設定；build 用的 Firebase Web 設定與伺服器 secrets 分開存放。
4. 用 `scripts/prepare-deployment.mjs` 從同一份設定產生 Flutter defines、Worker 設定與 Firestore rules。**先審查並明確部署產生的 rules，再部署對應的前後端**，不可只部署 repo 的預設 rules。
5. 在 Firebase Console 建立首位管理員的 Auth 帳號，核對 UID 後，以 `scripts/bootstrap-admin.mjs` 建立一次性、create-only 的 admin profile。它預設完全離線 dry-run，不會把任意登入者自動升成管理員。
6. 依部署指南設定 GitHub Actions。`main`／`dev` push 會觸發部署；必須提供自己的完整設定與憑證，缺少時 fail-fast。repo 不包含任何教會的可用生產憑證。

不要直接在新的分支執行舊部署工具去連既有站台；不要把真實姓名、同工名單、日曆 ID、照片、金鑰或私有設定提交到公開 repo。新增忽略規則不會移除已進入 Git 歷史的內容；曾外洩的真正 secrets 仍須撤銷／輪替。

## 共用設定

`config/church.example.json` 是可公開的中性範例。私有部署檔僅在 build 時輸入，生成檔留在 `build/` 或 `.local/`，不覆寫 tracked source。

| 欄位 | 意義 |
|---|---|
| `appName` / `shortName` | Flutter、網頁 title/meta/載入畫面與 PWA manifest 的名稱 |
| `timeZone` | 單一 IANA 時區，前後端使用同一值 |
| `services[].id` | Firestore 及 API 使用的 stable ID；**建立資料後不可直接改名或刪除** |
| `services[].label` / `name` / `weekday` | 短名、完整顯示名、星期（1=週一，7=週日） |
| `services[].enabled` | 停用聚會時改為 `false`，保留 ID 與歷史資料的可辨識性；不做資料刪除／遷移 |
| `features` | `calendar`、`photoImport`、`pushNotifications`、`lineNotifications` 的啟用開關 |
| `devotional` | `enabled`、`dataUrl`、`linkUrl`、`sourceName`，選填 `fetchUrl`／`fetchFormat`；不綁定特定教會網站 |
| `icons` | favicon、192/512 px 與 maskable PNG 圖示路徑；客製素材需自行確認權利 |

設定內容會送到瀏覽器，**不是秘密保管箱**。`CHURCH_CONFIG_JSON` 不放 API 私鑰、service account JSON、Webhook secret 或人員名單。更改設定後重新產生、測試及部署；不是在瀏覽器裡即時改設定。

## 選用整合

### Google Calendar

讀取使用 `GOOGLE_CALENDAR_ID` 與限制用途的 `GOOGLE_CALENDAR_API_KEY`，適用可公開讀取的日曆。**公開日曆的內容不因 App 有登入而變成私密資料**；需要私密行事曆者必須另做後端讀取／OAuth，第一版未提供。

新增／編輯／刪除經同源 Cloudflare Pages Functions 寫入同一本日曆，以 Firebase ID token 和 `users/{uid}` 驗證權限。寫入用 `GOOGLE_SERVICE_ACCOUNT_JSON` **只放 Cloudflare Secret**，並將日曆分享給該 service account（變更活動權限）。這個寫入 service account 不需要用來繞過 Firestore rules。

### 照片匯入與通知

- 照片匯入：先完成[首次初始化](docs/deployment.md#照片匯入首次初始化)：建立各聚會的服事項目與事件選項文件，以同一份教會設定產生、檢查並明確發佈 `settings/import_prompts`；只設 key 不會建立模板。再啟用 `photoImport`，在 Cloudflare Secret 設 `GEMINI_API_KEY`，重新產生並部署設定。`--publish` 是實際 Firestore 寫入，需先確認專案、權限及內容，不是離線預覽。辨識結果必須由人校對再匯入，尤其是人員順序與日期。照片及所需名單會交給第三方模型處理，部署者須先取得合適的授權／同意並確認供應商條款、資料政策及額度。不要把 key 傳入 `--dart-define`。
- 推播：啟用 `pushNotifications` 並設定 `FCM_WEB_VAPID_KEY`。瀏覽器支援及使用者授權仍是必要條件；這是接收端整合，不包含完整的自動發送／排班提醒服務。
- LINE：啟用 `lineNotifications`，另接自己的 n8n 或相容 HTTPS webhook，設定 `NOTIFY_WEBHOOK_URL` 與 `NOTIFY_WEBHOOK_SECRET`。沒有預設 LINE 群組或托管 workflow。通知接收端須驗證 `x-notify-secret`，自行管理 LINE token、群組與個資。新增日曆活動後才通知，通知失敗不回滾已建立的活動。
- Production 與 Preview 的 Cloudflare secrets **分開設定**；建議 Preview 使用獨立測試日曆與通知目標，不要預設都發到正式群組。

### 每日靈糧

可直接讀部署者有權使用、允許瀏覽器跨來源讀取的 JSON feed；`linkUrl` 是使用者點擊後前往的網站，`sourceName` 是顯示的來源名稱。既有格式如下（日期依部署時區）：

```json
{
  "date": "2026-09-24",
  "rawRange": "約翰福音 1:1-5",
  "fetchedAt": "2026-09-24T00:00:00Z"
}
```

範例僅示意格式，不是即時資料。來源沒有當天日期時不會把舊範圍當成今天。

`.github/workflows/fetch-daily-verse.yml` 是**選用的來源適配流程，不是任意 HTML 爬蟲**：

- 與部署共用 GitHub Secret／Variable `CHURCH_CONFIG_JSON`；只在 `devotional.enabled=true` 且 `devotional.fetchUrl` 非空時抓取。沒有設定便不抓，沒有任何預設站點。
- 日期判斷直接使用同份設定的 `timeZone`，不再另設一組 feed／時區變數；排程仍是 UTC（預設每日 17:00），不會依設定自動改 cron。
- `fetchFormat:'json'`（預設）接受上面的既有 JSON 格式；`fetchFormat:'dailyBibleHtml'` 保留舊的固定 HTML adapter，只接受「日期、`<span>|</span>`、經文範圍 `<span>`」結構。不同網站或來源版型改變時，須另寫適配器與測試，不會猜測任意 HTML。
- `fetchUrl` 必須是直接回應所選格式的 HTTPS URL（不跟隨 redirect）；檢查格式與日期後只將必要欄位寫入 `data` 分支的 `daily-verse.json`，分支不存在會建立。允許 repository 的 Actions 寫入權限後才可更新資料分支。
- `dataUrl` 是 **App 讀取 JSON 的位置**，不是抓取來源；`linkUrl` 是點擊後的網站。`dataUrl` 不能指向 GitHub HTML 檔案預覽頁。若已有可靠 JSON feed，也可直接讀取並把 `fetchUrl` 留空。
- **不跳過 TLS 憑證驗證**。既有來源若憑證鏈不完整，應修正來源憑證、提供正確且受信任的 CA，或改用其他合法來源，不可恢復 `--insecure`。公開 repo 的 data 分支也是公開資料，複製前須自行確認再散布權利；網頁可讀不等於可任意使用。

## 權限與資料安全

`role` 表示身分；`admin` 有全部權限，其他人的編輯權限由 `groups` 控制，服事表另受 `zones`／`zoneTypes` 限制。stable service IDs、`roster-editors`、`calendar-editors` 都是資料格式的一部分。

| 動作 | admin | roster-editors | calendar-editors |
|---|---|---|---|
| 編輯服事表 | 全部啟用聚會 | 自己的牧區 | 不授予 |
| 修改 Google Calendar | 可（已啟用／已設定） | 不授予 | 可（已啟用／已設定） |
| 讀取使用者完整名單 | 可 | 可 | 不授予 |
| 帳號、角色、群組與範本管理 | 可 | 不可 | 不可 |

Firestore rules 才是資料庫防線，隱藏按鈕不是授權。`zoneTypes` 是 `zones` 的投影；直接在 Console 寫資料時也須保持一致。刪除 `users/{uid}` 撤銷 App 資料存取，不等於刪除 Firebase Auth 帳號。

**隱私提醒**：Firestore 沒有欄位級讀取遮罩；可讀使用者名單的服事表編輯者也能讀那些文件中的 email、推播 token 等欄位。授權前請理解此範圍，收集資料以必要為限。部署者負責備份、刪除、存取檢查、帳號停用與事故處理。

Firebase Web API key、Google Calendar 前端 API key、FCM VAPID **公鑰**最終都可從瀏覽器取得，即使 build 時從 GitHub Secrets 注入也不會變成秘密。應設定 Firebase authorized domains、正確 rules、Google API 用途及 HTTP referrer 限制；公鑰不能代替資料授權。真正的伺服器 secrets 不得出現在前端 bundle。

## 開發與驗證

```bash
flutter pub get
flutter analyze
flutter test
dart format lib test

# 無 npm 相依套件、無網路呼叫
node --test scripts/*.test.mjs
npm test --prefix functions-tests
npm test --prefix web-tests

# Python publisher 離線測試（需 uv；已有 .venv 時略過 venv）
uv venv .venv
uv run --no-project --python .venv/bin/python scripts/build_import_prompt_test.py

# Firestore + Auth Emulator（首次需下載依賴與 emulator；需相容 Java）
# 含規則測試，以及安裝精靈建立首位管理員的整合測試
npm ci --prefix firestore-tests
npm test --prefix firestore-tests

# 安裝精靈的真瀏覽器 smoke（離線示範，需本機 Chrome；CHROME 可指定執行檔）
node scripts/installer-browser-smoke.mjs
```

帶設定的本機執行及 release build 見[部署指南](docs/deployment.md)。**Docker/nginx 只是受限的靜態前端路線**：需提供 `CHURCH_CONFIG_JSON` build-arg，但不執行 Cloudflare Pages Functions；`calendar`、`photoImport`、`lineNotifications` 必須關閉（否則 build 拒絕），不可當作完整功能的一鍵部署。

原始碼主要位置：

- `lib/features/<feature>/{domain,data,presentation}/`：各功能的 model、repository、UI。
- `lib/core/`：共用設定、型別與 UI 工具。
- `functions/`、`worker/`：Cloudflare API 與共用授權／第三方整合。
- `firestore.rules`、`firestore-tests/`：資料授權模板與 emulator 測試。
- `web/`、`web-tests/`：PWA 資源與快取測試。
- `scripts/`：設定產生、首位管理員 bootstrap 與離線測試。
- `scripts/installer/`：Cloud Shell 安裝精靈（核心、各雲端 adapter、私人網頁）。

協作規範見 [AGENTS.md](AGENTS.md)。歡迎 Issue／PR，但請先移除個資與憑證，不要把正式資料當測試 fixture。

## 授權與素材

MIT 適用於本專案原創程式碼與新製中性 PWA 圖示，**不會把 Flutter、套件、字型、聖經譯本、靈修內容或外部標誌全部重新授權為 MIT**。發佈時保留第三方 notices；App「我的 → 開源授權」使用 Flutter 內建的授權顯示機制。

已核對的本機套件／素材範圍與未查實項目見 [第三方授權與素材](docs/third-party-notices.md)。這不是完整的法務稽核或侵權保證。部署者自行加入的教會名稱、圖示、照片、文章與資料須另有適當權利。
