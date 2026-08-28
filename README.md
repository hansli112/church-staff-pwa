# 教會同工助手 (Church Staff PWA)

這是一個基於 **Flutter Web** 開發的全方位 **漸進式網路應用程式 (PWA)**，旨在為教會同工與志工提供集中的管理平台。專案採用 **Feature-First (功能優先)** 架構搭配 **Clean Architecture**，方便未來輕鬆擴展模組。

## 核心功能

- **集中式儀表板**：快速存取核心工具與關鍵資訊
- **服事表管理**：管理服事行程與志工安排，換班可在編輯模式直接交換（兩天一次寫入，不會半途卡住）
- **模組化設計**：可輕鬆添加新功能（如請假申請、場地預約、公告系統）
- **PWA 優化**：針對行動裝置進行優化，提供類原生 App 體驗
- **推播通知**：Firebase Cloud Messaging 整合
- **在地化支持**：完整支援繁體中文 (`zh_TW`)

## 技術棧

| 層級 | 技術 |
|------|------|
| **框架** | Flutter (Web Channel) |
| **語言** | Dart |
| **狀態管理** | Provider |
| **後端服務** | Firebase (Auth, Firestore, Messaging) |
| **導覽** | Material Navigation Bar |
| **在地化** | intl package (`zh_TW`) |
| **UI 設計** | Material Design 3 |

## 架構設計

專案採用 **Feature-First** 模式，結合 **Clean Architecture** 原則：

```
lib/
├── core/                          # 共享資源
│   ├── config/                    # 環境設定（Firebase、Google Calendar key）
│   ├── services/                  # 跨 feature 服務（推播、外部連結、版本資訊）
│   ├── types/                     # 共用型別定義（service_type.dart）
│   └── widgets/                   # 共用 UI 組件
├── features/                      # 獨立功能模組
│   ├── auth/                      # 登入、使用者管理
│   │   ├── domain/                # Entity & Repository Interface
│   │   ├── data/                  # Firebase 實作
│   │   └── presentation/          # 登入頁、使用者管理
│   │       └── providers/         # SessionProvider（登入狀態）、UserAdminProvider（使用者 CRUD）
│   ├── calendar/                  # 教會行事曆
│   │   └── presentation/
│   │       ├── screens/           # calendar_screen.dart
│   │       └── widgets/           # _calendar_models.dart、_day_cell.dart、_day_events_sheet.dart、_event_detail_sheet.dart、_event_segment_bar.dart
│   ├── dashboard/                 # 儀表板（目前僅 presentation 層）
│   │   └── presentation/
│   └── roster/                    # 服事表管理
│       ├── domain/
│       ├── data/
│       └── presentation/
│           └── widgets/           # roster_card.dart、roster_view_card.dart、_roster_people_dialog.dart、_special_event_dialog.dart
├── presentation/                  # 應用層 UI 編排
│   └── screens/main_scaffold.dart # 主 Shell (Bottom Navigation Bar)
├── firebase_options.dart          # Firebase 平台設定
└── main.dart                      # 進入點與 Provider 樹組裝
```

## 快速入門

### 前置準備

- 已安裝 [Flutter SDK](https://flutter.dev/docs/get-started/install)（版本 ≥ 3.10.7）
- 已安裝 [Git](https://git-scm.com/)
- 網頁瀏覽器（建議使用 Chrome）

### 本地開發設定

1. **安裝依賴**
   ```bash
   flutter pub get
   ```

2. **在 Chrome 中以開發模式執行**
   ```bash
   flutter run -d chrome
   ```

3. **執行靜態分析**
   ```bash
   flutter analyze
   ```

4. **執行測試**
   ```bash
   flutter test
   ```

## 構建與部署

### 開發環境變數

create `.env` file from `.env.example`：

```bash
# Firebase (非敏感資訊，可公開)
FIREBASE_API_KEY=<value>
FIREBASE_AUTH_DOMAIN=<value>
FIREBASE_PROJECT_ID=<value>
FIREBASE_STORAGE_BUCKET=<value>
FIREBASE_MESSAGING_SENDER_ID=<value>
FIREBASE_APP_ID=<value>
FIREBASE_MEASUREMENT_ID=<value>

# Google Calendar
GOOGLE_CALENDAR_ID=<value>

# 敏感資訊（GitHub Secrets）
GOOGLE_CALENDAR_API_KEY=<value>
FCM_WEB_VAPID_KEY=<value>
```

> **`GOOGLE_CALENDAR_API_KEY` 一定會出現在前端 bundle 裡**（Web 前端呼叫
> Calendar API 沒有藏起來的方法）。請到 GCP Console → APIs & Services →
> Credentials 對這把 key 設定：
> - **Application restrictions**：HTTP referrers，只允許正式站與 preview 網域
> - **API restrictions**：只勾 Google Calendar API
>
> 沒設限制的話，任何人都能抄走這把 key 去打你的配額。

### 生產環境構建

產生用於部署的靜態檔案：

```bash
flutter build web --release --base-href / \
  --dart-define=FCM_WEB_VAPID_KEY=<PUBLIC_VAPID_KEY> \
  --dart-define=FIREBASE_API_KEY=<API_KEY> \
  --dart-define=FIREBASE_AUTH_DOMAIN=<AUTH_DOMAIN> \
  --dart-define=FIREBASE_PROJECT_ID=<PROJECT_ID> \
  --dart-define=FIREBASE_STORAGE_BUCKET=<STORAGE_BUCKET> \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=<SENDER_ID> \
  --dart-define=FIREBASE_APP_ID=<APP_ID> \
  --dart-define=FIREBASE_MEASUREMENT_ID=<MEASUREMENT_ID> \
  --dart-define=GOOGLE_CALENDAR_API_KEY=<CALENDAR_API_KEY> \
  --dart-define=GOOGLE_CALENDAR_ID=<CALENDAR_ID>
```

編譯產出位於 `build/web/`。

### 部署方式

#### Cloudflare Pages（推薦）

GitHub Actions 會自動構建並推送到 Cloudflare Pages：
- `main` 分支 → Production
- `dev` 分支 → Preview

詳見 `.github/workflows/deploy-flutter-pwa.yml`。

#### Docker + nginx（本地或自託管）

先照 `.env.example` 在專案根目錄建立 `.env`，再：

```bash
docker compose build   # 讀 .env 當作 build args
docker compose up -d   # http://localhost:8787
```

Firebase 設定必須在 **build 階段**注入（Flutter Web 是靜態檔，執行期沒機會補），
所以少了 `FIREBASE_API_KEY` 會直接讓 build 失敗，而不是產出一個開不起來的 image。

### 行事曆寫入（Cloudflare Pages Functions）

管理員與 `calendar-editors` 成員在 App 裡新增／編輯／刪除行事曆活動，會寫進
**同一本 Google Calendar**，不是另存一份。

為什麼需要伺服器端：前端讀行事曆用的是 `GOOGLE_CALENDAR_API_KEY`，而 **API key
只能讀不能寫**。寫入需要 OAuth token 或 service account 憑證，兩者都不能放進
瀏覽器。所以寫入走 `functions/api/calendar/`（Cloudflare Pages Functions，與
App 同源，沒有 CORS 問題），憑證只存在於伺服器端。

程式碼位置：

| 路徑 | 作用 |
|---|---|
| `functions/api/calendar/events.js` | `POST` 新增 |
| `functions/api/calendar/events/[id].js` | `PATCH` 編輯、`DELETE` 刪除 |
| `worker/google_calendar.js` | 共用邏輯（身分驗證、簽 JWT、參數驗證） |
| `worker/line_notify.js` | 新增成功後通知 n8n 發 LINE 群組訊息（選用） |
| `functions-tests/` | `node --test`，CI 會擋部署 |

`functions/` 放在 repo 根目錄，`wrangler pages deploy` 會自動一起上傳，
不需要改部署方式。

**權限怎麼驗**：拿呼叫者自己的 Firebase ID token 去讀 Firestore 的
`users/{uid}`，看他是不是 admin 或屬於 `calendar-editors`。刻意不在 Worker 裡
自己驗 RS256 —— 
Firestore 會驗簽章、過期與 audience，而 `firestore.rules` 只准本人讀自己那份，
所以少寫一段容易出錯的密碼學程式碼，service account 也不需要 Firestore 的
IAM 權限。

#### 一次性設定

**1. 建立 service account 並下載金鑰**

```bash
PID=<你的 Firebase 專案 id>
gcloud services enable calendar-json.googleapis.com --project="$PID"
gcloud iam service-accounts create calendar-writer \
  --display-name="Calendar writer" --project="$PID"
gcloud iam service-accounts keys create .local/service-account.json \
  --iam-account="calendar-writer@${PID}.iam.gserviceaccount.com" --project="$PID"
chmod 600 .local/service-account.json
```

**不需要給它任何 IAM 角色** —— 它的權限完全來自下一步的日曆共用。
金鑰放在 `.local/`（已 gitignore），這個 repo 是公開的，不要放別的地方。

**2. 把日曆分享給它**

Google 日曆 → 該日曆的設定 → 與特定使用者或群組共用 → 加入
`calendar-writer@<專案id>.iam.gserviceaccount.com`，權限選 **「變更活動」**。

只能用網頁操作：gcloud 的 token 拿不到 Calendar 的 scope（只允許
cloud-platform / drive 那幾個），沒辦法用指令代勞。

漏掉這步的話寫入會回 502「沒有權限寫入這本日曆」，Google 那邊的原因是
`requiredAccessLevel`。

**3. 驗證真的打得到**

```bash
node scripts/verify-calendar-writer.mjs
```

這支載入的是 `worker/google_calendar.js` **本人** —— 跟部署後跑的是同一份程式碼
—— 拿真的金鑰去真的日曆上新增一筆 2099 年的測試活動、讀回來比對、再刪掉。
單元測試裡的 Google 是假的，證明不了簽章、API 啟用與日曆共用；這支可以。

**4. 設定 Cloudflare 執行期變數**

```bash
npx wrangler login            # 只有第一次，或 token 過期時
bash scripts/push-calendar-secrets.sh
```

會把 `GOOGLE_SERVICE_ACCOUNT_JSON`、`GOOGLE_CALENDAR_ID`、`FIREBASE_PROJECT_ID`
推到 Pages，**Production 與 Preview 各一次**（Preview 沒設的話 dev 分支的預覽
站點會回「伺服器設定不完整」，而 production 看起來一切正常）。

這三個是**執行期**變數，跟 build 階段的 `--dart-define` 是兩套。金鑰是多行
JSON，用 dashboard 的輸入框貼很容易貼壞，所以走 CLI 從檔案直接送。

設完要**重新部署一次**才生效，現有的 deployment 不會自動帶到新設定。

#### LINE 群組通知（選用）

在 App 裡**新增**活動成功後，會往 n8n 打一個 webhook，由 n8n 發訊息到 LINE
群組。編輯和刪除不通知。

為什麼不從 Cloudflare 直接打 LINE Messaging API：channel access token 和訊息
排版都已經在 n8n（那邊還有一條「LINE 群組訊息 → 建事件 → 回覆」的既有流程）。
再接一次等於把同一段排版邏輯養在兩個系統。`worker/line_notify.js` 只負責把
「發生了什麼」講清楚，長什麼樣交給 n8n —— 改訊息格式不必重新部署 App。

送出去的 payload 是攤平過的，n8n 那端不必知道 Google 用 `date` 表示全天、用
`dateTime` 表示定時，也不必知道 `end.date` 是排他的：

```json
{
  "action": "created",
  "source": "pwa",
  "id": "evt-timed",
  "title": "小組聚會",
  "allDay": false,
  "start": "2026-09-01T19:00:00+08:00",
  "end": "2026-09-01T21:00:00+08:00",
  "location": "教會 2F",
  "description": "記得帶聖經",
  "link": "https://calendar.google.com/event?eid=evt-timed",
  "actorUid": "..."
}
```

**通知失敗不會讓新增失敗**。走到那一步時活動已經寫進 Google 了，回 500 只會
讓人以為沒建成然後再按一次。失敗只留在 Cloudflare 的 log 裡。通知本身丟給
`waitUntil` 在背景跑，使用者不必等 LINE。

**設定**：`NOTIFY_WEBHOOK_URL` 和 `NOTIFY_WEBHOOK_SECRET`，任一沒設就整個關掉。
`push-calendar-secrets.sh` 會從 `.local/n8n-notify-url` 和
`.local/n8n-notify-secret` 讀，**Production 與 Preview 都推**。

兩個環境發到同一個 LINE 群組，因為 n8n 那條 workflow 的群組 ID 是寫死的。
日常操作就在 dev 的預覽站上，只設 production 的話平常用的站台反而沒有通知。
真要讓預覽站發到別的地方，做法是在 n8n 依 query string 挑目標（`?to=test`
之類），而不是把 Preview 的變數留空 —— 留空只會讓那個站台整個安靜。

secret 要和 n8n Webhook node 的 Header Auth 憑證一致，header 名稱是
`x-notify-secret`。n8n 那支 workflow 的範本在 `.local/n8n/`（含群組 ID，所以不
進 repo）。

---

離線時寫入會直接失敗並提示重試，不會排隊 —— 一個小時後才默默出現的活動比
當場拒絕更難處理。

### Firestore 安全規則

`firestore.rules` 需另外部署（`firebase deploy --only firestore:rules`）。
重點行為：

- 每條規則都要求 `isActiveUser()` — 也就是 `users/{uid}` 這份文件存在。
  管理員在後台刪掉帳號後，該人的 Firebase Auth 帳號雖然還在（前端 SDK 無法
  刪別人的 Auth 帳號），但因為 user 文件沒了，所有讀寫立刻失效。
- `users` 只有本人與 `roster-editors` 成員讀得到 —— 服事表的人員選擇器要靠它
  列名單。代價要講清楚：Firestore rules 沒有欄位級的讀取限制，所以授予
  `roster-editors` 就等於讓對方看得到全部人的 email 與推播 token。只有行事曆
  權限的人讀不到，這是刻意綁 `roster-editors` 而不是「任何 group」的原因。

### 權限模型

編輯權限走 **group**，比照 Linux：一個人可以同時屬於多個，彼此正交（可以只給
行事曆不給服事表），存在 `users/{uid}` 的 `groups` 陣列。`role` 回去單純表示
身分，不決定權限 —— 唯一的例外是 `admin`，它等同 root，不必列在任何 group 裡
就擁有全部。

| | `admin` | `roster-editors` | `calendar-editors` | 沒有 group |
|---|---|---|---|---|
| 服事表 | 改（全部聚會別） | 改（**只有自己的牧區**） | 讀 | 讀 |
| 行事曆活動 | 改 | 讀 | 改 | 讀 |
| 列出使用者名單 | 可 | 可 | 不可 | 不可 |
| 開帳號／改角色／授予 group／刪帳號 | 可 | **不可** | **不可** | 不可 |
| `settings` 範本與活動選項 | 可 | **不可** | **不可** | 讀 |

要放行一個人，就在後台的使用者編輯頁勾他需要的那幾項，一個一個給。group 成員
不能授予任何人 group（包括自己），所以授權不會自己擴散 —— 只有管理員動手才會
多一個人。

#### 服事表還有第二個軸：牧區

group 決定「能不能改服事表」，`zones`（牧區）決定「能改哪一本」，兩個相乘。只
屬於青崇與兒主的人被加進 `roster-editors` 之後，主日那本仍然只讀得到 —— 分頁不
會出現，直接打 Firestore 也會被規則擋掉。要讓他碰主日，就得先把主日加進他的牧區。

`admin` 一樣是 root：一個牧區都沒有也拿得到全部聚會別。反過來，`roster-editors`
但沒有任何牧區的人什麼都改不動，服事表頁會顯示「尚未設定可檢視的牧區」。

規則判斷讀的是 `users/{uid}.zoneTypes` —— `zones` 是一個 map 的 list，而 rules
沒有迴圈也沒有 map/filter，讀不出裡面的 `serviceType`，所以 App 在寫入使用者
文件時同時攤平出這個投影（見 `User.zoneTypes`）。來源仍然只有 `zones` 一份。

**這一項需要資料遷移**：既有使用者文件都沒有 `zoneTypes`，會被讀成「沒有牧區」，
於是所有非 admin 的服事表編輯者都會寫入失敗。**部署新規則前**先補：

```bash
node scripts/backfill-user-zone-types.mjs           # dry run，先看要改哪些人
node scripts/backfill-user-zone-types.mjs --apply   # 確認後才寫入
```

憑證沿用部署規則本來就要登的那份 firebase CLI 登入（`FIREBASE_TOKEN`、firebase
CLI、gcloud，由近到遠取第一個拿得到的），不必為了這支腳本另外登入。它同時會列出
「有 `roster-editors` 但一個牧區都沒有」的人 —— 那些人補完之後會變成什麼都改不動，
要先到後台把牧區加上去。

同一支腳本也是 `zoneTypes` 的漂移檢查：

```bash
node scripts/backfill-user-zone-types.mjs --check   # 只稽核，有不一致就非 0 退出
```

走 App 的寫入漂不掉（`toJson()` 每次由 `zones` 重算），會漂的是繞過 App 直接改
文件 —— Firebase console 手改、Admin SDK 腳本、遷移程式。那種漂移在畫面上看不
出來（UI 讀的是 `zones`），只會表現成「某個人的服事表存不進去」。`--check` 隨時
可以跑，也適合掛進排程。

（`groups` 本身仍然不需要遷移：規則讀的是 `data.get('groups', [])`，既有使用者
沒有這個欄位就一律視為沒有任何 group。）

看得到權限的地方有三處：使用者編輯頁的「編輯權限」勾選框（管理員授權用）、
使用者列表的副標尾端「可編輯：…」（管理員一眼掃全部人用；角色與牧區都是身分，
排在前面）、以及個人頁角色標籤旁邊
的權限標籤（本人自己看）。管理員三處都不列出個別 group —— 他隱含全部，逐項列出
反而像是只被指定了那幾項。

強制點有三個，改動時要一起改：

| 檔案 | 東西 | 角色 |
|---|---|---|
| `firestore.rules` | `inGroup()` | 真正的防線（服事表、使用者名單） |
| `worker/google_calendar.js` | `CALENDAR_GROUP` | 真正的防線（行事曆） |
| `lib/features/auth/domain/entities/user.dart` | `UserGroup` | 只決定 UI 顯不顯示入口 |

group 名稱字串是資料格式的一部分（存進 Firestore 的就是它），改名等於要遷移
資料。`firestore.rules` 的 `hasValidGroups()` 會擋掉不在清單裡的名稱，避免打錯
字變成一個看起來像授權、實際上什麼都不對應的欄位。

## 開發規範

### 命名慣例

- **檔案與資料夾**：使用 `snake_case`（如 `main_scaffold.dart`、`roster_provider.dart`）
- **類別與介面**：使用 `PascalCase`（如 `RosterProvider`、`RosterRepository`）
- **常數**：使用 `camelCase`（如 `appTitle = 'Church Staff'`）

### 狀態管理

- 使用 `Provider`，盡可能將作用域限制在特定功能模組內
- 跨功能共享的全域資料（如認證狀態）定義在 `lib/main.dart`
- 認證狀態拆分為兩個 Provider：`SessionProvider`（登入 / 登出 / session restore）與 `UserAdminProvider`（使用者 CRUD、cache 管理）
- 避免過度耦合，保持 Provider 樹的清晰

### 測試規範

- 使用 `flutter_test` 框架
- 測試檔案位於 `test/` 目錄，命名為 `<feature>_<unit>_test.dart`（如 `roster_provider_test.dart`）
- 執行所有測試後再提交 Pull Request

### 代碼風格

- **縮進**：2 個空格
- **格式化**：使用 Dart formatter（`dart format lib test`）
- **分析**：遵守 `analysis_options.yaml` 與 `flutter_lints` 規則

更多詳細的開發規範與 commit 風格，請參考 [`AGENTS.md`](./AGENTS.md)。

## 常見命令

```bash
# 依賴管理
flutter pub get              # 安裝依賴
flutter pub upgrade          # 升級依賴

# 開發與調試
flutter run -d chrome        # 在 Chrome 中執行
flutter run -d chrome --debug # 調試模式

# 代碼品質
flutter analyze              # 靜態分析
flutter test                 # 執行測試
dart format lib test         # 格式化代碼

# 行事曆寫入 API（Pages Functions，無相依套件）
npm test --prefix functions-tests

# service worker 的快取策略（無相依套件）
npm test --prefix web-tests

# 構建
flutter build web --release --base-href /  # 生產構建（不含 dart-define）
# 詳見上述「生產環境構建」段落，包含完整 dart-define 參數
```

## 項目結構簡述

### `lib/core/`
共享的主題、通用 UI 組件、工具函數。

### `lib/features/<feature>/`
每個功能模組包含：
- `domain/`: Entities（實體）、Repository 介面、Use Cases（使用情景）
- `data/`: Repository 實現、Data Sources（遠端/本地）
- `presentation/`: Screens（頁面）、Providers（狀態）、Widgets（組件）

### `lib/presentation/`
應用層 UI 編排，如 `main_scaffold.dart` 包含 Bottom Navigation Bar。

### `web/`
PWA 資源（manifest、icon、`index.html`）。

## 故障排除

### Flutter 版本相容性

若遇到依賴版本衝突，嘗試：

```bash
flutter clean
flutter pub get
flutter analyze
```

### Firebase 設定問題

確認 `lib/firebase_options.dart` 已包含正確的 Firebase 配置。生產構建時務必提供 `--dart-define` 參數。

### PWA 離線功能

Service Worker 是自己的一份：`web/cache_sw.js`。Flutter 3.27+ 內建的那支在
activate 時會把自己反註冊掉，沒有快取的話每次重新載入都要重抓 `main.dart.js`
（約 3 MB）與 `canvaskit.wasm`（約 7 MB）。

策略分三層：

| 對象 | 策略 | 快取名 |
|---|---|---|
| `/`、`index.html`、`app_update.js`、`manifest.json`、`flutter_bootstrap.js`、`flutter.js` | network-first，快取只當離線 fallback | 綁 build SHA |
| 其餘同源資產（含 `main.dart.js`、`version.json`） | cache-first | 綁 build SHA |
| `/canvaskit/` | cache-first，跨 deploy 存活 | 綁 Flutter 版本 |
| `fonts.gstatic.com` 的中文字型 subset | cache-first，上限 64 筆 | 不綁版本 |
| Firestore／Auth／FCM／Calendar 等 API | 完全不攔截 | — |

`version.json` **刻意** cache-first：個人頁的「更新於」要回答的是「我手上這個
App 是哪一版」。放進 network-first 的話，舊 SW 還在服務舊 bundle、卻顯示伺服器
最新的部署時間，一台裝置到底更新了沒就再也看不出來（實際踩過兩次）。更新偵測
不靠它，靠的是 SW 的 `updatefound` / `SKIP_WAITING`（見 `web/index.html`）。

換版交接在 `web/app_update.js`：新的 SW 裝好後會停在 `waiting`，要有人送
`SKIP_WAITING` 才會 activate，activate 觸發 `controllerchange`，那時重載一次就
換到新 bundle。它自己走 network-first —— 這段程式碼決定裝置能不能換到新版，被
舊快取服務就再也救不回來。三個時機會去檢查：載入、切回前景（PWA 從多工列切回
來不算 navigation，瀏覽器不會自己檢查）、以及個人頁的「檢查更新」按鈕。特別注
意 `registration.waiting`：新版若在上一次造訪就裝好、停在 waiting，這一次載入
不會再有 `updatefound`，只等那個事件的話裝置就永遠卡在舊版。

`web-tests/` 用 `node:vm` 把 `web/cache_sw.js` 與 `web/app_update.js` 真的跑起
來、餵假的 `caches` / `fetch` / `navigator.serviceWorker`，逐條驗這張表與上面
那些時序，CI 會擋部署。

確保 `web/manifest.json` 正確配置，並在生產環境啟用 HTTPS。

## 貢獻指南

歡迎提交 Issue 與 Pull Request！詳見 [`AGENTS.md`](./AGENTS.md) 了解提交規範。

## 許可證

（待補充）
