# 資料模型與權限規格

這份是規格，`firestore.rules` 是它的實作，`firestore-tests/rules.test.js` 是驗收。
三者不一致時以這份為準，再回頭改另外兩個。之後若搬離 Firestore，照這份重寫權限。

## 路徑

| 路徑 | 內容 |
|---|---|
| `users/{uid}` | 全域個資：`name`、`email`、`locale`、`fcm`（`{deviceId: token}`）、`createdAt`、`updatedAt` |
| `churches/{cid}` | `name`、`nameKey`（正規化後的名稱，同名檢查用）、`status`（`active` / `suspended` / `deleted`）、`createdBy`、`createdAt`、`deletedAt`、`logoVersion`（logo 的 Storage generation）、`homeName`（主畫面名稱，選填，最多 8 字） |
| `churches/{cid}/members/{uid}` | `uid`（= doc id，collection group 查詢用）、`name`、`email`、`role`、`groups`、`zones`、`zoneTypes`、`notificationPrefs`、`joinedAt` |
| `churches/{cid}/rosters/{id}` | 服事表，`type` 是聚會別 ID，`dateKey` 是 `YYYY-MM-DD` |
| `churches/{cid}/pendingMembers/{舊 uid}` | 從舊版搬來、還沒登入的同工：`name`、`email`、`emailHash`、`role`、`groups`、`zones`、`zoneTypes`。後端建立，管理員可以刪 |
| `pendingIndex/{email 的 SHA-256}` | 只有後端讀寫：`churches`（教會 id → 待認領同工 id） |
| `churches/{cid}/staff_orders/{type}` | 各聚會別的同工排序 |
| `churches/{cid}/settings/{doc}` | `services`（聚會別，`ids` 只增不減）、`roster_templates` 等 |
| `churches/{cid}/settings/link` | 教會連結：`title`（1–30 字）、`body`（最多 120 字）、`url`（限 `https`）；`source`（每日內容來源，`https`）與 `fetchMinute`（每天抓取時間，台北時間午夜後的分鐘數，15 分鐘為單位）只能經 `setLinkSource` 設定 |
| `churches/{cid}/settings/linkContent` | 只有後端寫：最近抓到的 `title`、`body`、`link`、`source`、`fetchedAt`，以及上次失敗的 `error`、`errorStatus`、`errorAt` |
| `linkSources/{cid}` | 只有後端讀寫：內容來源的排程，`source`、`fetchMinute`、`nextAt`、`lastDay` |
| `churches/{cid}/settings/webhook` | 外部通知，只有後端寫、只有管理員讀：`url`（`https`）、`events`（`calendar`、`roster`）、`lastDelivery`（`at`、`event`、`ok`、`status`、`error`） |
| `webhookSecrets/{cid}` | 只有後端讀寫：外部通知的密鑰，用行事曆 token 的金鑰以 AES-256-GCM 加密 |
| `webhookOutbox/{cid}/rosterChanges/{eventId}` | 只有後端讀寫：還沒送出的服事表異動，每 5 分鐘合併成一則外部通知後刪除 |
| `platform/funding` | 雲端費用進度，誰都讀得到（網站的支持頁不用登入）、只有後端寫：`month`（`YYYY-MM`）、`target`、`received`、`carried`、`monthsLeft`（金額都是新台幣整數）、`updatedAt` |
| `platform/fundingCosts` | 只有後端讀寫（營運者經 `adminSetFundingCosts` 改）：`items`（`name`、`amount`、`currency` 為 `TWD` / `USD`、`per` 為 `month` / `year`） |
| `platform/fxRates` | 只有後端讀寫：`rates`（一元台幣換多少外幣）、`fetchedOn` |
| `fundingMonths/{YYYY-MM}` | 只有後端讀寫：該月 `received`、`target`（月份過了就不再改） |
| `fundingPayments/{商店_交易 id}` | 只有後端讀寫：`store`、`productId`、`amount`、`currency`、`amountTwd`、`refundedTwd`、`month`、`at`。退款比付款先到時，先只有 `store`、`refundShare`（退了幾成），付款到了再補上其他欄位。不記帳號或名字 |

- 一個教會的所有資料都在 `churches/{cid}` 底下，可以整棵匯出。
- 推播 token 放在 `users/{uid}`，只有本人和 Cloud Functions 讀得到。self-host 版的 roster editor 讀得到全部 token，這裡改掉了。
- 教會內顯示的名字來自 member doc，不讀 `users/{uid}`。

## 角色與群組

- `role`：`admin`、`leader`、`staff`、`member`。只有 `admin` 有權限上的意義，其他是身分標示。
- `groups`：`roster-editors`、`calendar-editors`。可同時擁有多個；admin 視同全部都有。
- `zoneTypes`：`zones` 攤平後的聚會別 ID 清單，決定 roster editor 能改哪幾種服事表。

## 權限

「同工」= 該教會有 member doc，**且**教會 `status == 'active'`。所有判斷只看路徑裡那間教會。

| 動作 | 誰可以 |
|---|---|
| 讀 `churches/{cid}` | 有 member doc 的人（停用中也可以，用來顯示「教會已停用」） |
| 建立、改名、改狀態、刪除教會 | 只有 Cloud Functions |
| 改主畫面名稱（`homeName`） | admin，只能動這個欄位 |
| 查自己屬於哪些教會 | 本人（collection group `members`，`where uid == 自己`） |
| 讀 member | 本人、roster-editors、admin |
| 讀待認領同工 | roster-editors、admin；只有 admin 能刪，其他寫入都是後端 |
| 加入教會（建立 member） | 只有 Cloud Functions（邀請） |
| 改 member | admin（不能改 `uid`、不能把自己降級）；本人只能改 `notificationPrefs` |
| 刪 member | admin 刪別人；非 admin 可以自己退出。admin 要先被別的 admin 降級才能走 |
| 讀服事表、排序、設定 | 同工 |
| 寫服事表、排序 | admin（任何已設定的聚會別）；roster-editors（只限自己 `zoneTypes` 裡的聚會別，移動時新舊聚會別都要有） |
| 寫設定 | admin；`services` 的 `ids` 只增不減，不能刪；`calendar`、`linkContent`、`webhook` 只有 Cloud Functions 能寫 |
| 讀寫 `users/{uid}` | 本人（限上列欄位）；刪除由 Cloud Functions 處理 |

## 交給 Cloud Functions 的（M2）

規則做不到的檢查都放在後端：建立教會（email 已驗證、`nameKey` 不重複）、邀請加入、帳號刪除、平台後台（改名、轉移管理員、停用）。

`previewInvite` 不用登入：邀請連結開的登入頁要能顯示是哪間教會邀請。沒登入時只回教會名稱；登入後才回教會 id 和到期日。邀請碼本身就是秘密，拿到碼就能註冊加入，所以這不多露出什麼。

## Storage

| 路徑 | 誰可以 |
|---|---|
| `churches/{cid}/logo.png` | 同工讀；管理員寫，1MB 以內的圖片 |
| `churches/{cid}/logo-{版本}-*.png` | 只有後端（主畫面 icon，經教會頁 Function 提供） |
| `moves/{uid}/*` | 只有上傳者本人讀寫，20MB 以內（搬家檔，用完即刪） |
