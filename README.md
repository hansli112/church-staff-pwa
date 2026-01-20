# 教會同工助手 (Church Staff PWA)

這是一個基於 **Flutter** 開發的全方位 **漸進式網路應用程式 (PWA)**，旨在為教會同工與志工提供一個集中的管理平台。專案採用 **Feature-First (功能優先)** 架構，方便未來輕鬆擴展模組。

## 🌟 核心功能

*   **集中式儀表板**：快速存取核心工具與關鍵資訊。
*   **服事表管理**：管理服事行程與志工安排（目前使用模擬數據）。
*   **模組化設計**：可輕鬆添加新功能，如「請假申請」、「場地預約」或「公告系統」。
*   **PWA 優化**：針對行動裝置進行優化，提供類原生 App 的使用體驗。
*   **在地化支持**：完整支援繁體中文 (`zh_TW`)。

## 🛠 技術棧

*   **框架**：Flutter (Web Channel)
*   **語言**：Dart
*   **狀態管理**：`provider`
*   **導覽**：標準 Flutter 導覽配合 `NavigationBar`
*   **在地化**：`intl` 套件
*   **UI 風格**：Material Design 3

## 🏗 架構設計

專案採用 **Feature-First** 模式。每個功能（Feature）都是一個獨立的微型模組，並包含其自身的 Clean Architecture 層次。

### 目錄結構

```text
lib/
├── core/               # 共享資源（主題、通用組件）
├── features/           # 獨立功能模組
│   ├── dashboard/      # 儀表板功能
│   └── roster/         # 服事表管理功能
│       ├── data/       # 資料庫實作與數據源
│       ├── domain/     # 實體 (Entities) 與儲存庫介面
│       └── presentation/ # UI 介面與 Provider 狀態
└── presentation/       # 應用層 UI 編排 (Main Scaffold)
```

## 🚀 快速入門

### 前置準備

*   已安裝 [Flutter SDK](https://flutter.dev/docs/get-started/install)。
*   網頁瀏覽器（建議使用 Chrome 進行調試）。

### 本地開發

在 Chrome 中以開發模式執行：

```bash
flutter run -d chrome
```

### 生產環境構建

產生用於部署的靜態檔案（適用於 GitHub Pages、Firebase Hosting 等）：

```bash
flutter build web --release --base-href /
```

## 💻 開發規範

*   **命名慣例**：檔案與資料夾使用 `snake_case`，類別名稱使用 `PascalCase`。
*   **狀態管理**：使用 `Provider`。盡可能將 Provider 的作用域限制在特定功能模組內；僅在全域共享資料時才在 `main.dart` 定義。
*   **UI 設計**：嚴格遵守 Material Design 3 設計指南。
