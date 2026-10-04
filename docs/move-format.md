# 搬家檔的格式

舊的自架版（church-staff-pwa）的管理員在自己的 Cloud Shell 執行搬家指令，用自己的帳號讀 Firestore，寫出一個搬家檔，再到馬大別忙「建立教會 → 從舊版搬過來」上傳。讀取與對照在 `functions/src/move.ts`、`functions/src/importer.ts`。

## 格式

一個 UTF-8 的 JSON 檔，最大 20MB：

```jsonc
{
  "format": "church-staff-pwa-move",   // 固定
  "version": 1,
  "project": "grace-church-staff",     // 舊的 Firebase 專案 id，只做紀錄
  "exportedAt": "2026-10-04T00:00:00Z",

  // 舊版 Firestore 的四個集合，每份文件是 {id, data}，data 照原樣。
  "users":       [{ "id": "<舊 uid>", "data": { "name": "王牧師", "email": "…", "role": "admin", "groups": [], "zones": [] } }],
  "settings":    [{ "id": "services", "data": { … } }, { "id": "roster_templates", "data": { … } }, …],
  "rosters":     [{ "id": "20261004_sunday", "data": { "type": "sunday", "date": { "__time__": "2026-10-03T16:00:00Z" }, "duties": […] } }],
  "staffOrders": [{ "id": "sunday", "data": { "roles": { "司琴": ["李美玉"] } } }]
}
```

- Firestore 的時間寫成 `{"__time__": "<ISO 8601>"}`。也接受 Admin SDK 直接 `JSON.stringify` 出來的 `{"_seconds": …, "_nanoseconds": …}`。
- `settings` 裡只有 `services`、`roster_templates`、`event_options` 會用到；小組範本、每日靈糧、LINE 通知等設定不搬。

## 不放、也不會讀

- **密碼雜湊**：讓人上傳任意的密碼雜湊，等於讓人能替別人的 email 建帳號。檔案裡就算有（例如 `accounts`、`passwordHash`、`salt`），也一律忽略。同工用自己的 email 重新登入：Google 帳號直接登入；原本用 email 密碼的人，用同一個 email 重新註冊並設定新密碼。
- 推播 token、行事曆授權等任何密鑰。

## 上限

同工 2,000 人、服事表 20,000 天。超過就拒絕，並說明數字。

## 搬過來之後

- 上傳的人成為新教會的管理員，不論用哪個帳號登入。預覽時可以在名單上選「這位是我」，接手那位的牧區、權限群組與服事表。
- 其他同工存成「待認領」的同工資料（`churches/{cid}/pendingMembers/{舊 uid}`），服事表上原本指向舊 uid 的地方，就指向這筆資料。
- 待認領索引 `pendingIndex/{email 的 SHA-256}` 只有後端讀寫，key 是正規化（去空白、小寫）後 email 的雜湊。
- 同工用同一個 email 登入、且 email 已驗證後，會被問要不要加入；換了 email 的人由管理員在同工頁合併。
- 上傳的檔案用完就刪掉。
