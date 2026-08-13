#!/usr/bin/env python3
"""從 Firestore 現況產生服事表匯入用的 prompt。

repo 是公開的，所以同工姓名一律不進版控：模板在
docs/roster-import-prompt.template.md，產生的成品寫到 .local/（已 gitignore）。

用法：
    python3 scripts/build-import-prompt.py            # 三個崇拜都產生
    python3 scripts/build-import-prompt.py youth      # 只產生青崇

需要環境變數 FIREBASE_PROJECT_ID，或 .local/project-id 這個檔。
只讀 Firestore，不寫入任何東西。

各教會自己的規則（例如「會前禱+奉獻拆兩項」、敬拜團展開方式、綽號對照）
放在 .local/import-rules.json，格式見模板文件末段。
"""

import json
import pathlib
import re
import subprocess
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
LOCAL = ROOT / ".local"
TEMPLATE = ROOT / "docs" / "roster-import-prompt.template.md"
TYPES = {"sundayService": "主日", "youth": "青崇", "children": "兒主"}


def project_id() -> str:
    import os

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


def token() -> str:
    result = subprocess.run(
        ["gcloud", "auth", "print-access-token"], capture_output=True, text=True
    )
    if result.returncode != 0 or len(result.stdout.strip()) < 50:
        sys.exit(f"拿不到 access token，先跑 gcloud auth login。\n{result.stderr.strip()}")
    return result.stdout.strip()


def get(base: str, path: str, tok: str) -> dict:
    request = urllib.request.Request(
        f"{base}/{path}", headers={"Authorization": f"Bearer {tok}"}
    )
    with urllib.request.urlopen(request) as response:
        return json.load(response)


def fetch_names(base: str, tok: str) -> list[str]:
    names, page = [], None
    while True:
        suffix = f"&pageToken={page}" if page else ""
        data = get(base, f"users?pageSize=300{suffix}", tok)
        for doc in data.get("documents", []):
            name = doc.get("fields", {}).get("name", {}).get("stringValue", "").strip()
            if name:
                names.append(name)
        page = data.get("nextPageToken")
        if not page:
            break
    return sorted(set(names))


def main() -> None:
    wanted = sys.argv[1:] or list(TYPES)
    for t in wanted:
        if t not in TYPES:
            sys.exit(f"未知的崇拜類別「{t}」，可用：{', '.join(TYPES)}")

    base = (
        f"https://firestore.googleapis.com/v1/projects/{project_id()}"
        "/databases/(default)/documents"
    )
    tok = token()

    names = fetch_names(base, tok)
    if not names:
        sys.exit("users 讀回來是空的，中止")

    templates = get(base, "settings/roster_templates", tok).get("fields", {})
    options = get(base, "settings/event_options", tok).get("fields", {})
    rules_path = LOCAL / "import-rules.json"
    rules = json.loads(rules_path.read_text()) if rules_path.exists() else {}

    # 只擷取模板本文那段（```` 圍起來的第一個區塊）。
    body = re.search(r"^````\n(.*?)^````$", TEMPLATE.read_text(), re.S | re.M)
    if not body:
        sys.exit("模板裡找不到 ```` 圍起來的本文區塊")
    body = body.group(1)

    # 去姓後撞名 → app 會判成「不確定是哪一位」，那格不會連到任何帳號。
    from collections import Counter

    given = Counter(n[1:] for n in names if len(n) > 1)
    clashes = {g: [n for n in names if n[1:] == g] for g, c in given.items() if c > 1}

    LOCAL.mkdir(exist_ok=True)
    for service_type in wanted:
        roles = [
            v["stringValue"]
            for v in templates.get(service_type, {})
            .get("arrayValue", {})
            .get("values", [])
        ]
        events = [
            v["mapValue"]["fields"]["name"]["stringValue"]
            for v in options.get(service_type, {})
            .get("arrayValue", {})
            .get("values", [])
        ]
        if not roles:
            print(f"⚠ {TYPES[service_type]} 在 roster_templates 裡沒有服事項目，跳過")
            continue

        rule = rules.get(service_type, {})
        nicknames = rule.get("nicknames", {})
        nickname_block = ""
        if nicknames:
            lines = "\n".join(f"{k} → {v}" for k, v in nicknames.items())
            nickname_block = (
                "\n### 綽號對照\n\n這些寫法跟本名沒有共同的字，只能查表：\n\n"
                + lines
                + "\n"
            )

        team = rule.get("teamRules", "")
        filled = (
            body.replace("{{ROLES}}", "、".join(roles))
            .replace("{{EVENTS}}", "、".join(events) if events else "（尚未設定）")
            .replace(
                "{{NAMES}}",
                "\n".join(
                    "  " + "、".join(names[i : i + 6]) for i in range(0, len(names), 6)
                ),
            )
            .replace("{{EXTRA_ROLE_RULES}}", rule.get("extraRoleRules", ""))
            .replace("{{NICKNAMES}}", nickname_block)
            .replace("{{TEAM_RULES}}", f"\n{team}\n" if team else "")
            .replace("{{SAMPLE_ROLE_A}}", roles[0])
            .replace("{{SAMPLE_ROLE_B}}", roles[1] if len(roles) > 1 else roles[0])
        )
        left = re.findall(r"\{\{[A-Z_]+\}\}", filled)
        if left:
            sys.exit(f"模板還有沒填掉的欄位：{sorted(set(left))}")

        out = LOCAL / f"roster-import-prompt.{service_type}.md"
        out.write_text(filled)
        print(f"{TYPES[service_type]}：{out.relative_to(ROOT)}（{len(names)} 人、{len(roles)} 個服事項目）")

    if clashes:
        print("\n⚠ 去掉姓氏後會撞名，這幾位匯入時可能對不到帳號：")
        for given_name, full in clashes.items():
            print(f"    {given_name} → {full}")


if __name__ == "__main__":
    main()
