# 自行部署指南

這條路線使用各教會自己的 **Firebase Auth／Firestore + Cloudflare Pages／Pages Functions**。本文的 `example.invalid`、`your-project-id`、`AUTH_UID_FROM_CONSOLE` 都是佔位值，不是可用的上游服務。以下會連線或寫資料的步驟需由有權管理該專案的人確認後執行。

## 0. 前置條件

- Git、Flutter `3.41.0`（Dart SDK 要求見 `pubspec.yaml`）、Node.js 22+。
- Firebase CLI、Google Cloud CLI、Wrangler。CI 的工具／版本以 `.github/workflows/deploy-flutter-pwa.yml` 為準。
- 自己持有的 Google/Firebase 與 Cloudflare 帳號，管理者有權設定 Authentication、Firestore、Pages、網域與 secrets。
- 開啟第三方服務前先確認計費／配額與隱私條款。本專案不保證永久免費，不提供代管或客服承諾。

`.env.example` 是設定對照表，**不會自動載入**。server secrets 不得傳給 Flutter；`--dart-define` 與 `--dart-define-from-file` 的所有內容最終都可能在瀏覽器被讀取。

## 1. 建立自己的後端

1. 在 Firebase Console 建立專案，新增 Web app，保存它的 Firebase Web config。
2. Authentication → Sign-in method 啟用 **Email/Password**；設定自己的正式／預覽網域為 authorized domains。本機開發若使用 `localhost`，也確認已允許。
3. 建立 Firestore **`(default)`** 資料庫，選擇合適區域並以限制存取的模式開始。App 尚未部署完整 rules 與 user profile 前，登入後被拒絕是預期行為；不要先把規則改成公開讀寫。
4. 在 Cloudflare 建立自己的 Pages 專案。若依本文以 GitHub Actions/Wrangler 部署，避免再開另一條重複的自動 build 部署流程。
5. Production 與 Preview 的資料／憑證分流由部署者決定。至少日曆、通知測試目標應與正式環境隔離；需要完全隔離時使用不同 Firebase 專案與對應設定。

## 2. 建立私有設定

```bash
mkdir -p .local
cp config/church.example.json .local/church.json
```

編輯 `.local/church.json`：

- `appName`、`shortName` 設顯示名稱；`timeZone` 設單一 IANA 時區。
- 每個 `services` 項目有固定 `id`、`label`、`name`、`weekday`（1–7）及 `enabled`。第一版只有**每週固定星期**，不能靠改資料標籤實現單週例外。
- **service ID 是永久資料鍵**。改顯示名稱只動 `label/name`；停用只動 `enabled:false`，保留項目與 ID，不直接刪除。不要為改名讓既有 `zones`、`zoneTypes`、服事表變成未知 ID。
- 選用功能先維持 `false`；先驗證核心登入／服事表，再逐一啟用。
- 每日靈糧的 `dataUrl` 是 App 讀取 JSON 的網址，`linkUrl` 是點擊後的網站；若需 workflow 更新 data 分支，另設 `fetchUrl` 與 `fetchFormat`（`json` 或固定版型 `dailyBibleHtml`）。`fetchUrl` 留空便不抓取，所有日期判定使用同份設定的 `timeZone`。來源 URL 不得含秘密。
- 日曆 ID、同工姓名、server secrets 不放這個檔案。ChurchConfig 會被編入公開前端及 Worker。

另建立 `.local/firebase-web.json`，只放前端需要的值：

```json
{
  "FIREBASE_API_KEY": "REPLACE_WITH_FIREBASE_WEB_API_KEY",
  "FIREBASE_AUTH_DOMAIN": "your-project-id.firebaseapp.com",
  "FIREBASE_PROJECT_ID": "your-project-id",
  "FIREBASE_STORAGE_BUCKET": "",
  "FIREBASE_MESSAGING_SENDER_ID": "REPLACE_WITH_SENDER_ID",
  "FIREBASE_APP_ID": "REPLACE_WITH_WEB_APP_ID",
  "FIREBASE_MEASUREMENT_ID": "",
  "GOOGLE_CALENDAR_ID": "",
  "GOOGLE_CALENDAR_API_KEY": "",
  "FCM_WEB_VAPID_KEY": ""
}
```

空白選填欄位可依實際 Firebase Web config 補上；其他佔位值必須替換。Firebase API key 是前端識別設定，不是管理者憑證；Firestore rules、Auth 與 key 限制才構成對應安全邊界。

## 3. 同一份設定產生三端產物

```bash
node scripts/prepare-deployment.mjs \
  --config .local/church.json \
  --out .local/deployment
```

這個動作完全本機處理，**不會部署、不會連 Firebase，也不修改正式資料**。輸出包含：

- `.local/deployment/dart-defines.json`：Flutter 的 `CHURCH_CONFIG_JSON`。
- `.local/deployment/worker/generated_config.js` 與 `functions/`：同份設定的 Pages Functions staging。
- `.local/deployment/firestore.rules`、`firebase.json`：依 stable service IDs 產生的規則與部署入口。
- `.local/deployment/church.json`：本次設定副本。
- `.local/deployment/web/`：已套入 appName／shortName／icons 的 `index.html`、`manifest.json`、`firebase-messaging-sw.js` 與需帶入的圖示資產。

檢查輸出的 IDs、啟用功能及目標專案。不要把 private config 寫回 `config/church.example.json`、`worker/generated_config.js` 或 repo 的 `web/`。`build/` 與 `.local/` 已 gitignore；產物可能含教會設定，即使不是金鑰也不要隨便上傳公開附件。

## 4. 先驗證並部署生成的 rules

本機離線／emulator 測試：

```bash
flutter pub get
flutter analyze
flutter test
node --test scripts/*.test.mjs
npm test --prefix functions-tests
npm test --prefix web-tests
npm ci --prefix firestore-tests
npm test --prefix firestore-tests
```

Emulator 的第一次執行可能下載工具，需相容 Java。這些測試不等於已驗證你的真實 Firebase／Cloudflare／Google Calendar 設定。

登入 Firebase CLI 並明確指定**自己的**專案，審查 `.local/deployment/firestore.rules` 後部署：

```bash
firebase login
PROJECT_ID=your-project-id
firebase deploy --only firestore:rules \
  --config .local/deployment/firebase.json \
  --project "$PROJECT_ID"
```

**不要改用根目錄預設 `firestore.rules` 取代生成檔。** 新的 stable IDs 若只改 Flutter／Worker 而沒有先上對應 rules，存檔會被拒絕。更改存取模式時必須同步審查規則；部署流程不會悄悄替你放寬權限。

## 5. 安全建立首位管理員

App 沒有「第一個註冊者自動變 admin」或公開自助升權入口。先在 Firebase Console → Authentication → Users **手動新增屬於首位管理員的 Email/Password 帳號**，核對 email 與 UID，透過適當方式讓該管理員取得密碼。不要把密碼交給腳本或提交到 repo。

先離線預覽（不取得 token、不查 Auth、不查／寫 Firestore）：

```bash
node scripts/bootstrap-admin.mjs \
  --project your-project-id \
  --uid AUTH_UID_FROM_CONSOLE \
  --name '初始管理員' \
  --username admin \
  --config .local/church.json
```

`--uid` 可換為 `--email admin@example.invalid`。`--name` 必填，`--username` 未指定時使用 name；實際登入仍使用 Auth email，不是 username。未給 `--config` 時 zones 為空，admin 仍有管理權限；給了設定時以啟用的 services 同時建立 `zones` 與 `zoneTypes`。

提供 `--config` 時，必須使用與 `prepare-deployment.mjs` 相同的**完整 `church.json`**，會套用相同的 schema、時區、功能、圖示與聚會清單驗證；不接受只有 `services` 的部分設定檔。無效設定會在取得 token 或連線前拒絕，不能靠 bootstrap 繞過部署設定限制。

確認這確實是要授權的本人帳號，而非其他既有帳號後，使用有 `firebaseauth.users.get`／對應 Auth 查詢能力與 Firestore 讀取／建立權限的管理者 ADC。通常可由專案管理者指派 Firebase Authentication Viewer 與 Cloud Datastore User 等必要 IAM 角色；依實際 IAM policy 採最小權限，使用完移除不再需要的權限。

腳本會把明確指定的 project 同時放入 `x-goog-user-project` 作為 ADC REST 的 quota project；操作者也需在該專案有 `serviceusage.services.use` 權限（例如 Service Usage Consumer），不可默默將其他專案作為配額目標。

```bash
gcloud auth application-default login

node scripts/bootstrap-admin.mjs \
  --project your-project-id \
  --uid AUTH_UID_FROM_CONSOLE \
  --name '初始管理員' \
  --username admin \
  --config .local/church.json \
  --apply \
  --confirm-project your-project-id \
  --confirm-uid AUTH_UID_FROM_CONSOLE
```

這是實際寫入命令，**不要在不確定目標時執行**。腳本會顯示目標、在指定 project 查既有 Auth user、拒絕停用／UID 不符的帳號，並只建立 `users/{uid}`：

- `id`、`name`、`email`、`username`、`role:'admin'`、`zones`、`zoneTypes`、`groups` 與 App 的 User 格式一致。
- Auth 帳號不存在就失敗，**不建立、不刪除、不重設任何 Auth 帳號／密碼**。
- profile 已存在就拒絕，不升權、不覆寫；寫入同時有 `currentDocument.exists=false`，即使查詢後別人先建立文件也不會覆寫。
- email lookup 也必須提供 Console 中核對過的 `--confirm-uid`，避免只憑姓名或 email 誤授權。
- IAM/ADC 是管理者權限，能繞過一般 Firestore rules；只在受信任環境使用，不要把此流程搬成公開 API。
- 可改用短期 `GOOGLE_OAUTH_ACCESS_TOKEN`，但不要把 token 寫進命令紀錄／log／tracked 檔案。default dry-run 完全不需要憑證。

腳本的離線測試驗證 dry-run、身分核對、拒絕覆寫、併發 create precondition 與 API 失敗路徑。它沒有替你驗證 live IAM／專案設定；apply 後仍須登入 App 確認。

## 6. 建置與 Pages staging

前端本機開發：

```bash
flutter run -d chrome \
  --dart-define-from-file=.local/deployment/dart-defines.json \
  --dart-define-from-file=.local/firebase-web.json
```

`flutter run` 不會啟動 Cloudflare Pages Functions。核心 Firebase 功能可用，但照片／日曆寫入等 `/api/` 需要對應的 Pages Functions 環境，不能只因前端跑起來就視為完整部署驗證。

Release build：

```bash
flutter build web --release --base-href / --no-web-resources-cdn \
  --dart-define-from-file=.local/deployment/dart-defines.json \
  --dart-define-from-file=.local/firebase-web.json
```

接著套入產生的網頁 metadata，並只用 staging 的 Functions／Worker 來打包：

```bash
cp -R .local/deployment/web/. build/web/
npx --yes wrangler@4 pages functions build .local/deployment/functions \
  --outdir=build/web/_worker.js
```

`--outdir` 會產生 Pages advanced worker 的 `_worker.js/index.js` 目錄；不要改成 `--outfile`，Wrangler 4 的該選項會產生 multipart upload bundle，不是可直接部署的 JavaScript。

這裡的 HTML 已將 base href 固定為 `/`，因此本指南限部署在網域根路徑。正式上傳前還需要與 workflow 相同的版本快取及 FCM 設定注入；不要將未完成注入的 `build/web` 當作完整部署產物。下一節 CI 路線會執行這些步驟，不會把 `.local/deployment` 整個公開成網站。

### 自訂圖示

預設從 repo 的 `web/` 取中性圖示。客製 PNG 請先確認素材權利，將檔案留在 gitignored 的 `.local/branding/`，**不用覆寫 tracked `web/`**。`icons` 的路徑同時代表資產目錄內的相對路徑與最終網站路徑。例如沿用範例路徑時：

```text
.local/branding/
├── favicon.png
└── icons/
    ├── Icon-192.png
    ├── Icon-512.png
    ├── Icon-maskable-192.png
    └── Icon-maskable-512.png
```

準備好圖示後，用以下命令取代第 3 節的 prepare 命令：

```bash
node scripts/prepare-deployment.mjs \
  --config .local/church.json \
  --assets .local/branding \
  --out .local/deployment
```

產生器只複製 `icons` 指定的 PNG 至 `.local/deployment/web/<相對路徑>`，檢查檔案存在且不允許 realpath／symlink 逃出資產目錄。之後仍按照前述 `cp -R .local/deployment/web/. build/web/` 帶入，名稱、manifest、背景通知圖示和實際 PNG 必須來自同一份設定。`--assets` 未指定時就是 `web/`，不會默默下載任何外部圖片。

CI 預設不會取得你的私有檔案；若用了客製素材，必須在 CI prepare 之前透過自己的私有資產來源準備同一套檔案，並設定 GitHub Variable `CHURCH_ASSETS_DIR` 為該 runner 目錄（預設 `web`，workflow 會傳給 `--assets`）。缺檔就應讓建置失敗，不回退成其他教會圖示。本文不提供私有素材儲存服務。檢查 192/512 尺寸、maskable 安全區及 favicon 後再上線。

Docker 的資產來源目前固定為 build context 中的 `web/`，且 `.local/` 已被 `.dockerignore` 排除；`CHURCH_ASSETS_DIR` 不是 Docker 的私有 context 功能。若使用受限 Docker 路線且需要客製圖示，可自行將有權使用的 PNG 放入 gitignored `web/private-icons/`，再把 `icons` 改為該相對路徑；不要提交這些教會素材。

## 7. GitHub Actions 與 Cloudflare

`.github/workflows/deploy-flutter-pwa.yml` 是標準 release 路線：`main`／`dev` push 或手動觸發會執行；**沒有 `DEPLOY_ENABLED` 這類額外開關**。Fork 後先確認 Actions 是否允許執行，完成自己的設定再觸發。`main` 對應正式、`dev` 對應預覽；缺少必要設定時 fail-fast，不拿中性設定蓋既有站台。

GitHub Settings → Secrets and variables → Actions：

- Variable `CLOUDFLARE_PAGES_PROJECT`；Secrets `CLOUDFLARE_ACCOUNT_ID`、`CLOUDFLARE_API_TOKEN`（最小所需 Pages 權限）。名稱及 Secret／Variable 位置需與 workflow 一致。
- Secret 或 Variable `CHURCH_CONFIG_JSON`：自己的 `.local/church.json` 全文；secret 優先。雖不是 server secret，仍不要把真實部署檔提交到公開 source。
- 選填 Variable `CHURCH_ASSETS_DIR`：runner 上已準備好的 PNG 目錄，預設 `web`。
- Firebase Web 欄位；選用功能啟用才加 Calendar API key／calendar ID／FCM VAPID 公鑰。
- Production／Preview 的執行期設定須**另外**放 Cloudflare，不是只填 build 用 GitHub 變數。

Cloudflare runtime 最小必需 `FIREBASE_PROJECT_ID`。選用整合再補：

| 功能 | Cloudflare runtime 設定 |
|---|---|
| Google Calendar 寫入 | `GOOGLE_CALENDAR_ID`、Secret `GOOGLE_SERVICE_ACCOUNT_JSON` |
| 照片辨識 | Secret `GEMINI_API_KEY`，選填 `GEMINI_MODEL` |
| LINE/n8n webhook | `NOTIFY_WEBHOOK_URL`、Secret `NOTIFY_WEBHOOK_SECRET` |

一般不要設定 runtime `CHURCH_CONFIG_JSON` binding；Worker 使用 staging 內的產生設定。如果設定了 binding，**任何值與 staging 不一致都會拒絕**，不只是 service IDs，以免名稱、時區或功能開關與 Flutter／rules 漂移。修改 secrets 後依 Cloudflare 的設定生效方式重新部署，並分別驗證 Production／Preview。

`scripts/push-calendar-secrets.sh` 只設定 Production，且必須指定自己的 `CLOUDFLARE_PAGES_PROJECT`。Wrangler Pages secret put 沒有可用的 `--env preview`；Preview 請用 Cloudflare Dashboard 或正式 REST API 另行設定，不要誤以為跑一次腳本就兩邊都有。

行事曆寫入還需要 Google Calendar API 已啟用，並把目標日曆分享給 service account（變更活動）。那把 service account key 僅給日曆寫入使用，不能放進 `.local/firebase-web.json`。公用日曆的讀取 key 應限制 HTTP referrers 與 Calendar API 用途。

選用的 `scripts/verify-calendar-writer.mjs` 是 **live 檢查，不是離線測試**：會使用真實 service account 在目標日曆建立一筆遠期活動、讀回、再刪除；清理失敗需人工刪除。只有在有權且已確認測試目標時才執行。它現在讀取 prepare 產生的 Worker，因此必須先 prepare；預設輸出目錄是 `.local/deployment`，另有 `CHURCH_DEPLOYMENT_DIR` 可指定目錄，`CHURCH_CONFIG_FILE` 則指定同一份設定。不要在文件驗證或 CI 離線測試中自動執行它。

### 照片匯入首次初始化

**只有 `photoImport=true` 與 `GEMINI_API_KEY` 還不能辨識。** 新資料庫或新加入的聚會沒有 `settings/import_prompts` 對應欄位時，API 會回覆「辨識設定還沒建立」。先保持照片功能關閉，在確認過的測試專案完成以下流程，再依自己的變更程序套用正式環境。

1. 管理員登入 App，在服事表編輯模式的「服事項目設定」為每個要辨識的聚會新增項目並儲存，建立 `settings/roster_templates`。也開啟「事件選項設定」並儲存：沒有特殊活動可以留空，但產生腳本需要 `settings/event_options` 文件存在。確認 `users` 至少已有具姓名的管理員／同工 profile；完全沒有姓名時腳本會中止。
2. 視表格版面準備 gitignored `.local/import-rules.json`，每個頂層鍵必須是 `church.json` 的 `services[].id`。`layoutRules`、`extraRoleRules`、`nicknames`、`teamRules` 的格式及範例見[模板文件](roster-import-prompt.template.md#各崇拜的差異怎麼設定)。沒有特殊規則可以省略檔案；缺 `layoutRules` 會警告，表示尚未指定版面，不代表任意表格都能正確辨識。不要把真實綽號、名單或預覽產物提交到 repo。
3. 確認本機安裝 `uv`、Python 3.10+、Node.js 與 Google Cloud CLI。腳本會先用目前 `gcloud` 使用者取得 access token，失敗才退回 ADC；必須核對實際登入帳號及目標專案。該帳號需要讀取目標 Firestore 的 `users`／`settings`，發佈時另需建立／更新 `settings/import_prompts` 的 IAM 權限（由專案管理者依最小權限授予，例如適用的 Cloud Datastore User）。**App 的 admin 身分不等於 gcloud 的 IAM 權限；這條管理腳本路徑也不受 App 的 Firestore rules 限制。** 不需把 Google Calendar service account key 交給此腳本。

下列初始化環境以 repo 根目錄執行；替換 project 與 service ID，`CHURCH_CONFIG_FILE` 必須指向 prepare-deployment 使用的**同一份**設定：

```bash
# 已有 .venv 時略過這行；Python 腳本只用標準函式庫
uv venv .venv
export CHURCH_CONFIG_FILE="$PWD/.local/church.json"
export FIREBASE_PROJECT_ID=your-project-id
SERVICE_ID=sundayService # 替換成自己設定中要辨識的 stable ID
```

**以下生成命令會讀取真實 Firestore 及取得 token，不是離線 dry-run**，但不寫入遠端，也不呼叫 Gemini。由有權操作者確認讀取對象後才執行：

```bash
uv run --no-project --python .venv/bin/python \
  scripts/build-import-prompt.py "$SERVICE_ID"
```

檢查 `.local/roster-import-prompt.<SERVICE_ID>.md` 的日期、項目、版面與姓名；它含同工資料，只供私下檢查。腳本同時檢查模板欄位是否和 Worker 相符。若輸出「沒有服事項目，跳過」就還沒有生成該聚會模板，先回 App 完成設定。省略 service ID 會處理設定中的所有聚會；不會自動排除停用的聚會，因此首次設定建議逐一指定。

**只有內容、專案、帳號權限與正式寫入都已獲確認後，才執行 `--publish`：它會重新讀取資料，實際建立／更新 `settings/import_prompts`，不是預覽，也沒有互動確認提示。不要放進一般離線測試或自動執行。** 已有模板時先備份，單次只更新這次指定的 service ID 欄位，其他聚會模板保留；發佈的是保留 `{{ROLES}}` 等即時欄位的模板，不是把本機的完整姓名預覽原封不動上傳。

```bash
uv run --no-project --python .venv/bin/python \
  scripts/build-import-prompt.py "$SERVICE_ID" --publish
```

每個要辨識的聚會都完成後，設定 Cloudflare runtime Secret `GEMINI_API_KEY`，將同份 `church.json` 的 `features.photoImport` 設為 `true`，重新 prepare、建置及部署對應前後端。在已授權的測試資料上操作「匯入服事表 → 從照片辨識」，校對回傳 JSON 再決定是否匯入；這會傳送照片／名單給 Gemini 並使用配額，不屬於離線驗證。新增聚會、修改私有規則或模板本文要重新發佈該聚會模板；只改既有聚會的同工、項目或事件名單時，Worker 會即時讀取，不必重發。照片功能關閉時仍可手動貼 JSON。

Publisher 的安全離線回歸可用 `uv run --no-project --python .venv/bin/python scripts/build_import_prompt_test.py`；一般只 mock HTTP，不讀私有設定或憑證。若另設 `FIRESTORE_EMULATOR_HOST`，只接受 loopback host，額外在固定 `demo-prompt-mask` 專案測試含連字號 ID 的部分更新；務必使用專門的本機 emulator，不要指向共享測試資料。這些測試不證明真實 IAM 或 Gemini 辨識品質。

## 8. 上線檢查

- 未登入／僅有 Auth 帳號但無 user profile 者不能讀取受保護資料；非 admin 不能修改角色／groups。
- 管理員登入後可管理使用者及正確的聚會種類；服事表編輯者只能修改被授權牧區。
- 跨日、跨月與瀏覽器時區不同時，使用的日期仍符合教會時區；DST 區域另測夏令時間邊界。
- 未啟用的行事曆、照片、通知及靈糧入口不造成 API 呼叫或錯誤。
- 啟用的整合用測試帳號／測試日曆逐一驗證，確認 Preview 不會發到正式通知目標。
- title、載入畫面、manifest、加入主畫面圖示與登入後名稱一致。保留 Flutter 第三方 notices 及授權入口。
- 開啟過舊 PWA 的裝置也能更新；`cache_sw.js` 中沒有 `__BUILD_VERSION__`／`__VENDOR_VERSION__` 未替換值。啟用推播時，messaging SW 沒有 Firebase placeholders。
- 在公開 diff／artifact 檢查中沒有同工姓名、真實日曆 ID、key、service account JSON、Webhook secret 或私有設定。
- 建立自己的 Firestore 備份、帳號停用及憑證輪替流程。不要用重設規則為公開讀寫來解決權限錯誤。

## 既有部署升級：先設定、再切換

**不要把中性範例直接推到既有正式站。** 升級前先從既有部署設定重建自己的私有 `church.json`，核對原 appName、service IDs、時區、功能開關、靈糧／日曆／圖示設定與 server secrets；本 repo 不會自動讀上游環境來幫你猜。

1. 備份既有 Firestore，保留目前可回復的部署版本及 rules。
2. 核對 Firestore 裡實際使用的 stable service IDs、`zones`、`zoneTypes` 與新設定一致；不能以改 config 的方式偷偷遷移正式資料。
3. 若有舊資料缺 `zoneTypes`，先在隔離環境規劃與驗證遷移，再另行授權執行；不要直接複製舊 README 的 backfill 命令去動正式資料。
4. 先在獨立 preview／測試專案用相同生成流程驗證。審查新的 rules 是否與仍在使用的舊 App 相容。
5. 經確認後依序部署**生成 rules → 對應 Worker／Flutter／web staging**。需要無中斷過渡時先做相容規則或維護窗口，不可先上不相容規則造成既有使用者全面鎖住。
6. 首位管理員腳本只給新 profile 用；既有使用者若需權限調整，由已有管理員處理，不使用 bootstrap 強制覆寫。
7. 確認實際裝置更新成功後再停用舊站；停用 service 仍保留原 ID。設定產生器本身不做 Firestore 資料遷移、刪除或自動修正。
8. 第一次升級先保留原星期與時區，確認所有管理員裝置更新後才調整排程設定。新版會在 transaction 內讀取同週七個日期，避免不同星期設定的新版客戶端同時重複補表；舊的固定三聚會版本沒有這個防護，不能混用它來變更排程。既有排表不會因改設定而搬動。

## 部署界線

- Docker／nginx 只提供受限的靜態前端。它也需要 `CHURCH_CONFIG_JSON` build-arg（compose 讀同名環境變數），但**不執行 Pages Functions**；`calendar`、`photoImport`、`lineNotifications` 必須關閉，否則 build 拒絕。使用這些整合請走 Cloudflare，不把 Docker 說成完整功能的一鍵部署。
- 本次 repo 內的離線測試、emulator 測試與 web build 只能證明對應程式層面的結果，不能取代你的真實 IAM、DNS、日曆 ACL、FCM／LINE 收件或供應商配額測試。
- [第三方授權與素材](third-party-notices.md) 記錄目前已知範圍及未查實項；部署者自行加入的素材、同工資料與外部內容仍須有適當權利。
