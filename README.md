# 馬大別忙

多教會共用的同工服事表工具（代管版）。設計見 [`docs/design.md`](docs/design.md)，資料模型與權限見 [`docs/data-model.md`](docs/data-model.md)，專案建立見 [`docs/firebase-setup.md`](docs/firebase-setup.md)。

> 開發中。舊的自架版（church-staff-pwa）在其他分支，已凍結。

## 自己部署

代管版是唯一受支援的使用方式。程式碼採 MIT 公開，技術同工可以自己部署，但**不受支援**：沒有安裝精靈、沒有升級指引，問題請自行處理。要離開代管版，管理員可以在「教會資訊 → 匯出資料」下載全部資料。

想自己部署的話，起點在：

- `scripts/firebase-project.sh`：建立 Firebase 專案、開服務、寫 App 設定
- [`docs/firebase-setup.md`](docs/firebase-setup.md)：專案設定步驟與要手動完成的部分

## 結構

| 路徑 | 內容 |
| --- | --- |
| `app/` | Flutter App（iOS、Android、Web） |
| `functions/` | Cloud Functions（TypeScript，asia-east1） |
| `firestore.rules`、`storage.rules` | 安全規則，測試在 `firestore-tests/` |
| `landing/` | Landing page 與法律文件草稿 |
| `tools/e2e/` | 瀏覽器 smoke test、截圖、效能量測 |
| `scripts/` | `check.sh`（全部檢查）、`firebase-project.sh`（建立專案） |

## 開發

```sh
scripts/check.sh            # analyze、全部測試（需要 Java、Node 與 Chrome）

cd app
flutter run -d chrome --dart-define=MARTHA_ENV=demo       # 不用網路，記憶體裡的示範教會
flutter run -d chrome --dart-define=MARTHA_ENV=emulator   # 接本機 Firebase emulator
```

App 的流程測試與示範模式用記憶體版後端（`app/lib/data/memory/`）。它只保留畫面需要的規則（權限、邀請期限、最後一位管理員、未驗證 email、教會停用），而且每一條都在 `app/test/contract/` 的契約測試裡：同一組案例在 `flutter test` 跑記憶體版，在 `scripts/check.sh contract` 用 Chrome 跑真的 Firebase 後端接本機 emulator（需要 Chrome、Java、Node）。後端另外算出來的東西（搬家檔內容、教會連結抓到的內容、webhook 送出結果、Google 行事曆、照片辨識、雲端費用目標）在記憶體版是測試指定的固定答案。改 rules 或 Functions 的行為時，契約測試要跟著改。

本機 emulator：

```sh
cd functions && npm run build && cd ..
npx --prefix functions firebase emulators:start --only auth,firestore,functions,storage --project demo-martha
FIRESTORE_EMULATOR_HOST=localhost:8181 FIREBASE_AUTH_EMULATOR_HOST=localhost:9199 \
  npx --prefix functions tsx functions/scripts/seed.ts   # 150 位同工、一年份服事表
```

## 授權

程式碼採 [MIT](LICENSE)。「馬大別忙」名稱與圖示不在 MIT 授權範圍內，fork 請改名。

希望每間教會都能免費使用，請勿把它包裝成商業產品販售（這是期望，不是授權條件）。
