---
name: roster-import
description: |
  把服事表照片轉成可匯入 app 的 JSON，並在匯入前用真實資料做一次乾式匯入。
  流程：讀圖 → 對照 Firestore 現況產出 JSON → 驗證 → 回報哪些名字/日期會對不上。
  使用者說「服事表轉 json」「這張表幫我轉」或直接貼服事表照片時使用。
  也可只做其中一步：/roster-import prompt（產生給外部 LLM 用的 prompt）、
  /roster-import check <檔案>（只驗證現成的 JSON）。
allowed-tools:
  - Read
  - Bash
  - Write
---

# 服事表匯入

## 前置

需要 gcloud 讀得到 Firestore，以及 `.local/project-id`（或 `FIREBASE_PROJECT_ID`）。
拿不到 token 就叫使用者跑 `gcloud auth login`，**不要**自己代跑登入。

`.local/` 已 gitignore。這個 repo 是公開的 —— **同工姓名、綽號對照、產生出來的
prompt 一律不准寫進 `docs/`、`scripts/` 或任何進版控的檔案**。要放範例就用虛構人名。

## 先確認崇拜類別

`sundayService`（主日）/ `youth`（青崇）/ `children`（兒主）。
照片標題通常寫得出來（例如「青年崇拜服事表」）。判斷不了就問，不要猜 ——
三個崇拜的服事項目不一樣（主日是「投影」，青崇是「PPT」），弄錯整份都對不上。

## 主流程：照片 → JSON

1. **產生最新的 prompt**（順便把名單更新到現況）

   ```
   python3 scripts/build-import-prompt.py <崇拜類別>
   ```

   成品在 `.local/roster-import-prompt.<崇拜類別>.md`。

2. **讀那份 prompt，然後自己照著它轉圖**

   用 Read 讀 `.local/roster-import-prompt.<崇拜類別>.md`，把裡面的規則當成
   自己的規則，直接讀使用者給的照片產出 JSON。不要把 prompt 丟回去給使用者
   叫他自己貼到別的地方 —— 除非他明講要 prompt（見下面「只要 prompt」）。

   特別容易錯的幾點，轉圖時自己再檢查一次：
   - 人名只能用 prompt 裡那份名單的全名。中文罕用字很容易看錯，
     **從名單裡挑字形最接近的，不要自己拼字**。
   - 「暫停」不是人名 → 整個項目不輸出。
   - 橫跨多欄的合併儲存格 → 被蓋到的項目不輸出，只留活動。
   - 格子裡自己寫了別的日期的欄位（週二禱告會那種）→ 整欄略過。

3. **寫成檔案**（放 `.local/`，不要放專案根目錄）

   ```
   .local/import-<崇拜類別>-<今天日期>.json
   ```

4. **乾式匯入驗證**（這一步不能跳）

   ```
   python3 scripts/preview-roster-import.py <崇拜類別> <剛才那個檔>
   ```

   這支會抓 Firestore 現況、產生一支暫時的 Dart 測試去呼叫 app 真正在用的
   `parseRosterImportJson`，所以輸出就是按下匯入會看到的東西。跑完自動刪掉
   那支測試。

5. **看結果決定要不要修**

   - `✗ 整份會被擋下來` → 一定要修，那份 JSON 匯不進去。
   - **名單裡沒有這個人** → 多半是名字看錯。回頭比對名單修掉。
     真的是新同工（還沒建帳號）才留著。
   - **不確定是哪一位** → 名字寫得不夠完整，補成全名。
   - **這幾天沒有匯入** → app 只有「本季 + 下季」的服事表。日期打錯就修；
     真的超出範圍就告訴使用者那幾天要等季度到了再匯。
   - **沒有設定這個服事** → 通常正常（臨時支援）。不用改 JSON。
   - **活動沒有固定顏色** → 正常。想固定顏色要去 app 的事件選項設定加。

   改完重跑第 4 步，直到只剩下無害的項目。

6. **交付**

   把 JSON 內容貼給使用者（讓他直接複製），並用一兩句話說明乾式匯入的結果，
   特別是還剩下哪些會出現在匯入結果視窗裡。檔案路徑也一併給。

## 只要 prompt

使用者說要 prompt（他想用別的 LLM 讀圖）時：

```
python3 scripts/build-import-prompt.py           # 三個都產生
python3 scripts/build-import-prompt.py youth     # 只產生一個
```

Read 產生出來的檔案，把 ```` 圍起來的本文原樣貼給使用者。
**提醒他那份含真實姓名，不要貼進公開的地方。**

## 使用者不在這台電腦前

他人在手機上、或換了一台機器時，本機這條路走不了。產一份可以上傳到
claude.ai 的獨立技能給他：

```
python3 scripts/build-claude-skill.py
```

產物 `.local/claude-skill/roster-import.zip` 上傳一次，之後在 claude.ai
附照片就能轉。**那份含真實姓名**，要跟使用者確認可以送到 claude.ai。
名單有異動時重跑再上傳覆蓋。

那個版本沒有乾式匯入（claude.ai 上沒有 repo 也沒有 Firestore），
錯誤要等 app 的匯入結果視窗才會浮現。人回到電腦前時，還是建議用本機這條。

## 只驗證現成的 JSON

```
python3 scripts/preview-roster-import.py <崇拜類別> <檔案>
```

照第 5 步解讀結果。

## 教會專屬規則放哪

`.local/import-rules.json`，每個崇拜類別各一組：

- `extraRoleRules` — 接在服事項目清單後面的額外規則
  （例如「會前禱+奉獻要拆成兩項」）
- `nicknames` — 綽號對照，`{"綽號": "全名"}`。只有跟本名沒有共同字的才需要
  （有共同字的靠白名單就夠了）。匯入結果的「名單裡沒有這個人」出現綽號時，
  就往這裡加一筆。
- `teamRules` — 敬拜團之類「一個欄位代表一組人」的展開規則

服事項目與活動清單不用寫在這裡，腳本直接從 Firestore 讀。

## 不要做的事

- 不要把真實姓名寫進 `docs/`、`scripts/`、測試、commit 訊息。
- 不要幫使用者按匯入 —— 那是 app 上的操作，而且會寫進 production。
- 不要跳過乾式匯入就把 JSON 交出去。
- 名字對不上時不要「猜一個最像的」硬塞。對不上就照原文留著，讓匯入結果去報。
