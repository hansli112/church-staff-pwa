#!/usr/bin/env python3
"""從 Firestore 現況產生服事表匯入用的 prompt。

repo 是公開的，所以同工姓名一律不進版控：模板在
docs/roster-import-prompt.template.md，產生的成品寫到 .local/（已 gitignore）。

用法：
    python3 scripts/build-import-prompt.py            # 三個崇拜都產生
    python3 scripts/build-import-prompt.py youth      # 只產生青崇
    python3 scripts/build-import-prompt.py --publish  # 順便發佈到 Firestore

需要環境變數 FIREBASE_PROJECT_ID，或 .local/project-id 這個檔。

沒有 --publish 就只讀 Firestore，產物寫到 .local/。

--publish 會把**模板**寫進 settings/import_prompts，那是 app 內建的「照片直接
匯入」在用的 —— functions/api/roster/import-image.js 從那裡讀。

發佈的是模板不是完成品：服事項目、活動、同工名單、今天這幾個留成 {{...}}，
由 worker 每次呼叫時從 Firestore 現況填。所以**新同工建完帳號就直接生效，
不必重跑這支**。只有改了版面規則、欄名對照、綽號或模板本文才要重新發佈。

各教會自己的規則（例如「會前禱+奉獻拆兩項」、敬拜團展開方式、綽號對照）
放在 .local/import-rules.json，格式見模板文件末段。
"""

import datetime
import json
import pathlib
import sys
import re
import subprocess
import sys
import urllib.error
import urllib.request

# worker 每次呼叫才填的欄位。跟 worker/roster_prompt.js 的 fillPrompt 一致 ——
# 兩邊對不上的話，prompt 會帶著 {{NAMES}} 這種字面值送出去。
LIVE_FIELDS = ("ROLES", "EVENTS", "NAMES", "TODAY", "SAMPLE_ROLE_A", "SAMPLE_ROLE_B")

# 名單一行放幾個人，以及活動清單空的時候寫什麼。這兩個值 worker 也各有一份 ——
# 對不上的話，本機驗過的 prompt 跟線上送出去的就不是同一份，而且沒有東西會
# 叫。functions-tests/prompt_parity.test.js 把兩邊釘在一起。
NAMES_PER_LINE = 6
NO_EVENTS = "（尚未設定）"

from _firestore import LOCAL, ROOT, TYPES, base_url, get, project_id, token  # noqa: F401

TEMPLATE = ROOT / "docs" / "roster-import-prompt.template.md"


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


def fill_live(template: str, *, roles: list[str], events: list[str], names: list[str]) -> str:
    """填上「活的」那幾個欄位。

    這支只給本機預覽用。正式流程是 worker 的 fillPrompt 做同一件事，資料直接
    從 Firestore 現況讀 —— 所以新同工建完帳號就生效，不必有人回來重跑。
    兩邊的輸出要長得一樣，否則本機驗過的跟線上跑的不是同一份 prompt。
    """
    return (
        template.replace("{{ROLES}}", "、".join(roles))
        .replace("{{EVENTS}}", "、".join(events) if events else NO_EVENTS)
        .replace(
            "{{NAMES}}",
            "\n".join(
                "  " + "、".join(names[i : i + NAMES_PER_LINE])
                for i in range(0, len(names), NAMES_PER_LINE)
            ),
        )
        # 有些表的標題根本不寫年份（兒主那張就是），模型只能猜。給它今天，
        # 讓它挑離今天最近的那個年份 —— 猜錯年份整份都匯不進去。
        .replace("{{TODAY}}", datetime.date.today().isoformat())
        .replace("{{SAMPLE_ROLE_A}}", roles[0])
        .replace("{{SAMPLE_ROLE_B}}", roles[1] if len(roles) > 1 else roles[0])
    )


def publish(base: str, tok: str, prompts: dict[str, str]) -> None:
    """把產生好的 prompt 寫進 settings/import_prompts。

    只送這一輪真的產生出來的那幾個崇拜（updateMask），所以
    `build-import-prompt.py youth --publish` 不會把另外兩個洗掉。
    """
    mask = "&".join(f"updateMask.fieldPaths={t}" for t in prompts)
    payload = json.dumps(
        {"fields": {t: {"stringValue": body} for t, body in prompts.items()}}
    ).encode()
    request = urllib.request.Request(
        f"{base}/settings/import_prompts?{mask}",
        data=payload,
        method="PATCH",
        headers={"Authorization": f"Bearer {tok}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request) as response:
            json.load(response)
    except urllib.error.HTTPError as e:
        sys.exit(
            f"發佈失敗（HTTP {e.code}）。這個帳號要有寫入 settings/ 的權限。\n"
            + e.read().decode(errors="replace")[:600]
        )
    print(f"\n已發佈到 settings/import_prompts：{'、'.join(TYPES[t] for t in prompts)}")
    print("app 的「照片直接匯入」現在用的就是這一份。")


def main() -> None:
    args = sys.argv[1:]
    should_publish = "--publish" in args
    wanted = [a for a in args if a != "--publish"] or list(TYPES)
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
    published: dict[str, str] = {}
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
                "\n### 綽號對照\n\n表上這些寫法對不到名單，只能查表：\n\n"
                + lines
                + "\n"
            )

        team = rule.get("teamRules", "")
        # 版面規則是三個崇拜差最多的地方（主日整張是轉置的），沒寫的話這一段
        # 就空著 —— 模板本文刻意不再假設「一列一天」。
        layout = rule.get("layoutRules", "")
        # ── 兩類欄位 ──────────────────────────────────────────────────────
        # 「寫的」：版面規則、欄名對照、綽號、敬拜團 —— 有人去改
        # .local/import-rules.json 才會變，發佈時就填好。
        #
        # 「活的」：服事項目、活動、同工名單、今天 —— 隨時會變，**故意留成
        # {{...}}** 交給 worker 每次呼叫時填。烤進去的話，新同工建完帳號還要
        # 有人記得回來重跑這支，而沒人會記得。
        template = (
            body.replace("{{LAYOUT_RULES}}", f"\n{layout}\n" if layout else "")
            .replace("{{EXTRA_ROLE_RULES}}", rule.get("extraRoleRules", ""))
            .replace("{{NICKNAMES}}", nickname_block)
            .replace("{{TEAM_RULES}}", f"\n{team}\n" if team else "")
        )
        remaining = set(re.findall(r"\{\{([A-Z_]+)\}\}", template))
        if remaining != set(LIVE_FIELDS):
            sys.exit(
                "模板剩下的欄位跟 worker 會填的對不上。\n"
                f"  模板裡有：{sorted(remaining)}\n"
                f"  worker 填：{sorted(LIVE_FIELDS)}\n"
                "改了模板的話，worker/roster_prompt.js 的 fillPrompt 要一起改。"
            )

        filled = fill_live(template, roles=roles, events=events, names=names)
        left = re.findall(r"\{\{[A-Z_]+\}\}", filled)
        if left:
            sys.exit(f"填完還有剩下的欄位：{sorted(set(left))}")

        out = LOCAL / f"roster-import-prompt.{service_type}.md"
        # 本機這份是填好的，給 try-gemini-import.py 與肉眼看用。
        out.write_text(filled)
        # 發佈出去的是**模板**，不是上面那份。
        published[service_type] = template
        note = "" if layout else "，⚠ 沒有 layoutRules"
        print(
            f"{TYPES[service_type]}：{out.relative_to(ROOT)}"
            f"（{len(names)} 人、{len(roles)} 個服事項目{note}）"
        )

    if should_publish and published:
        publish(base, tok, published)

    if clashes:
        print("\n⚠ 去掉姓氏後會撞名，這幾位匯入時可能對不到帳號：")
        for given_name, full in clashes.items():
            print(f"    {given_name} → {full}")


if __name__ == "__main__":
    main()
