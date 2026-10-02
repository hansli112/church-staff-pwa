# 資料模型與權限規格

這份是規格，`firestore.rules` 是它的實作，`firestore-tests/rules.test.js` 是驗收。
三者不一致時以這份為準，再回頭改另外兩個。之後若搬離 Firestore，照這份重寫權限。

## 路徑

| 路徑 | 內容 |
|---|---|
| `users/{uid}` | 全域個資：`name`、`email`、`locale`、`fcm`（`{deviceId: token}`）、`createdAt`、`updatedAt` |
| `churches/{cid}` | `name`、`nameKey`（正規化後的名稱，同名檢查用）、`status`（`active` / `suspended` / `deleted`）、`createdBy`、`createdAt`、`deletedAt` |
| `churches/{cid}/members/{uid}` | `uid`（= doc id，collection group 查詢用）、`name`、`email`、`role`、`groups`、`zones`、`zoneTypes`、`notificationPrefs`、`joinedAt` |
| `churches/{cid}/rosters/{id}` | 服事表，`type` 是聚會別 ID，`dateKey` 是 `YYYY-MM-DD` |
| `churches/{cid}/staff_orders/{type}` | 各聚會別的同工排序 |
| `churches/{cid}/settings/{doc}` | `services`（聚會別，`ids` 只增不減）、`roster_templates` 等 |

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
| 查自己屬於哪些教會 | 本人（collection group `members`，`where uid == 自己`） |
| 讀 member | 本人、roster-editors、admin |
| 加入教會（建立 member） | 只有 Cloud Functions（邀請） |
| 改 member | admin（不能改 `uid`、不能把自己降級）；本人只能改 `notificationPrefs` |
| 刪 member | admin 刪別人；非 admin 可以自己退出。admin 要先被別的 admin 降級才能走 |
| 讀服事表、排序、設定 | 同工 |
| 寫服事表、排序 | admin（任何已設定的聚會別）；roster-editors（只限自己 `zoneTypes` 裡的聚會別，移動時新舊聚會別都要有） |
| 寫設定 | admin；`services` 的 `ids` 只增不減，不能刪 |
| 讀寫 `users/{uid}` | 本人（限上列欄位）；刪除由 Cloud Functions 處理 |

## 交給 Cloud Functions 的（M2）

規則做不到的檢查都放在後端：建立教會（email 已驗證、`nameKey` 不重複）、邀請加入、帳號刪除、平台後台（改名、轉移管理員、停用）。
