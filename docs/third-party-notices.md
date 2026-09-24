# 第三方授權與素材

本專案原創程式碼的 [MIT License](../LICENSE) 不取代任何第三方授權。重散布 source 或 build 時，應保留原有著作權聲明、授權條文及需要附帶的 notices。這份說明不是完整法務稽核、授權適用性的保證，也不主張擁有外部內容的權利。

## 已檢查的範圍

2026-09-24 以當時的 `pubspec.lock`，讀取本機 pub cache 對應版本的根 `LICENSE`，並初步分類。這次共找到 **68 個 hosted 套件的 LICENSE**；沒有只憑套件名稱推定授權。另讀取 Flutter `3.41.0` 的根 LICENSE 與 SDK 隨附字型授權檔。版本升級後須重新核對；完整原文仍以套件內 LICENSE 為準。

直接相依套件（包含開發工具）：

| 套件 | 核對版本 | 根 LICENSE |
|---|---|---|
| `cloud_firestore` | 6.8.0 | BSD-3-Clause |
| `cupertino_icons` | 1.0.9 | MIT；原文署名 Vladimir Kharlampidi |
| `firebase_auth` | 6.5.7 | BSD-3-Clause |
| `firebase_core` | 4.13.0 | BSD-3-Clause |
| `firebase_messaging` | 16.5.0 | BSD-3-Clause |
| `flutter_lints` | 6.0.0 | BSD-3-Clause |
| `http` | 1.6.0 | BSD-3-Clause |
| `intl` | 0.20.3 | BSD-3-Clause |
| `provider` | 6.1.5+1 | MIT；原文署名 Remi Rousselet |
| `shared_preferences` | 2.5.5 | BSD-3-Clause |
| `timezone` | 0.11.1 | BSD-2-Clause |
| `url_launcher` | 6.3.2 | BSD-3-Clause |
| `web` | 1.1.1 | BSD-3-Clause |

其餘根 LICENSE 中：

- MIT：`nested` 1.0.0（Remi Rousselet）。
- Apache-2.0：`clock` 1.1.2、`fake_async` 1.3.3、`material_color_utilities` 0.13.0。
- BSD-3-Clause：`_flutterfire_internals`、`async`、`boolean_selector`、`characters`、`cloud_firestore_platform_interface`、`cloud_firestore_web`、`collection`、`ffi`、`file`、`firebase_auth_platform_interface`、`firebase_auth_web`、`firebase_core_platform_interface`、`firebase_core_web`、`firebase_messaging_platform_interface`、`firebase_messaging_web`、`http_parser`、`leak_tracker`、`leak_tracker_flutter_testing`、`leak_tracker_testing`、`lints`、`matcher`、`meta`、`path`、`path_provider_linux`、`path_provider_platform_interface`、`path_provider_windows`、`platform`、`plugin_platform_interface`、`shared_preferences_android`、`shared_preferences_foundation`、`shared_preferences_linux`、`shared_preferences_platform_interface`、`shared_preferences_web`、`shared_preferences_windows`、`source_span`、`stack_trace`、`stream_channel`、`string_scanner`、`term_glyph`、`test_api`、`typed_data`、`url_launcher_android`、`url_launcher_ios`、`url_launcher_linux`、`url_launcher_macos`、`url_launcher_platform_interface`、`url_launcher_web`、`url_launcher_windows`、`vector_math`、`vm_service`、`xdg_directories`。版本記錄於 `pubspec.lock`。

以上是根授權檔層級的觀察，不等於已逐一稽核每個子目錄、vendored library、平台原生 SDK 或所有 notices。

## Flutter、字型與建置產物

- Flutter SDK 根授權是 BSD-3-Clause，原文署名 The Flutter Authors。
- 本機 SDK 的 `MaterialIcons_LICENSE.txt` 是 **CC BY 4.0**；不要因程式套件採 BSD/MIT，就宣稱所有字型也一樣。Material Icons 來源為 Google 的 [Material Design Icons](https://github.com/google/material-design-icons)。Flutter release build 可能做字型子集化，應保留相應 notices。
- 本機 SDK 的 `Roboto_LICENSE.txt`、`RobotoCondensed_LICENSE.txt` 為 Apache-2.0。
- CSS 指定 `Noto Sans TC`、`PingFang TC`、`Microsoft JhengHei` 等名稱，不代表本 repo 提供或授權這些字型檔。瀏覽器／Flutter 實際使用的系統字型或下載字型，須按發佈環境另行核對。
- App「我的 → 開源授權」透過內建 `showLicensePage` 顯示授權。保留 Flutter 的 `LicenseRegistry`／`LicensePage` 及 build 產生的 `assets/NOTICES.Z` 等授權資源，不要為縮小檔案而移除。實際 notices 路徑可能隨 Flutter 版本調整。
- 本 repo 沒有以自己的 MIT 聲明覆蓋 CanvasKit、Dart runtime、Firebase JavaScript SDK 或相關原生 SDK 的授權。

## PWA 圖示

目前 `web/favicon.png` 與 `web/icons/Icon-{192,512}.png`、`Icon-maskable-{192,512}.png` 是本專案**自行程式產生**的中性幾何人物圖形，未使用外部 logo、圖片或字型，隨本專案 MIT 授權。可重現產生：

```bash
node scripts/generate-neutral-icons.mjs
```

此命令會覆寫這五個預設圖示。部署者的客製圖示請保存在私有設定／素材目錄並經 staging 帶入，不要先覆寫 repo 的預設檔。

舊版本中的圖示來源及權利未查實，已從目前檔案換下；這不會改變 Git 歷史中的舊素材，也不構成對舊素材使用／散布權的追認。若要重散布舊版，仍須另行處理。

## 尚未查實／由部署者負責

- npm／Firebase CLI／Wrangler／GitHub Actions 及其傳遞相依套件的完整授權樹，未做逐檔稽核。
- Flutter engine、CanvasKit、平台 SDK 及遠端載入的 Firebase scripts／中文字型等，未完成全套 notices 的逐項比對。
- 各聖經譯本、靈修文章、經文範圍 feed、來源網站的再散布及擷取條款。可公開存取不等於可擷取、複製或改作；預設不啟用任何來源。
- 教會名稱、商標、客製圖示、人員照片及個資。沒有將任何教會品牌使用權隨 MIT 轉授；請只加入有權使用的素材。
- Google/Firebase、Cloudflare、Gemini、LINE/n8n 等服務條款、資料處理與地域法規。開源授權不豁免服務商條款、付費義務或個資保護責任。

發佈前建議重新核對鎖定版本與實際 build，保留完整 notices，確認新增素材的來源與授權；有疑義時尋求適當的法律意見。
