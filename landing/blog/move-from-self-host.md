---
title: 從自架的同工助手搬到馬大別忙
date: 2026-11-10
description: 自架的同工助手（church-staff-pwa）不再更新了。把同工、服事表和聚會設定搬到馬大別忙，大約十分鐘。
---

自己架的同工助手（church-staff-pwa）已經不再更新。馬大別忙是同一套服事表的線上版，不用自己顧 Firebase 和 Cloudflare，還有手機 App。這篇給當初架網站的管理員，照著做大約十分鐘。

搬家只會讀舊網站的資料，不會改動或刪除。搬完之前，大家照常用舊網站就好。

請用電腦做。搬家檔是在電腦上產生、下載的，用同一台電腦上傳最省事。

## 會搬過去的

- 同工的名字、email、權限、所屬的聚會和小組
- 每一份服事表、特別活動和同工排序
- 聚會、服事項目和常用的特別活動

登入密碼、推播、LINE 通知、每日靈糧和行事曆連線不會搬。同工到馬大別忙用同一個 email 登入，就會接上自己的資料；行事曆搬完再重新連接。

## 1. 產生搬家檔

用當初建立網站的 Google 帳號[打開 Cloud Shell](https://shell.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https%3A%2F%2Fgithub.com%2Fhansli112%2Fchurch-staff-pwa&cloudshell_git_branch=main&cloudshell_workspace=.&cloudshell_tutorial=docs%2Fmove-to-martha.md&show=terminal)。瀏覽器登入的是別的帳號也沒關係，先打開，跑完再照下面的說明換帳號。

跳出 **在 Cloud Shell 中開啟** 時，先勾 **信任存放區**，再按 **確認**。

![勾選信任存放區，再按確認](/media/zh-Hant/move-cloudshell-trust.png)

接著跳出 **授權 Cloud Shell**，按 **授權**。這是 Google 官方的視窗，讓 Cloud Shell 用你的帳號讀舊網站的資料。之後再看到同樣的視窗，也一樣按 **授權**。

![授權 Cloud Shell 的視窗，按授權](/media/zh-Hant/move-cloudshell-authorize.png)

右邊會出現搬家教學。按第 1 步指令卡右上角的終端機圖示，再到下方的終端機按一次 Enter。

![搬家教學的第 1 步，指令卡右上角的終端機圖示](/media/zh-Hant/move-cloudshell-run.png)

跑完會寫出同工幾位、服事表幾份，對一下數字。

- 寫 `找到好幾個同工助手的專案`：在指令最後的 `--out move.json` 前面加上 `--project 專案ID` 再跑一次，專案 ID 填它列出來的其中一個。
- 寫 `找不到同工助手的專案` 或 `讀不到`：Cloud Shell 用的不是建立網站的 Google 帳號。照下面換成那個帳號：
  1. 在終端機輸入 `gcloud auth login`，按 Enter。
  2. 問要不要繼續（`Y/n`）時，輸入 `Y`，按 Enter。
  3. 點終端機裡出現的網址，登入建立網站的帳號（不在清單上就選 **使用其他帳戶**），再按 **允許**。
  4. 複製頁面上的驗證碼，貼回終端機，按 Enter。
  5. 再按一次教學第 1 步的終端機圖示，在終端機按 Enter。

## 2. 下載搬家檔

在終端機執行：

```sh
cloudshell download "$HOME/move.json"
```

瀏覽器會下載 `move.json`。這個檔案裡有同工的名字和 email，不要傳到群組或寄給別人，上傳完就刪掉。

## 3. 上傳到馬大別忙

1. <span data-from-app="hide">打開[網頁版](/home)</span>登入，用 Google 或 email 都可以。用 email 註冊的，要先點開驗證信裡的連結。
2. 在「加入你的教會」選「建立新教會」，點最下面的「從舊版搬過來」。
3. 點「選擇搬家檔」，選剛剛下載的 `move.json`。
4. 看一下同工和服事表的數量，填上「教會名稱」。
5. 在「這位是我（選填）」選你自己，就會接手你在舊版的服事和權限。和你登入的 email 一樣的那位已經先勾好了。
6. 點「建立教會並搬過來」。上傳的人就是新教會的管理員。

![選擇搬家檔，看過內容、填好教會名稱，按建立教會並搬過來](media:move)

## 4. 請同工加入

搬過來的同工會先列成還沒登入。到「設定」→「邀請」建立邀請連結，傳到同工的群組。

- 同工用和舊版同一個 email 登入，會看到「加入〈你們教會〉？」，點「加入」就接上自己的服事表。
- 舊版用 email 和密碼登入的人，舊密碼不能用。請他用同一個 email 註冊新帳號，或直接用 Google 登入。
- 舊版沒有 email 的同工，用邀請連結加入時名字填得和服事表上一樣，就會被問是不是自己。
- 換了 email 的人，由管理員在他的同工頁點「合併還沒登入的資料」。

## 搬完之後

搬家只搬一次，之後在舊網站改的服事表不會過來。挑一個日子，跟同工說從那天起改用馬大別忙。

舊網站可以留著當備份，也可以到 Firebase 和 Cloudflare 的主控台自己刪掉。

接下來的設定可以看[第一次使用：建立教會、邀請同工](/blog/getting-started/)和[安排服事：幾週一起排、拖曳交換](/blog/plan-weeks/)。
