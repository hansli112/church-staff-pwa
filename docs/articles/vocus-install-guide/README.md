# vocus 安裝教學文章

給不會寫程式的教會同工看的安裝教學，2026-09-28 發佈在 vocus：
https://vocus.cc/article/6aba4b3afd89780001a439af

| 檔案 | 內容 |
|---|---|
| `article.md` | 文章原稿。`【插入圖 NN｜檔名】` 是圖片位置，下一行 `圖說：` 是 caption |
| `images/` | 文章用圖。`00-cover.png` 是 vocus 封面，`00-app-overview.png` 是開頭主圖（也是 Threads 附圖） |
| `threads.md` | Threads 宣傳貼文（本文、第 2/2 則連結、topic、發文時間） |
| `cover/cover.html` | 封面原始檔，用 1200×630 viewport 截圖就是 `00-cover.png` |
| `tools/` | 更新 vocus 文章、拍 App 截圖用的 script |

截圖裡的「恩典教會」、王大衛、陳美恩等人名都是示範資料。

## 改文章後更新 vocus

vocus 的編輯器是 Lexical。這些 script 不透過 API，而是用 Chrome DevTools Protocol 操作已登入的 Chrome：先貼 HTML，再把圖片標記換成帶 caption 的 image node，最後走「調整發佈設定」重新發佈。

1. Chrome 用 `--remote-debugging-port=9222` 開啟，並登入 vocus（Google 帳號 hansli112871114）。
2. `node tools/cdpd.mjs &`：在 127.0.0.1:9333 開一個小型 CDP daemon。第一次連線時 Chrome 會跳「Allow remote debugging?」，要按 Allow。
3. 有新圖或換過圖：先從 `tools/vocus-images.json` 刪掉那張的 key，打開文章編輯頁、點進內文，再跑 `python3 tools/upload_images.py`。圖片是用貼上 `File` 的方式上傳到 vocus CDN，網址會記回 `vocus-images.json`。
4. `python3 tools/build_body.py`：把 `article.md` 轉成 HTML，並附上每張圖的 caption。
5. `python3 tools/republish.py`：重建內文、清掉「上篇」後重新發佈。vocus 每次都會自動把沙龍裡的上一篇文章填進「上篇」，所以這一步要清。

`python3 tools/preview.py` 會在這個資料夾產生 `preview.html`（圖片內嵌），用來在本機先看排版。這個檔已經 gitignore。

## 拍 App 截圖（Firebase emulator，全假資料）

不用建立雲端資源，也不會用到真實教會的資料：

1. 複製一份 repo，在 `lib/main.dart` 的 `Firebase.initializeApp` 之後加上：
   ```dart
   FirebaseAuth.instance.useAuthEmulator('localhost', 9199);
   FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8181);
   ```
   `default_church_config.dart` 的 `appName` 改成示範教會的名字。要拍行事曆的話，把 `features.calendar` 改成 `true`。
2. build：`flutter build web --release --no-web-resources-cdn --dart-define-from-file=fb.json`。`fb.json` 的內容是假的 `FIREBASE_*`，其中 `FIREBASE_PROJECT_ID` 要用 `demo-` 開頭。要拍行事曆的話，再加上假的 `GOOGLE_CALENDAR_API_KEY` 和 `GOOGLE_CALENDAR_ID`。
3. 起 emulator：`firestore-tests/node_modules/.bin/firebase emulators:start --only auth,firestore --project demo-church`。新版 firebase-tools 需要 Java 21 以上，firestore-tests 裡鎖的 v14 可以用 Java 17。
4. `python3 -m http.server` 服務 `build/web`，然後跑 `python3 tools/seed.py`，會建立 4 個假帳號、服事表範本和 7 份服事表。密碼寫在 `staff-pass`，不要 commit。
5. Chrome 用 iPhone 的 device metrics（390×844、DPR 3）加 iPhone Safari UA 開啟，用 `meien@example.test` 登入。首頁的「加到主畫面」卡片按「不用了」後再截圖。
6. 行事曆：用 CDP `Fetch.enable` 攔截 `*googleapis.com/calendar/*`，再用 `Fetch.fulfillRequest` 回傳假活動。
7. 拍完後關掉 emulator 和 server，並刪掉那份複製的 repo。
