"""這個資料夾裡的腳本共用的 Firestore 讀取工具。

底線開頭代表「給 scripts/ 自己用」，不是可以獨立跑的腳本。腳本用
`python3 scripts/x.py` 跑時 sys.path[0] 就是 scripts/，所以直接 `import
_firestore` 就找得到。

會抽出來是因為 build-import-prompt.py 與 preview-roster-import.py 各有一份
一模一樣的 project_id / token / get，而 token 那段的雙憑證退路是後來才補的 ——
補在一邊忘了另一邊，就會出現「一支跑得動、另一支叫你去 gcloud auth login」
這種查起來很煩的狀況。
"""

import json
import os
import pathlib
import subprocess
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
LOCAL = ROOT / ".local"

# enum 的 name 就是資料格式的一部分，見 lib/core/types/service_type.dart。
TYPES = {"sundayService": "主日", "youth": "青崇", "children": "兒主"}


def project_id() -> str:
    """repo 是公開的，專案 id 不寫死在版控裡。"""
    value = os.environ.get("FIREBASE_PROJECT_ID", "").strip()
    if value:
        return value
    path = LOCAL / "project-id"
    if path.exists():
        return path.read_text().strip()
    sys.exit(
        "找不到 Firebase 專案 id。二選一：\n"
        "  export FIREBASE_PROJECT_ID=你的專案id\n"
        "  echo 你的專案id > .local/project-id"
    )


def base_url() -> str:
    return (
        f"https://firestore.googleapis.com/v1/projects/{project_id()}"
        "/databases/(default)/documents"
    )


def token() -> str:
    """拿一個讀得到 Firestore 的 access token。

    使用者憑證會過期，而過期後 `gcloud auth print-access-token` 需要互動式重新
    登入 —— 在腳本裡跑就直接死掉。所以拿不到時退回 application-default 憑證，
    那份通常還活著。兩個都不行才叫使用者去登入。
    """
    for command in (
        ["gcloud", "auth", "print-access-token"],
        ["gcloud", "auth", "application-default", "print-access-token"],
    ):
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode == 0 and len(result.stdout.strip()) >= 50:
            return result.stdout.strip()
    sys.exit(
        "拿不到 access token，兩種憑證都試過了。二選一：\n"
        "  gcloud auth login\n"
        "  gcloud auth application-default login"
    )


def get(base: str, path: str, tok: str) -> dict:
    request = urllib.request.Request(
        f"{base}/{path}", headers={"Authorization": f"Bearer {tok}"}
    )
    with urllib.request.urlopen(request) as response:
        return json.load(response)


def paged(base: str, path: str, tok: str) -> list[dict]:
    """把一個集合讀完，跟著 nextPageToken 翻到底。"""
    docs, page = [], None
    while True:
        joiner = "&" if "?" in path else "?"
        suffix = f"{joiner}pageToken={page}" if page else ""
        data = get(base, f"{path}{suffix}", tok)
        docs.extend(data.get("documents", []))
        page = data.get("nextPageToken")
        if not page:
            break
    return docs
