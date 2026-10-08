# 資料模型與權限規格

這份是規格，`firestore.rules` 是它的實作，`firestore-tests/rules.test.js` 是驗收。
三者不一致時以這份為準，再回頭改另外兩個。之後若搬離 Firestore，照這份重寫權限。

## 路徑

| 路徑 | 內容 |
|---|---|
| `users/{uid}` | 全域個資：`name`、`email`、`locale`、`fcm`（`{deviceId: token}`）、`createdAt`、`updatedAt` |
| `churches/{cid}` | `name`、`nameKey`（正規化後的名稱，同名檢查用）、`status`（`active` / `suspended` / `deleted`）、`createdBy`、`createdAt`、`deletedAt`、`logoVersion`（logo 的 Storage generation）、`homeName`（主畫面名稱，選填，最多 8 字） |
| `churches/{cid}/members/{uid}` | `uid`（= doc id，collection group 查詢用）、`name`、`email`、`role`、`groups`、`zones`、`zoneTypes`、`notificationPrefs`、`joinedAt` |
| `churches/{cid}/rosters/{id}` | 服事表，`type` 是聚會別 ID，`dateKey` 是 `YYYY-MM-DD`，id 是 `<dateKey>_<type>`。活動的服事表（掛在行事曆活動上）的 id 是 `ev_<活動 id>`，沒有 `type`，改成 `kind: 'event'`、`eventId`、`title`（活動名稱）、`dateKey` 與 `endDateKey`（活動的第一天、最後一天，UTC+8）。名稱和日期由 `calendarWrite`（在 App 改的）和 `syncEventRosters`（一天三次，含 18:30，在 Google 日曆直接改的）照活動更新。另外記 `calendarId`（活動在哪本行事曆）、重複活動的 `recurringEventId` 與 `originalStart`，建立時 App 寫，之後只有後端改。活動刪掉時後端加上 `cancelledAt`（取消：不顯示、不提醒，留著給復原；30 天內活動回來就恢復，過了就刪掉），只有後端寫這個欄位 |
| `churches/{cid}/pendingMembers/{舊 uid}` | 從舊版搬來、還沒登入的同工：`name`、`email`、`emailHash`、`role`、`groups`、`zones`、`zoneTypes`。後端建立，管理員可以刪 |
| `pendingIndex/{email 的 SHA-256}` | 只有後端讀寫：`churches`（教會 id → 待認領同工 id） |
| `invites/{邀請碼}` | `cid`、`churchName`、`expiresAt`（31 天內）、`revoked`、`createdBy`、`createdAt`、`zoneTypes`（選填，加入後屬於的牧區，最多 20 個；加入時只留教會還有的聚會別，不帶服事項目）。管理員建立、撤回，加入經 `redeemInvite` |
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
| `fundingPayments/{商店_交易 id}` | 只有後端讀寫：`store`（`apple` / `google` / `newebpay`）、`productId`（網站付款是 `web_once`）、`amount`、`currency`、`amountTwd`、`refundedTwd`、`month`、`at`。id 是 `apple_<交易 id>`、`google_<訂單 id>`、`newebpay_<訂單號碼>`。退款比付款先到時，先只有 `store`、`refundShare`（退了幾成），付款到了再補上其他欄位。不記帳號或名字 |
| `newebpayOrders/{訂單號碼}` | 只有後端讀寫：網站線上支持（藍新金流）的訂單。訂單號碼（MerchantOrderNo）由後端產生，`YYYYMMDD` 加 12 個十六進位字元。開單時 `amount`（新台幣整數，30–10,000）、`status`（`pending`）、`createdAt`、`expiresAt`；付款通知到了改成 `status: paid`，加上 `tradeNo`（藍新交易序號）、`paymentType`、`paidAt`，拿掉 `expiresAt`。沒付款的過了 `expiresAt`（3 天）就刪掉。不記卡號、email、IP 或名字 |
| `platform/newebpayRate` | 只有後端讀寫：這個小時開了幾張藍新訂單，`hour`（UTC 的 `YYYY-MM-DDTHH`）、`count`。全站每小時最多 60 張 |

- 一個教會的所有資料都在 `churches/{cid}` 底下，可以整棵匯出。
- 推播 token 放在 `users/{uid}`，只有本人和 Cloud Functions 讀得到。self-host 版的 roster editor 讀得到全部 token，這裡改掉了。
- 教會內顯示的名字來自 member doc，不讀 `users/{uid}`。
- 上面的「字」都是[長度上限](#長度上限)說的字。

## 長度上限

文字欄位的上限算「字」：人看到的一個字（grapheme cluster），「🙏」「👨‍👩‍👧」「🇹🇼」都是一個字。App 的輸入框（Flutter `maxLength` 本來就這樣算）、`MemoryBackend`、Cloud Functions（`Intl.Segmenter`）都這樣數。

| 上限 | 字 | 誰檢查 | 規則的 UTF-16 上限 |
|---|---|---|---|
| 教會名稱 `churchName` | 60 | App、Functions（建立、搬家、改名） | — |
| 主畫面名稱 `homeName` | 8 | App | 32 |
| 教會連結標題 `linkTitle` | 30 | App；抓來的內容由 Functions 截斷 | 120 |
| 教會連結敘述 `linkBody` | 120 | App；抓來的內容由 Functions 截斷 | 480 |
| 雲端費用項目 `costName` | 40 | App、Functions | — |
| 個人名字 `profileName`（個人資料、同工名單上的名字） | 40 | App（Google 帳號的名字也截到 40 字）；Functions 從別處抄來的名字（登入名稱、搬家檔、個人資料）截到 40 字 | 160 |
| 活動的服事表名稱 `eventTitle` | 200 | App、Functions 從行事曆抄來時截斷 | 800 |

`firestore.rules` 的 `size()` 算的是 UTF-16 code unit，數不了字，所以規則只擋濫用：上限 × 4。Functions 數字之前也先擋同一個 × 4。一般的字（中文 1 單位、emoji 2–4 單位）到上限都過得了；一個字超過 4 單位的（組合的家庭 emoji、帶 tag 的旗子）可能字數沒到就先碰到 × 4。介於上限和 × 4 之間的直接寫入規則會放行，這段由 App 擋。

其他上限每一邊單位都一樣：網址（教會連結、內容來源、外部通知）500 個 UTF-16 單位，外部通知的密鑰 16–200 個可見 ASCII 字元，服事最多 20 種。

數字在三個地方：`app/lib/domain/limits.dart`、`functions/src/limits.ts`、`firestore.rules`。`functions/test/limits.test.ts`（CI 的 backend job）讀這三個檔，任何一個數字對不上就失敗；規則裡新加一個 `size() <=` 也要在那裡登記。

線上支持的金額（30–10,000 元）只有網站和 Functions 檢查，不在 App 裡：`functions/src/limits.ts` 的 `SUPPORT_AMOUNT` 和 `landing/support.html` 金額欄位的 `min`、`max`，同一個測試比對。

比對教會名稱、搜尋同工的正規化（`app/lib/domain/text.dart` ↔ `functions/src/text.ts`）和數字的方法，兩邊的測試都跑 `testdata/text_rules.json` 的每一列；要改規則先在那裡加一列。

## 角色與群組

- `role`：`admin`、`leader`、`staff`、`member`。只有 `admin` 有權限上的意義，其他是身分標示。
- `groups`：`roster-editors`、`calendar-editors`。可同時擁有多個；admin 視同全部都有。
- `zones`：同工屬於的牧區（聚會別），每個帶他在那裡的服事項目，可以是空的。服事表分頁只顯示自己的牧區，admin 和 roster-editors 看全部；這只是讓畫面清爽，規則照樣讓所有同工讀所有服事表。
- `zoneTypes`：`zones` 攤平後的聚會別 ID 清單，也就是自己的牧區。服事表分頁照它顯示，也決定 roster editor 能改哪幾種服事表；規則讀不到 `zones` 裡面，所以另存一份。

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
| 寫活動的服事表 | admin 和所有 roster-editors，不看牧區。一般服事表和活動的服事表不能互相改過去；取消了的不能再改，只能刪 |
| 寫設定 | admin；`services` 的 `ids` 只增不減，不能刪；`calendar`、`linkContent`、`webhook` 只有 Cloud Functions 能寫 |
| 讀寫 `users/{uid}` | 本人（限上列欄位）；刪除由 Cloud Functions 處理 |

## 交給 Cloud Functions 的（M2）

規則做不到的檢查都放在後端：建立教會（email 已驗證、`nameKey` 不重複）、邀請加入、帳號刪除、平台後台（改名、轉移管理員、停用）。

在某間教會裡做事的 Function 都先經過 `functions/src/access.ts`，判斷和上表的規則一樣，依序：

1. 不是這間教會的同工 → `permission-denied`（reason `permissionDenied`），不透露教會的狀態。
2. 教會停用（`suspended` 或 `deleted`）→ `failed-precondition`、reason `churchClosed`，不管這位同工原本能做什麼；App 顯示「這間教會已停用」。只有還原教會（`restoreChurch`）放行停用中的教會，而且只還原 30 天內刪除的；營運者停用的、刪除超過 30 天的一樣是 `churchClosed`。
3. 權限不夠 → `permissionDenied`。等級有同工、權限群組（admin 都算）、admin，以及 roster editor：教會有過這個聚會別（`settings/services` 的 `ids`），而且是 admin 或在 roster-editors 裡、`zoneTypes` 有它。

例外：邀請停用教會的回 `inviteInvalid`，教會預覽回 `notFound`（給還不是同工的人看）；排程和觸發器遇到停用的教會直接略過。Firestore 直接讀寫被規則擋下時，規則分不出原因，一律是 permission-denied。

App 看不到這個差別：在一間教會裡做的事，不管是 Firestore、Storage 還是 Function，都在那間教會的 `ChurchData`（`app/lib/data/backend.dart`）上，被擋下一律是 `CloudException`。規則擋下的讀寫和 Function 一樣是 `permissionDenied`，所以畫面說的是同一句「沒有權限」。

`previewInvite` 不用登入：邀請連結開的登入頁要能顯示是哪間教會邀請。沒登入時只回教會名稱；登入後才回教會 id 和到期日。邀請碼本身就是秘密，拿到碼就能註冊加入，所以這不多露出什麼。

## Storage

| 路徑 | 誰可以 |
|---|---|
| `churches/{cid}/logo.png` | 同工讀；管理員寫，1MB 以內的圖片 |
| `churches/{cid}/logo-{版本}-*.png` | 只有後端（主畫面 icon，經教會頁 Function 提供） |
| `moves/{uid}/*` | 只有上傳者本人讀寫，20MB 以內（搬家檔，用完即刪） |
