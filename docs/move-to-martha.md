# 搬到馬大別忙（線上版）

自架的同工助手不再更新。[馬大別忙](https://marthasit.com) 是同一套服事表的線上版：不用自己維護 Firebase、Cloudflare，手機 App 有服事提醒，免費使用。這份教學把你們教會的同工、服事表和聚會設定搬過去，大約 10 分鐘。

**搬家只讀資料，不會改動或刪除你們現在的網站**。搬完之前，大家照常用舊網站就好。

## 會搬過去的

- 同工的名字、email、權限群組、牧區、小組
- 每份服事表、特別活動、同工排序
- 聚會、服事項目、常用特別活動

**不會搬的**：登入密碼（同工到馬大別忙用同一個 email 重新註冊，或直接用 Google 登入，就會接上自己的資料）、推播、LINE 通知、每日靈糧、行事曆連線（搬完後在馬大別忙重新連接）。

## 1. 產生搬家檔

用**建立這個網站的 Google 帳號**打開 Cloud Shell。按下方指令卡右上角的「在終端機執行」圖示，然後在黑色終端機按一次 Enter：

```sh
bash -c 'd=$HOME/cloudshell_open/church-staff-pwa; [ -d "$d/.git" ] || git clone -q --branch main --single-branch https://github.com/hansli112/church-staff-pwa.git "$d" || exit 1; git -C "$d" pull -q --ff-only origin main; cd "$HOME" && node "$d/scripts/export-move.mjs" --out move.json'
```

完成後終端機會寫出同工幾位、服事表幾份，請對一下數字。

- 寫「找到好幾個同工助手的專案」：在指令最後的 `--out move.json` 前面加上 `--project 專案ID` 再執行一次（專案 ID 就是它列出來的那幾個之一）。
- 寫「沒有讀取權限」或「找不到」：換成建立網站的那個 Google 帳號再試。

## 2. 下載搬家檔

在終端機執行：

```sh
cloudshell download "$HOME/move.json"
```

瀏覽器會下載 `move.json`。這個檔案裡有同工的名字和 email，**不要傳到群組或寄給別人**，上傳完就可以刪掉。

## 3. 上傳到馬大別忙

1. 用電腦的瀏覽器打開 <https://marthasit.com/home>，用你的 Google 帳號或 email 登入。
2. 按「建立新教會」→「從舊版搬過來」，選剛剛下載的 `move.json`。
3. 先看預覽：同工、服事表的數量對不對；在名單上點「這位是我」，接手你自己在舊版的服事和權限。
4. 確認後建立。你會是新教會的管理員。

## 4. 請同工加入

搬過去的同工會先列成「還沒登入」。把馬大別忙的邀請連結傳到同工群組（在 App 的「設定 → 管理教會 → 邀請」），同工用**和舊版同一個 email** 登入，就會被問要不要加入，按「加入」就接上自己的服事表。沒有 email 或換了 email 的人，由管理員在「同工」頁按「合併還沒登入的資料」。

大家都搬過去之後，舊網站可以留著當備份，也可以在 Firebase、Cloudflare 主控台自己刪除。
