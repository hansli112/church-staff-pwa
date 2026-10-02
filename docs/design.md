# 馬大別忙 · 設計決策

> 2026-10-02 與 Hans 逐項確認。來源：church-staff-pwa（self-host 版）改版為多教會代管服務。

## 產品

- 代管、多教會共用的**同工工具**（不含會友）。單一 App「馬大別忙」（驚嘆號可有可無），教會 logo 在 App 內顯示。
- 平台：iOS、Android、Web（PWA），同一份 Flutter code。
- 語言：i18n 架構（ARB）。繁中先出；英文、簡中之後補。
- 營運：Hans 個人。不主動拓展，有人問就給用；已知有台灣、香港、馬來西亞詢問。
- 發布：**全部做完一次發布**，不分階段。

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

- 自由註冊，申請人須驗證 email。
- 同名檢查：名稱正規化（空白、全半形、大小寫）後完全相同就提醒並擋下，附聯絡連結。被搶註時由 Hans 在後台處理。
- 不設教會數量或用量上限；非教會單位也可使用（服務條款寫明為教會設計）。
- Hans 的後台：教會改名、轉移管理員、停用教會。
- 帳號刪除（Apple 5.1.1(v)）：App 內自行刪除，刪 Auth、`users/{uid}` 與所有 membership；服事表保留姓名文字；唯一管理員須先交接；教會刪除後保留 30 天可還原。

## 功能（第一版）

- 核心：登入、同工、服事表。
- 推播：FCM（iOS 需 APNs）。
- 行事曆：Google OAuth，**In production 但未驗證**（有警告畫面、終身約 100 位授權者上限）。管理員連接並選日曆；refresh token 加密存後端；讀寫皆由後端代理並快取；授權失效時顯示重新連接。Scope：`calendar.events`、`calendar.calendarlist.readonly`。
- 照片辨識：Hans 付費，Gemini **付費 tier**；每教會每月 30 張；全站每月上限 US$20，超過自動關閉。
- 不做：LINE 通知、每日靈糧。

## 金流

- 只做「支持平台」，不經手教會奉獻。
- 一次性打賞（IAP consumable）＋訂閱（回饋：只有自己看得到的徽章、可換 App icon）。
- 原生 `in_app_purchase`，支持者狀態**只在裝置上判斷**，無後端、不同步 Firestore。
- 不做感謝名單；Web 版不放贊助連結。

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
2. **M2**：註冊、email 驗證、同名檢查、membership、邀請、帳號刪除、後台
3. **M3**：匯入工具（含 `auth:export`/`auth:import` 保留密碼 hash），自家教會搬進 `prod` dogfood；i18n
4. **M4**：iOS/Android App、推播、Google 封閉測試
5. **M5**：打賞與訂閱、照片辨識限額
6. **M6**：landing page、法律文件、行事曆 OAuth
7. **M7**：買網域、付 Apple 年費、送審；執行 repo 切換

## 已接受的風險

1. 不設用量上限：單一教會暴衝會吃掉共用免費額度，Blaze 會產生帳單；budget alert 只通知不停用。
2. 行事曆 OAuth 未驗證：約 100 間教會上限。
3. 無功能差異的訂閱可能被 Apple 依 3.1.2(a) 退件。
4. 個資責任在 Hans 個人，涉及三地法規。
5. 一次發布加上時間零碎：其他教會要等很久。
6. Android 換 icon 要用 activity-alias；「馬大別忙」商標與商店重名尚未查。

## 參考數據（2026-10-02 量測，church-staff-pwa）

- 53 位使用者、146 份服事表、1.47 MB。
- 每日 reads 中位數約 130、p90 約 1,170（高峰多為開發期間）；writes 最高 159/天。
- 估計 Spark 免費額度可撐約 70–100 間教會。
