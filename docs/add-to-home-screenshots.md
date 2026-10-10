# 加入主畫面教學截圖

截圖日期：2026-10-09。圖片位於 `app/assets/add_to_home/`，來自實際操作手機模擬器或已授權的實體 iPhone，不是重畫的介面。只裁切操作區域並加上藍色圈選，沒有翻譯或替換截圖中的選單文字。

## 已收錄

| 圖片 | 真實來源 | 圈選位置 |
| --- | --- | --- |
| `safari_more.png` | iPhone 17 Pro 模擬器、iOS 26.5、Safari、繁體中文 | 精簡工具列右側的「⋯」 |
| `safari_share.png` | 同上 | Safari 選單的「分享」 |
| `safari_direct_share.png` | 同上，Safari「下方」版面；亦核對「上方」版面 | 底部工具列中央的分享圖示；兩種版面共用同一位置 |
| `safari_share_more.png` | 同上 | 系統分享面板的「檢視較多」 |
| `safari_add.png` | 同上 | 展開後的「加入主畫面」 |
| `chrome_android_more.png` | Android 14 模擬器、Chrome 113.0.5672.136、繁體中文 | 網址列右側的「⋮」更多選單 |
| `chrome_android_add.png` | 同上 | 舊版選單的「加到主畫面」 |
| `chrome_ios_share.png` | iPhone 13 真機、iOS 27.2、Chrome 155.0.8059.37 | 網址列右側的網頁分享圖示 |
| `chrome_ios_add.png` | 同上 | 展開後的中文版「加入主畫面」 |

既有瀏覽器圖片擷取公開的 `https://marthasit.web.app/`；新增的 Safari「下方／上方」工具列與分享面板擷取公開的 `https://marthasit-dev.web.app/`。皆未使用私人教會、登入資訊或邀請連結。實體 iPhone 的系統語言未更動；Chrome 透過本次啟動參數暫用繁中。

## 使用界線

- 來源標示必須保留瀏覽器版本及真機／模擬器資訊，不把模擬器稱為實體手機實測。
- Safari 26.5 的設定選項為「精簡／下方／上方」。精簡版面先「⋯ → 分享」，下方與上方版面都直接按底部中央的分享圖示；已分別在模擬器核對位置，採用同一張真實工具列截圖，不放兩張近似圖片。分享後若只看到圖示列，先「檢視較多 → 加入主畫面」；舊版分享面板可能改用向下捲動。
- 網頁不能可靠讀取 Safari 的版面設定；iPhone Safari 的「畫面不一樣？」讓同工選 `我看到「⋯」` 或 `我看到分享圖示`。選擇只切換該次教學的步驟與截圖，不更改 Safari 設定、不開啟其他瀏覽器；iPad 維持獨立的文字操作順序。
- Safari 直接分享已確認會出現真正的繁中系統分享面板，含「檢視較多」；未按最終的加入或安裝。拍攝後已恢復原本的精簡設定及模擬器關機狀態。
- Android 手動教學圖片是 **Chrome 113 的舊版選單**，不是目前版本。文字同時說明較新的「安裝並建立捷徑 → 安裝」，不得把舊版圖片標成新版。
- Android 若收到瀏覽器真正的 `beforeinstallprompt`，優先顯示一顆「加入主畫面」按鈕，再由系統詢問安裝；只有沒有邀請時才顯示手動備用教學。
- 不把 Safari 圖片放在 iPhone Chrome／Firefox 或 iPad 教學，避免冒充不同瀏覽器或裝置的畫面。
- iPhone Chrome 的兩張真機圖均已補齊。系統分享面板中「View Less」「Open in Safari」及第三方 App 名稱仍是英文，因此只裁切中文版「加入主畫面」附近，未重畫或翻譯圖片，也不把無關的個人 App 清單納入專案。
- iPhone Firefox、Android Firefox、iPad Safari 的繁中截圖尚缺，這些分流保留已核實的文字步驟，沒有仿造或借用截圖。
- Edge／Samsung Internet 未核實的手動選單仍使用外部瀏覽器退路；若有實際安裝邀請，優先顯示安裝按鈕。

## 完整操作截圖

`docs/screenshots/add_to_home/` 保留 2026-10-09 直接擷取的完整畫面：

- `iphone_safari_step_1.png`、`iphone_safari_step_2.png`：iPhone Safari 模擬器開啟本機示範模式的新教學，涵蓋三個步驟及頁面捲動。
- `iphone_safari_layout_choices.png`、`iphone_safari_direct_guide.png`：新版 Safari 工具列選擇及直接分享教學。以本機示範資料、Chromium 的 iPhone viewport／UA 擷取；不把這兩張 App 預覽稱為 Safari 真機或原生分享面板實測。圖解內的 `safari_direct_share.png` 則來自上述真正的 Safari 模擬器工具列。
- `android_chrome_browser.png`、`android_chrome_menu.png`：Android Chrome 113 模擬器開啟公開網站及其繁中原生選單。
- `android_chrome_step_1.png`、`android_chrome_step_2.png`：Android 模擬器開啟本機新版繁中手動備用教學，涵蓋三個步驟。
- `android_install_button.png`、`android_install_confirm.png`：Android Chrome 真正提供安裝邀請後，主畫面的大按鈕及原生「安裝應用程式」確認面板。事件已確認為 `BeforeInstallPromptEvent`、`isTrusted=true`，不是注入假事件；未按最後的安裝確認。測試網址是受信任的本機 `http://localhost:51747/`，不是原先不安全的 `10.0.2.2` 網址。
- `iphone_chrome_browser.png`：iPhone 13 真機 Chrome 的網頁分享入口。
- `iphone_chrome_add.png`：同一台真機分享面板的中文目標區域；為保護隱私及避免英中混雜，未保存其餘分享 App 清單到專案。

拍攝初期曾出現 Android 黑屏，重新開啟教學後已正常顯示並取得完整截圖；黑屏與安裝邀請延遲的根因都尚未確認，沒有為此修改 App 程式。取得原生安裝邀請時沒有 service worker 註冊，不宣稱是 service worker 修復。截圖確認的是 UI、捲動、安裝邀請及確認面板，不代表所有版本的完整安裝、通知流程皆已驗證。

## 維護

換圖時同步更新 `_GuideScreenshots` 的 `aspectRatio`、來源文案與測試。圖片必須先預留比例，避免解碼後推移同工正在點的按鈕。新圖片以操作區域為主，保持周圍足以定位的真實介面，不放無關的整頁截圖。
