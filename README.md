# 教會同工助手 (Church Staff PWA)

這是一個基於 **Flutter Web** 開發的全方位 **漸進式網路應用程式 (PWA)**，旨在為教會同工與志工提供集中的管理平台。專案採用 **Feature-First (功能優先)** 架構搭配 **Clean Architecture**，方便未來輕鬆擴展模組。

## 核心功能

- **集中式儀表板**：快速存取核心工具與關鍵資訊
- **服事表管理**：管理服事行程與志工安排
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

### Firestore 安全規則

`firestore.rules` 需另外部署（`firebase deploy --only firestore:rules`）。
重點行為：

- 每條規則都要求 `isActiveUser()` — 也就是 `users/{uid}` 這份文件存在。
  管理員在後台刪掉帳號後，該人的 Firebase Auth 帳號雖然還在（前端 SDK 無法
  刪別人的 Auth 帳號），但因為 user 文件沒了，所有讀寫立刻失效。
- `users` 只有本人與管理員讀得到，一般同工看不到別人的 email 與推播 token。

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

Service Worker 由 Flutter 自動管理；確保 `web/manifest.json` 正確配置，並在生產環境啟用 HTTPS。

## 貢獻指南

歡迎提交 Issue 與 Pull Request！詳見 [`AGENTS.md`](./AGENTS.md) 了解提交規範。

## 許可證

（待補充）
