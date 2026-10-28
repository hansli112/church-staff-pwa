# 資料模型與權限規格

這份是規格，`firestore.rules` 是它的實作，`firestore-tests/rules.test.js` 是驗收。
三者不一致時以這份為準，再回頭改另外兩個。之後若搬離 Firestore，照這份重寫權限。

## 路徑

| 路徑 | 內容 |
|---|---|
| `users/{uid}` | 全域個資：`name`、`email`、`locale`（自己選的語言，跟隨系統時沒有）、`appLocale`（App 實際顯示的語言：推播照它寫；建教會、搬家沒說語言時，預設內容和「待定」也照它）、`fcm`（`{deviceId: token}`）、`photoAiConsentAt`（同意照片辨識把照片和同工名單送到 Gemini 的時間，只能本人寫）、`notificationsSeenAt`（`{cid: 看過的最新一則通知的時間}`，通知列表的已讀，到毫秒；只能本人寫，最多 100 間）、`createdAt`、`updatedAt` |
| `users/{uid}/notifications/{id}` | 通知列表（#89），只有本人讀、只有後端寫：每一則推播（`functions/src/push.ts` 的 `notifyMembers`）都替收件的同工存一筆，關掉那種通知的也存，只是不推播。`cid`、`kind`（通知種類）、`title`、`body`（照收件人的 `appLocale`）、`link`（App 路由，和推播點開的一樣）、`at`（送出時間，後端的時間）。30 天後每天清掉（`forgetOldNotifications`）；退出或被移出教會時刪掉那間教會的（`onMemberDeleted`），刪帳號時整個刪掉 |
| `churches/{cid}` | `attendanceSince`（回報人數開的那天，`YYYY-MM-DD`；關著沒有這個欄位，#85）、`joinRequestsClosed`（`true`：不開放申請加入；開著沒有這個欄位，#88）、`name`、`nameKey`（正規化後的名稱，同名檢查用）、`status`（`active` / `suspended` / `deleted`）、`createdBy`、`createdAt`、`deletedAt`、`logoVersion`（logo 的 Storage generation）、`homeName`（主畫面名稱，選填，最多 8 字）、`timeZone`（教會的時區，IANA 名稱，限 `functions/src/timeZones.ts` 的 16 個；建立時照建立者手機的時區，之後管理員經 `setChurchTimeZone` 改；沒有這個欄位的是 #73 之前建立的，一律當 `Asia/Taipei`） |
| `churches/{cid}/members/{uid}` | `uid`（= doc id，collection group 查詢用）、`name`、`email`、`role`、`groups`、`zones`（每個 `{serviceType, duties, smallGroups}`）、`zoneTypes`、`identities`（身分，見〈角色與群組〉）、`leadTypes`、`leadMinistries`、`ministries`、`leadSmallGroups`、`smallGroups`、`notificationPrefs`（`muted`：關掉的通知種類；`reminderTiming`：服事提醒的時間，`weekly`／`dayBefore`／`both`，沒有就是 `weekly`）、`joinedAt` |
| `churches/{cid}/rosters/{id}` | 服事表，`type` 是聚會別 ID，`dateKey` 是 `YYYY-MM-DD`，id 是 `<dateKey>_<type>`。活動的服事表（掛在行事曆活動上）的 id 是 `ev_<活動 id>`，沒有 `type`，改成 `kind: 'event'`、`eventId`、`title`（活動名稱）、`dateKey` 與 `endDateKey`（活動的第一天、最後一天，教會的時區）。名稱和日期由 `calendarWrite`（在 App 改的）和 `syncEventRosters`（各教會當地每天 6:30、12:30、18:30，在 Google 日曆直接改的；教會改時區時也立刻照新時區重算一次，不發通知）照活動更新。另外記 `group`（活動屬於哪個群組，`service:<id>` 或 `ministry:<id>`，全教會的沒有這個欄位；#84）、`calendarId`（活動在哪本行事曆）、重複活動的 `recurringEventId` 與 `originalStart`，建立時 App 寫，之後只有後端改。活動刪掉時後端加上 `cancelledAt`（取消：不顯示、不提醒，留著給復原；30 天內活動回來就恢復，過了就刪掉），只有後端寫這個欄位 |
| `churches/{cid}/smallGroups/{id}` | 小組（#85）：`name`、`service`（屬於哪個聚會）、`weekday`（1 是週一…7 是週日）、`every`（1 每週、2 隔週）、`startsOn`（從這天起聚會，要是 `weekday` 那天；隔週照它算哪幾週）。後三個只有回報人數用到，可以沒有。只有後端寫（`editSmallGroup`），同工都讀得到 |
| `churches/{cid}/settings/smallGroups` | 只有後端寫：`ids`，用過的小組 ID，只增不減 |
| `churches/{cid}/attendance/{群組}` | 回報人數（#85），`{群組}` 是 `service:<id>` 或 `small:<id>`：`pauses`（暫停，每段 `{from, until}`：從 `from` 到 `until` 前一天不算；結束了也留著，那幾週才不會變成「未填」，最多 50 段）。底下 `days/{dateKey}` 是那次聚會的人數：`count`（0–100000）加選填的 `note`（最多 200 字），或 `none: true`（這次沒聚會）；`by` 是填的人 |
| `churches/{cid}/pendingMembers/{舊 uid}` | 從舊版搬來、還沒登入的同工：`name`、`email`、`emailHash`、`role`、`groups`、`zones`、`zoneTypes`、`notificationPrefs`、`rosterIds`（搬家時記下有他名字的服事表）。後端建立，管理員可以刪；認領或合併時偏好與小組併入同工，只有 `rosterIds` 那幾天改連到新帳號 |
| `churches/{cid}/joinRequests/{uid}` | 申請加入（#88）：`uid`、`name`、`email`（申請時帳號的）、`note`（選填，最多 100 字）、`createdAt`、`rejectedAt`（管理員拒絕的時間）。只有後端寫（`requestToJoin`、`withdrawJoinRequest`、`answerJoinRequest`），只有 admin 讀得到；申請的人從 `churchPreview` 知道自己的申請怎麼了。`createdAt` 滿 30 天就算沒有，每天清掉 |
| `churches/{cid}/joinRequestPushes/{uid}` | 只有後端讀寫：`uid`、`at`（上次為這個人的申請推播給管理員的時間）。同一個人一天內只推播一次，取消再申請也不會一直響；超過一天的每天清掉 |
| `pendingIndex/{email 的 SHA-256}` | 只有後端讀寫：`churches`（教會 id → 待認領同工 id） |
| `invites/{邀請碼}` | `cid`、`churchName`、`expiresAt`（31 天內）、`revoked`、`createdBy`、`createdAt`、`zoneTypes`（選填，加入後屬於的牧區，最多 20 個；加入時只留教會還有的聚會別，不帶服事項目）。管理員建立、撤回，加入經 `redeemInvite` |
| `churches/{cid}/staff_orders/{type}` | 各聚會別的同工排序 |
| `churches/{cid}/settings/{doc}` | `services`（聚會別，`ids` 只增不減）、`ministries`（事工：`ministries` 每個 `{id, name, duties: [{service, duty}]}`，最多 50 個；`ids` 只增不減）、`roster_templates` 等 |
| `churches/{cid}/settings/link` | 教會連結：`title`（1–30 字）、`body`（最多 120 字）、`url`（限 `https`）；`source`（每日內容來源，`https`）與 `fetchMinute`（每天抓取時間，教會時區午夜後的分鐘數，15 分鐘為單位）只能經 `setLinkSource` 設定 |
| `churches/{cid}/settings/linkContent` | 只有後端寫，兩種形狀擇一：成功時 `source`、`date`（教會的今天，`YYYY-MM-DD`）、`title`、`body`、`link`、`fetchedAt`；失敗時只有 `source`、`error`、`errorStatus`、`errorAt`，不保留之前的內容 |
| `linkSources/{cid}` | 只有後端讀寫：內容來源的排程，`source`、`fetchMinute`、`epoch`（設定每變一次就換，晚到的結果不能寫回）、`nextAt`、`lastAttemptDay`（排程這天試過了）、`lastDay`（最後成功的那天）、`attemptId`（抓取中才有） |
| `churches/{cid}/settings/webhook` | 外部通知，只有後端寫、只有管理員讀：`url`（`https`）、`events`（`calendar`、`roster`）、`lastDelivery`（`at`、`event`、`ok`、`status`、`error`） |
| `webhookSecrets/{cid}` | 只有後端讀寫：外部通知的密鑰，用行事曆 token 的金鑰以 AES-256-GCM 加密 |
| `webhookOutbox/{cid}/rosterChanges/{eventId}` | 只有後端讀寫：還沒送出的服事表異動，每 5 分鐘合併成一則外部通知後刪除 |
| `plannedPushes/{cid}_{rosterId}_{uid}` | 排好幾週（#90）等著「通知同工」的服事表異動，只有後端寫：在那頁排（`via: 'plan'`）時，每個被排進或移出的人（排的人自己除外）一筆。`cid`、`rosterId`、`uid`、`roles`（第一筆之前這個人在那天的服事項目；之後照常通知過的、他自己改的、匯入的異動會併進來）、`dateKey`、`serviceId`、`serviceName`、`sendAt`（還沒按是 `null`；夜裡按的是 7:00）。按「通知同工」（`notifyPlanned`，能排這個聚會的人）時，那個聚會 `sendAt == null` 的每人合成一則：比對當下的服事表，只說淨變了什麼，過去的日子不說，送完刪除。這個人又變回原本的樣子（排進又移出，或照常通知過）就刪掉；每小時也刪掉日子在各地都已過去的。讀名單的人（admin、行政、負責人）查得到自己教會的，用來決定按鈕能不能按 |
| `heldPushes/{cid}_{rosterId}_{uid}` | 只有後端讀寫：教會當地 22:00–7:00 的服事表異動推播，等 7:00 再送。`cid`、`rosterId`、`uid`、`roles`（第一筆延後的異動之前，這個人在那天的服事項目；他自己改的、匯入的異動會併進來，不算消息）、`dateKey`（那時的日期，活動改期看得出來）、`serviceId`、`serviceName`、`event`、`sendAt`。送出時比對當下的服事表，只說這段時間淨變了什麼，送完刪除。7:00 後、排程送出前又有異動時，兩者合成一則一起送 |
| `platform/funding` | 雲端費用進度，誰都讀得到（網站的支持頁不用登入）、只有後端寫：`month`（`YYYY-MM`）、`target`、`received`、`carried`、`monthsLeft`（金額都是新台幣整數）、`costs`（每一項費用公開給大家看：`name`、`names`（有填才有）、`perMonth` 每月新台幣、`per`；`target` 是 `perMonth` 加總；沒有匯率時沿用上一次的）、`updatedAt` |
| `platform/app` | 商店 App 最低能用的 build number，誰都讀得到（沒登入也要擋）、App 不能寫，營運者在 Console 或 REST 改：`minBuild`（`android`、`ios`；沒有或 0 就不擋）。比它舊的 App 整個畫面要求更新（`docs/firebase-setup.md`〈要求更新手機 App〉） |
| `platform/fundingCosts` | 只有後端讀寫（營運者經 `adminSetFundingCosts` 改）：`items`（`name` 繁中名稱、`names` 其他語言的名稱（`en`、`zh-Hans`、`ja`、`ko`，選填，沒填的不存）、`amount`、`currency` 為 `TWD` / `USD`、`per` 為 `month` / `year`）。支持頁（網站和 App）照語言顯示：簡中沒填顯示繁中，其他語言沒填顯示英文，英文也沒填顯示繁中 |
| `platform/fxRates` | 只有後端讀寫：`rates`（一元台幣換多少外幣）、`fetchedOn` |
| `fundingMonths/{YYYY-MM}` | 只有後端讀寫：該月 `received`、`target`（月份過了就不再改） |
| `fundingPayments/{商店_交易 id}` | 只有後端讀寫：`store`（`apple` / `google` / `ecpay`）、`productId`（網站付款是 `web_once`）、`amount`、`currency`、`amountTwd`、`refundedTwd`、`month`、`at`。id 是 `apple_<交易 id>`、`google_<訂單 id>`、`ecpay_<訂單號碼>`。退款比付款先到時，先只有 `store`、`refundShare`（退了幾成），付款到了再補上其他欄位。綠界後台退款不會通知後端，由營運者在平台後台填訂單號碼（`adminRefundOnlineSupport`）整筆扣回，可復原。不記帳號或名字 |
| `ecpayOrders/{訂單號碼}` | 只有後端讀寫：網站線上支持（綠界）的訂單。訂單號碼（MerchantTradeNo）由後端產生，`YYYYMMDD` 加 12 個十六進位字元。開單時 `amount`（新台幣整數，30–1,000）、`status`（`pending`）、`createdAt`、`expiresAt`；付款通知到了改成 `status: paid`，加上 `tradeNo`（綠界交易編號）、`paymentType`、`paidAt`，拿掉 `expiresAt`。沒付款的過了 `expiresAt`（3 天）就刪掉。不記卡號、email 或名字 |
| `platform/ecpayRate` | 只有後端讀寫：這個小時開了幾張綠界訂單，`hour`（UTC 的 `YYYY-MM-DDTHH`）、`count`。全站每小時最多 60 張 |

- 一個教會的所有資料都在 `churches/{cid}` 底下，可以整棵匯出。
- 推播 token 放在 `users/{uid}`，只有本人和 Cloud Functions 讀得到。self-host 版的 roster editor 讀得到全部 token，這裡改掉了。
- 教會內顯示的名字來自 member doc，不讀 `users/{uid}`。
- 服事表上誰是誰只看 `duties[].uids`（名字 → uid）。名字沒有 uid 就是無帳號，即使和某位同工同名；提醒、異動通知、「我接下來的服事」、搬家都不以名字補 uid。舊資料要補 uid 時用 `functions/scripts/backfill-roster-uids.ts`：預設只預覽，只對沒有 `uids` 欄位的服事、名字和唯一一位同工完全相同時自動補；明確的空 `uids` 只能靠人工確認的對應檔補。
- `zones[].smallGroups` 是舊的小組名稱，自架版和 #85 之前留下的；現在的小組在 `smallGroups`（同工所在的小組 ID）。`functions/scripts/migrate-small-groups.ts` 把名稱轉成小組一次，搬家和認領時也照名稱轉。
- 每日內容來源只接受一種 JSON：`{"date":"YYYY-MM-DD","title":"…","body":"…","link":"https://…"}`，四個欄位都要有，`date` 必須是教會的今天（照教會的時區）。抓不到、格式不對或不是今天，都記成失敗，首頁說明原因，不改顯示舊內容或固定連結；管理員可以重抓目前設定的來源。
- 行事曆活動的時間一律照教會的時區顯示與分日，不看手機在哪裡。後端送給 App 的時間是教會當地的時刻加上當時的時差（`calendar.ts` 的 `inZone`），App 只取時刻；沒有時差的時間視為錯誤資料。App 送出的時間是教會當地的時刻、不帶時差，由後端照教會的時區換算（舊版 App 送的帶時差的時間照原樣收）。行事曆的月份快取也照教會的時區分月，記下當時的時區，時區改了就重抓。
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

線上支持的金額（30–1,000 元）只有網站和 Functions 檢查，不在 App 裡：`functions/src/limits.ts` 的 `SUPPORT_AMOUNT` 和 `landing/support.html` 金額欄位的 `min`、`max`，同一個測試比對。

比對教會名稱、搜尋同工的正規化（`app/lib/domain/text.dart` ↔ `functions/src/text.ts`）和數字的方法，兩邊的測試都跑 `testdata/text_rules.json` 的每一列；要改規則先在那裡加一列。

App 與 Functions 各寫一次的教會資料規則也一樣：新教會的預設聚會、服事項目改名（只能原地改名，其他服事項目不變）、服事表上誰是誰（名字連到 uid 且還在名單上才算，一個服事項目只算一次）、搬家時舊同工資料的轉換，兩邊的測試都跑 `testdata/church_rules.json`。

## 角色與群組

權限都從身分來（#82）。一般同工什麼都沒有；要管事的人有一個或幾個身分，每個身分照下表給權限：

| 身分（`identities` 裡的一項） | 存法 | 能做什麼 |
|---|---|---|
| 管理員 | `{kind: 'admin'}`，`role: 'admin'` | 全部 |
| 牧者 · 全教會 | `{kind: 'pastor'}`，`role: 'admin'` | 等於管理員 |
| 牧者 · 某幾個聚會 | `{kind: 'pastor', services: [...]}`，那幾個進 `leadTypes` | 等於那幾個聚會的負責人 |
| 行政 | `{kind: 'office'}`，`groups` 是 `roster-editors` 和 `calendar-editors` | 排所有服事表（含活動的）、改所有活動；不能管同工和設定 |
| 聚會負責人 | `{kind: 'lead', service}`，進 `leadTypes` | 排那個聚會的服事表、加入和移出它的同工 |
| 事工負責人 | `{kind: 'lead', ministry}`，進 `leadMinistries` | 在任何聚會和活動排那個事工連到的服事項目（經 `editLedDuties`）、加入和移出它的同工 |
| 小組長 | `{kind: 'lead', smallGroup}`，進 `leadSmallGroups` | 管那個小組的活動、回報人數、設小組什麼時候聚會、加入和移出它的同工（#85） |

- `identities` 是同工頁顯示和編輯的；規則讀不到裡面，所以 App 同時寫攤平的 `role`、`groups`、`leadTypes`、`leadMinistries`（`Member.withIdentities`），舊版 App 也照舊讀 `role` 和 `groups`。只有管理員能寫這些欄位。沒有 `identities` 的舊資料：`role: 'admin'` 算管理員，`roster-editors` 算行政。
- 只有管理員（含全教會的牧者）能給身分。負責人只能加入、移出自己群組的一般同工（沒有身分、不是管理員、不在權限群組的；`setGroupMember`，規則在 `testdata/church_rules.json` 的 `groupMembership`），看得到全教會的同工名單。教會至少要有一位 `role: 'admin'`。
- `role` 另外的 `leader`、`staff`、`member` 是舊的身分標示，不再顯示；`leader` 的同工在轉換時變成他那幾個小組的小組長。
- 小組（#85）屬於一個聚會，由管理員或那個聚會的負責人、牧者開、改名、關閉，也由他們指派小組長，一個小組只有一位（經 `editSmallGroup`，規則在 `testdata/church_rules.json` 的 `smallGroupEditing`）；管理員也能在同工頁直接給小組長這個身分，只能選還沒有小組長的小組。小組長只能設小組什麼時候聚會（`smallGroupScheduling`）。改小組或換小組長時帶上畫面上看到的樣子，有人先改過就拒絕（衝突），復原也一樣，不會蓋掉別人的。小組的同工（`smallGroups`）由管理員、小組長和那個聚會的負責人加、移；沒有帳號的組員不記。關閉小組時小組長和同工都移出，填過的人數留著。
- `zones`：同工屬於的聚會（牧區），每個帶他在那裡的服事項目，可以是空的。聚會的同工從這裡來；安排服事表時選了不是這個聚會同工的人，只排這一次，不會加進來（#82）。服事表分頁顯示自己的牧區、負責的聚會和事工連到的聚會，admin 和行政看全部；這只是讓畫面清爽，規則照樣讓所有同工讀所有服事表。
- `zoneTypes`：`zones` 攤平後的聚會別 ID 清單；規則讀不到 `zones` 裡面，所以另存一份。
- `ministries`：同工所在的事工 ID，只由管理員或那個事工的負責人加、移。
- 舊的權限群組換成身分：`calendar-editors` 併進行政；只有 `roster-editors` 的（以前只能排自己的牧區）變成他牧區的聚會負責人。從自架版搬來的同工在認領或合併時換（`claimedGroups`），現有的同工用 `functions/scripts/migrate-leads.ts` 換一次；規則上線後要馬上跑，不然 `roster-editors` 會變成能排所有聚會。

## 權限

「同工」= 該教會有 member doc，**且**教會 `status == 'active'`。所有判斷只看路徑裡那間教會。

| 動作 | 誰可以 |
|---|---|
| 讀 `churches/{cid}` | 有 member doc 的人（停用中也可以，用來顯示「教會已停用」） |
| 建立、改名、改狀態、刪除教會 | 只有 Cloud Functions |
| 改主畫面名稱（`homeName`） | admin，只能動這個欄位 |
| 查自己屬於哪些教會 | 本人（collection group `members`，`where uid == 自己`） |
| 改回報人數的開關（`attendanceSince`） | admin |
| 關掉、打開申請加入（`joinRequestsClosed`，只能是 `true` 或拿掉） | admin |
| 讀申請加入 | admin；寫入都是後端 |
| 讀 member | 本人、admin、行政、負責人（`leadTypes`、`leadMinistries` 或 `leadSmallGroups` 不是空的） |
| 讀待認領同工 | admin、行政、負責人；只有 admin 能刪，其他寫入都是後端 |
| 加入教會（建立 member） | 只有 Cloud Functions（邀請、管理員允許申請加入） |
| 改 member | admin（不能改 `uid`、不能把自己降級）；本人只能改 `notificationPrefs`。改到 `notificationPrefs` 時，`muted` 只能是 `reminder`、`rosterChange`、`memberLeft`、`attendance`、`joinRequest`，`reminderTiming` 只能是 `weekly`、`dayBefore`、`both`。只檢查這次改到的欄位，因為從 self-host 搬來的可能有舊的種類，App 也是一次寫一個欄位 |
| 刪 member | admin 刪別人；非 admin 可以自己退出。admin 要先被別的 admin 降級才能走 |
| 讀服事表、排序、設定 | 同工 |
| 寫服事表、排序 | admin、行政（任何已設定的聚會別）；聚會負責人和牧者（只限 `leadTypes` 裡的聚會別，移動時新舊聚會別都要有）。事工負責人不能直接寫，經 `editLedDuties` 只改他事工連到的服事項目：其他服事項目、特別活動不能動，不能刪整天；還沒存過的那天可以照範本建立，但要有他的服事項目、其他服事項目要沒有人（`testdata/church_rules.json` 的 `ledDuties`） |
| 寫活動的服事表 | admin、行政，和活動所屬群組的負責人（服事表的 `group`，由後端照活動寫；App 建立時帶活動的，之後改不了）；事工負責人經 `editLedDuties` 只排他的服事項目（照名稱比對）。一般服事表和活動的服事表不能互相改過去；取消了的不能再改，只能刪 |
| 讀、寫回報人數（`attendance`，#85） | 照 `testdata/church_rules.json` 的 `attendanceAccess`：admin 全部；聚會的負責人和牧者那個聚會和底下的小組；小組長自己的小組。行政另外讀得到聚會的（不含小組）。可以補填、改、清掉；暫停也是同一批人設 |
| 讀小組 | 同工；寫只有 Cloud Functions（`editSmallGroup`） |
| 寫設定 | admin；`services` 的 `ids` 只增不減，不能刪；`calendar`、`linkContent`、`webhook`、`smallGroups` 只有 Cloud Functions 能寫。服事項目改名要連同工的牧區與同工排序一起改，經 `editService`（比對改名前的那一個聚會，其他聚會照現在的保留；超過 500 筆寫入整筆拒絕） |
| 讀寫 `users/{uid}` | 本人（限上列欄位，`fcm` 最多 50 支裝置）；刪除由 Cloud Functions 處理 |
| 讀 `users/{uid}/notifications` | 只有本人；寫入只有後端 |

## 回報人數（#85）

管理員在「管理教會」打開，記下打開那天（`attendanceSince`），之前的聚會不算。

- 什麼時候要填：聚會照服事設定的星期幾，而且那天有服事表；小組照設的星期幾，每週或隔週（從 `startsOn` 算）。沒設星期幾的小組不提醒。暫停的期間不算（`testdata/church_rules.json` 的 `attendanceDue`）。
- 提醒：每小時跑一次，教會當地 21:00 那次給還沒人填的群組推播一次（`functions/src/attendance.ts`）：聚會給它的負責人（`lead` 身分；牧者看得到人數、能填，但不提醒，`testdata/church_rules.json` 的 `attendanceReminded`），小組給小組長。首頁的「填寫人數」也只給會被提醒的人。有人填了、或按了「這次沒聚會」就不推。同工可以在「設定 → 通知」關掉「回報人數提醒」（`attendance`）。
- 首頁：我負責的聚會和小組（聚會的負責人、牧者，小組長；不含管理員）最近一次要填的還沒人填，就顯示「填寫人數」，到下一次聚會為止。
- 群組頁列最近 12 週要填的聚會：填了的寫人數，「這次沒聚會」的寫「沒聚會」，沒人填的寫「未填」，不當成 0；點了可以補填或改。
- 回報人數關著時，小組只是名字：沒有聚會時間、人數，也沒有提醒和首頁的「填寫人數」。

## 行事曆活動的歸屬（#84）

活動屬於全教會，或屬於一個群組，存在 Google 活動的 `extendedProperties.private.marthaGroup`（`''` 是全教會，`service:<id>`、`ministry:<id>`、`small:<id>` 是群組的；小組的活動由小組長管，#85），在 Google 日曆改活動也留著；直接在 Google 建的是全教會的。`calendarWrite` 照 Google 上現在的歸屬判斷（`testdata/church_rules.json` 的 `eventWriting`）：admin 和行政（`calendar-editors`）全部；群組的負責人只能建、改、刪自己群組的活動，不能動全教會的，也不能把活動移到全教會或別的群組；其他同工連行事曆都不會被問。

- 沒帶 `group` 的寫入（還不認得群組的舊版 App）：改活動就照 Google 上原本的歸屬，新活動算全教會的。
- 重複活動照系列存：把其中一天改到別的群組，整個系列（Google 上的主活動）跟著改，其他沒個別改過的日子也就跟著。
- 活動的服事表上的 `group` 是規則判斷負責人能不能排的依據，但規則查不到 Google：負責人建服事表時寫的 `group` 由後端（`onEventRosterCreated`）回頭對 Google，對不上（或活動已刪）就把這張服事表刪掉；不是 admin 或行政的人復原刪除時，也只能帶回自己群組活動的服事表。
- 群組的活動不推播（活動本來就沒有推播），但教會的 webhook 照樣收到 `calendar.*`，跟全教會的一樣。

## 交給 Cloud Functions 的（M2）

規則做不到的檢查都放在後端：建立教會（email 已驗證、`nameKey` 不重複）、邀請加入、帳號刪除、平台後台（改名、轉移管理員、停用）、服事項目改名（`editService`，連同事工連到的服事項目）、事工負責人排服事表（`editLedDuties`）、負責人加入和移出群組的同工（`setGroupMember`）。

行事曆連接完成時（`calendarCallback`），在向 Google 換 token 前後都重新確認這位仍是這間啟用中教會的管理員；中途被降級、移除或教會停用，就撤銷剛拿到的授權、不寫入。連接中的 `calendarStates/{state}` 帶後端專用的 `exchanging`，避免同一個 state 被用兩次。

在某間教會裡做事的 Function 都先經過 `functions/src/access.ts`，判斷和上表的規則一樣，依序：

1. 不是這間教會的同工 → `permission-denied`（reason `permissionDenied`），不透露教會的狀態。
2. 教會停用（`suspended` 或 `deleted`）→ `failed-precondition`、reason `churchClosed`，不管這位同工原本能做什麼；App 顯示「這間教會已停用」。只有還原教會（`restoreChurch`）放行停用中的教會，而且只還原 30 天內刪除的；營運者停用的、刪除超過 30 天的一樣是 `churchClosed`。
3. 權限不夠 → `permissionDenied`。等級有同工、權限群組（admin 都算）、admin，以及 roster editor：教會有過這個聚會別（`settings/services` 的 `ids`），而且是 admin、行政（roster-editors），或 `leadTypes` 有它；照片匯入另外讓事工連到這個聚會服事項目的負責人用（`arranges`）。

例外：邀請停用教會的回 `inviteInvalid`，教會預覽回 `notFound`（給還不是同工的人看）；排程和觸發器遇到停用的教會直接略過。Firestore 直接讀寫被規則擋下時，規則分不出原因，一律是 permission-denied。

App 看不到這個差別：在一間教會裡做的事，不管是 Firestore、Storage 還是 Function，都在那間教會的 `ChurchData`（`app/lib/data/backend.dart`）上，被擋下一律是 `CloudException`。規則擋下的讀寫和 Function 一樣是 `permissionDenied`，所以畫面說的是同一句「沒有權限」。

`previewInvite` 不用登入：邀請連結開的登入頁要能顯示是哪間教會邀請。沒登入時只回教會名稱；登入後才回教會 id 和到期日。邀請碼本身就是秘密，拿到碼就能註冊加入，所以這不多露出什麼。

## Storage

| 路徑 | 誰可以 |
|---|---|
| `churches/{cid}/logo.png` | 同工讀；管理員寫，1MB 以內的圖片 |
| `churches/{cid}/logo-{版本}-*.png` | 只有後端（主畫面 icon，經教會頁 Function 提供） |
| `moves/{uid}/*` | 只有上傳者本人讀寫，20MB 以內（搬家檔，用完即刪） |
