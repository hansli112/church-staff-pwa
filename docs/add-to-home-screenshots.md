# 加入主畫面教學截圖

截圖日期：2026-10-09。圖片位於 `app/assets/add_to_home/`，來自實際操作手機模擬器或已授權的實體 iPhone，不是重畫的介面。只裁切操作區域並加上藍色圈選，沒有翻譯或替換截圖中的選單文字。

## 已收錄

| 圖片 | 真實來源 | 圈選位置 |
| --- | --- | --- |
| `safari_more.png` | iPhone 17 Pro 模擬器、iOS 26.5、Safari、繁體中文 | 精簡工具列右側的「⋯」 |
| `safari_share.png` | 同上 | Safari 選單的「分享」 |
| `safari_share_more.png` | 同上 | 系統分享面板的「檢視較多」 |
| `safari_add.png` | 同上 | 展開後的「加入主畫面」 |
| `chrome_android_more.png` | Android 14 模擬器、Chrome 113.0.5672.136、繁體中文 | 網址列右側的「⋮」更多選單 |
| `chrome_android_add.png` | 同上 | 舊版選單的「加到主畫面」 |
| `chrome_ios_share.png` | iPhone 13 真機、iOS 27.2、Chrome 155.0.8059.37 | 網址列右側的網頁分享圖示 |
| `chrome_ios_add.png` | 同上 | 展開後的中文版「加入主畫面」 |

擷取的是公開的 `https://marthasit.web.app/`，未使用私人教會、登入資訊或邀請連結。實體 iPhone 的系統語言未更動；Chrome 透過本次啟動參數暫用繁中。

## 使用界線

- 來源標示必須保留瀏覽器版本及真機／模擬器資訊，不把模擬器稱為實體手機實測。
- Safari 26.5 的精簡版面是「⋯ → 分享 → 檢視較多 → 加入主畫面」。其他版面可能直接顯示分享按鈕，舊版分享面板可能改用向下捲動。
- Android 手動教學圖片是 **Chrome 113 的舊版選單**，不是目前版本。文字同時說明較新的「安裝並建立捷徑 → 安裝」，不得把舊版圖片標成新版。
- Android 若收到瀏覽器真正的 `beforeinstallprompt`，優先顯示一顆「加入主畫面」按鈕，再由系統詢問安裝；只有沒有邀請時才顯示手動備用教學。
- 不把 Safari 圖片放在 iPhone Chrome／Firefox 或 iPad 教學，避免冒充不同瀏覽器或裝置的畫面。
- iPhone Chrome 的兩張真機圖均已補齊。系統分享面板中「View Less」「Open in Safari」及第三方 App 名稱仍是英文，因此只裁切中文版「加入主畫面」附近，未重畫或翻譯圖片，也不把無關的個人 App 清單納入專案。
- iPhone Firefox、Android Firefox、iPad Safari 的繁中截圖尚缺，這些分流保留已核實的文字步驟，沒有仿造或借用截圖。
- Edge／Samsung Internet 未核實的手動選單仍使用外部瀏覽器退路；若有實際安裝邀請，優先顯示安裝按鈕。

## 完整操作截圖

`docs/screenshots/add_to_home/` 保留 2026-10-09 直接擷取的完整畫面：

- `iphone_safari_step_1.png`、`iphone_safari_step_2.png`：iPhone Safari 模擬器開啟本機示範模式的新教學，涵蓋三個步驟及頁面捲動。
- `android_chrome_browser.png`、`android_chrome_menu.png`：Android Chrome 113 模擬器開啟公開網站及其繁中原生選單。
- `android_chrome_step_1.png`、`android_chrome_step_2.png`：Android 模擬器開啟本機新版繁中手動備用教學，涵蓋三個步驟。
- `android_install_button.png`、`android_install_confirm.png`：Android Chrome 真正提供安裝邀請後，主畫面的大按鈕及原生「安裝應用程式」確認面板。事件已確認為 `BeforeInstallPromptEvent`、`isTrusted=true`，不是注入假事件；未按最後的安裝確認。測試網址是受信任的本機 `http://localhost:51747/`，不是原先不安全的 `10.0.2.2` 網址。
- `iphone_chrome_browser.png`：iPhone 13 真機 Chrome 的網頁分享入口。
- `iphone_chrome_add.png`：同一台真機分享面板的中文目標區域；為保護隱私及避免英中混雜，未保存其餘分享 App 清單到專案。

拍攝初期曾出現 Android 黑屏，重新開啟教學後已正常顯示並取得完整截圖；黑屏與安裝邀請延遲的根因都尚未確認，沒有為此修改 App 程式。取得原生安裝邀請時沒有 service worker 註冊，不宣稱是 service worker 修復。截圖確認的是 UI、捲動、安裝邀請及確認面板，不代表所有版本的完整安裝、通知流程皆已驗證。

## 維護

換圖時同步更新 `_GuideScreenshots` 的 `aspectRatio`、來源文案與測試。圖片必須先預留比例，避免解碼後推移同工正在點的按鈕。新圖片以操作區域為主，保持周圍足以定位的真實介面，不放無關的整頁截圖。
