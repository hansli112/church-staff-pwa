# 匯出資料的格式

管理員在「教會資訊 → 匯出資料」下載一個 zip，裡面有兩個檔案。產生的程式在 `app/lib/domain/export.dart`，測試在 `app/test/domain/export_test.dart`。

這份文件給想把資料搬到自己部署的人參考。目前沒有把匯出檔再匯入回來的工具。

## `服事表.csv`

- UTF-8，開頭有 BOM，Excel 直接打開中文不會亂碼。
- 換行是 CRLF。欄位有逗號、雙引號或換行時用雙引號包起來，裡面的雙引號寫兩次。
- 每一列是某一天某個服事的一個服事項目：

| 欄位 | 內容 |
| --- | --- |
| 日期 | `YYYY-MM-DD` |
| 服事 | 服事名稱，例如「主日崇拜」 |
| 服事項目 | 例如「司琴」 |
| 同工 | 這一格的同工，好幾個人用「、」連接；沒有人就是空的 |

只有存過的服事表會出現，包括過去的日子。日期由舊到新，同一天依服事設定的順序。

## `martha-export.json`

```jsonc
{
  "format": "martha-church-export",  // 固定
  "version": 1,                       // 格式改了會加一
  "exportedAt": "2026-10-04T02:30:00.000Z",

  "church": { "id": "…", "name": "恩典堂", "homeName": "恩典", "logoUrl": "https://…" },

  // 服事設定。ids 是用過的所有服事 id，只增不減。
  "services": {
    "services": [
      {
        "id": "sunday", "name": "主日崇拜",
        "weekday": 7,                      // 1 = 週一 … 7 = 週日
        "enabled": true,
        "duties": ["司會", "司琴"],         // 服事表的範本
        "events": [{ "name": "聖餐", "color": 0 }]  // color：0 紅、1 橘、2 黃、3 綠、4 藍、5 紫
      }
    ],
    "ids": ["sunday"]
  },

  // 同工。groups：roster-editors、calendar-editors。zones 是各服事負責的服事項目。
  "members": [
    {
      "uid": "…", "name": "李美玉", "email": "mei@example.com",
      "role": "staff",                   // admin、leader、staff、member
      "groups": ["roster-editors"],
      "zones": [{ "serviceType": "sunday", "duties": ["司琴"] }],
      "joinedAt": "2026-09-01T00:00:00.000Z"
    }
  ],

  // 同工排序：服事 id → 服事項目 → 依序的名字。
  "staffOrders": { "sunday": { "司琴": ["李美玉", "陳志豪"] } },

  // 所有存過的服事表。people 是顯示的名字；uids 只列出是同工的人。
  "rosters": [
    {
      "id": "2026-10-04_sunday", "date": "2026-10-04", "serviceId": "sunday",
      "duties": [{ "duty": "司琴", "people": ["李美玉"], "uids": { "李美玉": "…" } }],
      "events": [{ "name": "聖餐", "color": 0 }]
    }
  ],

  // 行事曆：只有有沒有連接、連的是哪本。沒有授權。
  "calendar": { "connected": true, "calendarName": "教會行事曆" },

  // 教會連結。fetchMinute 是台北時間午夜後的分鐘數。
  "churchLink": { "title": "奉獻", "body": "", "url": "https://…", "source": null, "fetchMinute": 270 },

  // 外部通知：網址與開了哪些事件。沒有密鑰。
  "webhook": { "url": "https://…", "events": { "calendar": true, "roster": false } }
}
```

沒有設定的部分是 `null`（`calendar`、`churchLink`、`webhook`），清單是空的 `[]`。

## 不包含

- 推播 token、行事曆的 Google 授權、外部通知的密鑰、邀請碼。
- 其他教會的任何資料。
- 帳號本身（登入方式、密碼）。同工在新的地方要重新註冊。
