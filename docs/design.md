# 馬大別忙 · 設計決策

> 2026-10-02 與 Hans 逐項確認。來源：church-staff-pwa（self-host 版）改版為多教會代管服務。

## 產品

- 代管、多教會共用的**同工工具**（不含會友）。單一 App「馬大別忙」（驚嘆號可有可無），教會 logo 在 App 內顯示。
- 平台：iOS、Android、Web（PWA），同一份 Flutter code。
- 語言：i18n 架構（ARB）。繁中先出；英文、簡中之後補。
- 營運：Hans 個人。不主動拓展，有人問就給用；已知有台灣、香港、馬來西亞詢問。
- 發布：**全部做完一次發布**，不分階段。
- 用語：一律說「安排服事表」，不說「排班」。其他用語見 `CONTEXT.md`。
- 介面風格：乾淨、少操作、少文字。原則見 `docs/design-principles.md`，以 Apple Human Interface Guidelines 為準。

## 後端

- Firebase Blaze（用量維持在免費額度內），設 budget alert。
- Cloud Functions 放特權邏輯；Web 放 Firebase Hosting；**移除 Cloudflare**。
- 專案：`prod`、`dev` 兩個新 Firebase 專案。不沿用 `church-staff-pwa`。
- Region：`asia-east1`，所有教會共用。
- 資料模型：
  - `users/{uid}`：全域個資、語言、推播 token（每裝置）
  - `churches/{cid}/members/{uid}`：角色、權限群組、牧區（沿用現有 user doc 的權限形狀）
  - `churches/{cid}/...`：rosters、settings、staff_orders
- 遷移預留（輕度）：repository interface 保持乾淨；`churches/{cid}` 可整棵匯出；ID、時間不依賴 Firestore 專有型別；權限邏輯另寫規格文件。
- 多教會身分：資料模型支援，產品不鼓勵；簡單的教會切換即可。

## 帳號與教會

- 自由註冊。
- 登入方式：
  - **Google 登入為主**，第一版就支援，登入畫面放在最顯眼的位置。
  - iOS 加 **Sign in with Apple**（Apple 準則 4.8：有第三方登入就必須提供）。這個功能要付費的開發者帳號才能設定，所以在 M7 付年費後補上。
  - email＋密碼收在下方，用 email 註冊的人才需要驗證 email；Google、Apple 帳號視為已驗證。
  - Firebase Auth 開「同一 email 只能有一個帳號」，處理不同登入方式的帳號連結（`account-exists-with-different-credential`）。
- 同名檢查：名稱正規化（空白、全半形、大小寫）後完全相同就提醒並擋下，附聯絡連結。被搶註時由 Hans 在後台處理。
- 不設教會數量或用量上限；非教會單位也可使用（服務條款寫明為教會設計）。
- Hans 的後台：教會改名、轉移管理員、停用教會。
- 教會 logo：管理員上傳到 Firebase Storage，上限 1MB，壓成 512px，只在 App 內顯示（頂部、歡迎畫面）。Storage rules 只允許該教會管理員寫入。
- 退出教會：非管理員可以自己退出。
  - 入口放在「我的 → 教會資訊」最下方，紅字。
  - 確認視窗：「退出〈教會名〉？需要重新邀請才能回來」，要再按一次「退出」。不要求輸入教會名稱。
  - 退出後通知該教會管理員。
- 帳號刪除（Apple 5.1.1(v)）：App 內自行刪除，刪 Auth、`users/{uid}` 與所有 membership；服事表保留姓名文字；唯一管理員須先交接；教會刪除後保留 30 天可還原。

## 功能（第一版）

- 核心：登入、同工、服事表。
- 安排服事表時選人：
  - 沿用 self-host：只列出有這項服事的同工，照同工排序排好。
  - 加搜尋框，搜尋整間教會的成員，比對名字的一部分，忽略全半形與大小寫。
  - 結果分兩區：上面是有這項服事的人，下面是「其他同工」。選了下面的人，問要不要順便把這項服事加到他身上。
  - 名單超過 30 人時，搜尋框自動取得焦點。
- 推播：FCM（iOS 需 APNs）。
- 行事曆：Google OAuth。M7 買網域後送 Google OAuth 驗證（`calendar.events` 是 sensitive scope，不需要 CASA，免費）；通過之前是 **In production 但未驗證**（只有管理員連接日曆時會看到警告畫面，終身約 100 位授權者上限）。Google 登入只用基本權限，不會出現警告。管理員連接並選日曆；refresh token 加密存後端；讀寫皆由後端代理並快取；授權失效時顯示重新連接。Scope：`calendar.events`、`calendar.calendarlist.readonly`。
- 交換服事：由能安排服事表的人操作。在服事表上點某人 →「交換」→ 只列出同一服事項目的其他日期 → 點一下完成，兩天一次寫入，可復原。同工自己發起交換請求之後再做。
- 特別活動：貼在某一天服事表上的彩色標籤（聖餐、浸禮、特會…）。各聚會別的常用選項與顏色和服事設定放在同一頁，安排服事表時可勾選或臨時自訂。
- 照片辨識：Hans 付費，Gemini **付費 tier**；每教會每月 30 張；全站每月上限 US$20，超過自動關閉。
- 不做：LINE 通知、每日靈糧、小組範本（self-host 只拿來顯示，沒有用在權限或安排服事表；之後需要再加成同工資料的文字欄位）。

## 金流

- 只做「支持平台」，不經手教會奉獻。
- 一次性打賞（IAP consumable）＋訂閱（回饋：只有自己看得到的徽章、可換成預設的 3–4 款 App icon）。iOS、Android 的替換 icon 都必須在打包時放進 App，不能用使用者上傳的圖，所以教會 logo 不能當 App icon。
- 原生 `in_app_purchase`，支持者狀態**只在裝置上判斷**，無後端、不同步 Firestore。
- 第一版不做感謝名單（考慮過只顯示 email，但支持者狀態只在裝置上，要列名單就得加後端收據驗證，而且 email 也是個資）。Web 版不放贊助連結。

## 實作方式

- **重寫**，不搬 self-host 的畫面、流程、狀態管理與資料存取。self-host 的程式碼與註解當規格讀：每張 ticket 先列出舊版的行為與邊界情況，再重新設計。
- 只有不碰 UI、不碰 Firebase 的純邏輯（同工排序、匯入解析、日期工具）可以搬，搬時補測試；新設計下不合理就重寫。
- Firebase 專案用 Hans 的**個人 Google 帳號**建立，不放在 dwave.cc organization 底下。

## 效能

目標：比 self-host 版明顯順。self-host 在資料一多時幾乎都會卡。

self-host 已經做了延遲建構清單（`ListView.builder`）和縮小重建範圍（`context.select`），所以卡頓的主因推測是下面兩點，M2 先用大量測試資料實測確認：
- Flutter Web 在 iPhone 上只能跑 JS 版 CanvasKit，Dart 全擠在 UI 執行緒；wasm 版被 WebKit bug 擋住。
- 每次進畫面都向伺服器重讀（`.get()`），打開選人視窗就重抓全部使用者。

做法：
1. iPhone 使用者以原生 App 為主，這是最大的改善。
2. 資料層：開 Firestore 離線快取；改用 listener，先用快取顯示，再背景更新；成員名單每間教會只讀一次，在記憶體共用。
3. 卡片內容（服事項目、特別活動）也延遲建構；排序、分組這類計算放在 build 之外，資料變了才重算。
4. 驗收目標，每個里程碑用測試資料實測（150 位同工、一年份服事表），在原生 App 與 iPhone Safari 各測一次：
   - 原生 App 冷啟動到看見服事表 < 1.5 秒。
   - 切換頁面、打開選人視窗 < 100ms。
   - 捲動維持 60fps。
5. Web 版的引擎限制無法消除，但資料層的改善一樣適用。

### 量測紀錄

工具：
- `functions/scripts/seed.ts`：灌測試資料到 emulator 或 dev。
- `tools/e2e/perf.mjs`：計時，用 profile build 加 `PERF_MARKS=true`。
- `--dart-define=PERF_HUD=true`：顯示 frame 時間。

**2026-10-02**

條件：
- Web profile build，資料在記憶體（demo：150 位同工、3 種聚會、一年份服事表）。
- 在 Linux 伺服器上用 headless 瀏覽器跑，沒有 GPU（軟體繪圖）。
- 每項跑 5 次取中位數。

| 項目 | 目標 | Chromium | WebKit |
| --- | --- | --- | --- |
| 冷啟動到看見服事表 | < 1.5 秒 | 1.25 秒 | 1.15 秒 |
| 切換分頁 | < 100ms | 89ms | 81ms |
| 打開選人視窗 | < 100ms | 94ms | 117–140ms |
| 捲動 | 60fps | 32fps，最長一格 183ms | 55fps，最長一格 152ms |

解讀：
- 這台機器沒有 GPU，瀏覽器的 WebGL 是軟體繪圖，所以捲動 fps 和 iPhone 不能直接比。冷啟動、切換分頁、選人在這種條件下都在目標附近。
- 選人視窗在 WebKit 超過 100ms，主要花在底部面板第一次排版。已經把搜尋比對改成每個名字只正規化一次。
- 捲動時最長的那一格，發生在第一次畫出新的中文字的時候：Web 版的中文字型是執行時才從 Google Fonts 下載的。

下一步（需要實機）：
- 原生 App 在 Hans 的 iPhone、Android 上各量一次。用 profile 模式和 DevTools 量冷啟動與捲動。
- iPhone Safari 開 Web 版量一次。如果中文字型造成卡頓：預先載入常用字的子集字型，或在啟動畫面先暖字型。

## 數據與監控

- 行為分析：Firebase Analytics（GA4），三平台。user property 帶 `church_id`，看各教會活躍度、DAU/MAU、留存、功能使用。不追蹤跨 App，不需 ATT。
- 平台統計：每日排程 Cloud Function 寫 `stats/{date}`：
  - `count()` 聚合：使用者、教會（依 status）、members、rosters。
  - Cloud Monitoring API：前一日 Firestore reads/writes/deletes、儲存量、Functions 呼叫次數。
  - 費用：用量 × 公開單價估算，不開 billing export（要 BigQuery，多一套東西）。
  - 限制：Firestore 無法拆出每間教會的讀寫量；重度教會靠 GA4 活躍度與後端既有計數（照片額度）推估。
- 錯誤 log：
  - App：Crashlytics（當機、未處理例外）。
  - Web：Crashlytics 不支援，錯誤送到一支 function 寫入 Cloud Logging。
  - Cloud Functions：直接寫 Cloud Logging，Error Reporting 自動分組。
- 通知：Crashlytics 與 Error Reporting 的「新錯誤類型」email，寄到專案擁有者的 Google 帳號，不用開新帳號。
- 檢視：Hans 後台加「統計」頁，畫每日快照趨勢；行為與錯誤細節連到 Firebase / GCP console。
- 隱私：log 只記 uid、cid、錯誤堆疊，不記姓名、email、服事表內容；log 保留預設 30 天。分析不提供關閉開關，隱私權政策與商店隱私標籤揭露。

## 授權

- 程式碼：MIT（self-host 與馬大別忙皆同）。
- 「馬大別忙」名稱與圖示**不在 MIT 授權範圍**，fork 須改名；README 附不具法律效力的期望：「希望每間教會免費使用，請勿包裝成商業產品販售」。
- 暫不接受 PR（只收 issue），所以不需要 CLA。商標註冊上架前再決定。

## Repo 與 self-host

- 同一個 repo。馬大別忙在 **orphan branch** 開發（與現有歷史無關）。
- 切換步驟：
  1. 發最後一版 self-host：`release_check_service.dart` 的網址、安裝精靈、Cloud Shell 按鈕改指 `selfhost` 分支。
  2. 現有 `main` 歷史改名 `selfhost`；orphan branch 成為新 `main`。
  3. README 與 vocus 文章連結改到 `selfhost`。
- 未更新的舊網站：收不到更新通知（讀取失敗時靜默回 null）；舊精靈 `pull --ff-only` 失敗，繼續用舊版，安全。
- 切換後 self-host **完全不維護**，README 註明凍結。

## 上架

- Apple 個人帳號（賣家顯示法定姓名），US$99/年，**送審前才付**；開發期用免費 Apple ID 在自己手機測。
- Google 個人帳號 US$25；首次上架前封閉測試 12 人 × 14 天。
- iOS 用 Mac build。
- 網域上架前才買；之前用 `*.web.app`。
- 隱私權政策、服務條款：Claude 寫草稿，找懂個資法的人審（台灣個資法、香港 PDPO、馬來西亞 PDPA）。

## 里程碑（有空才做，無期限）

1. **M1**：orphan branch、`dev` 專案；tenant 資料模型、rules、跨教會隔離測試
2. **M2**：元件庫（依 `docs/design-principles.md`）；Google 登入與 email 註冊、email 驗證、同名檢查、membership、邀請、退出教會、教會 logo、帳號刪除、後台（含統計頁）；錯誤 log、每日統計快照；效能測試資料與量測
3. **M3**：匯入工具（含 `auth:export`/`auth:import` 保留密碼 hash），自家教會搬進 `prod` dogfood；i18n
4. **M4**：iOS/Android App、推播、Crashlytics、GA4、Google 封閉測試
5. **M5**：打賞與訂閱、照片辨識限額
6. **M6**：landing page、法律文件、行事曆 OAuth（未驗證狀態）
7. **M7**：買網域、送 Google OAuth 驗證、付 Apple 年費、Sign in with Apple、送審；執行 repo 切換

## 已接受的風險

1. 不設用量上限：單一教會暴衝會吃掉共用免費額度，Blaze 會產生帳單；budget alert 只通知不停用。
2. 行事曆 OAuth 在驗證通過前：管理員連接時看到警告畫面，約 100 間教會上限。
3. 無功能差異的訂閱可能被 Apple 依 3.1.2(a) 退件。
4. 個資責任在 Hans 個人，涉及三地法規。
5. 一次發布加上時間零碎：其他教會要等很久。
6. Android 換 icon 要用 activity-alias；「馬大別忙」商標與商店重名尚未查。

## 參考數據（2026-10-02 量測，church-staff-pwa）

- 53 位使用者、146 份服事表、1.47 MB。
- 每日 reads 中位數約 130、p90 約 1,170（高峰多為開發期間）；writes 最高 159/天。
- 估計 Spark 免費額度可撐約 70–100 間教會。
