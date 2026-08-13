#!/usr/bin/env python3
"""拿真實資料對一份匯入 JSON 做乾式匯入，事先看到 app 會回報什麼。

不重寫比對邏輯 —— 從 Firestore 抓現況之後，產生一支暫時的 Dart 測試去呼叫
app 真正在用的 parseRosterImportJson 與 orderDutiesByTemplate，所以這裡看到
的結果就是按下匯入會看到的結果。

用法：
    python3 scripts/preview-roster-import.py youth roster.json
    python3 scripts/preview-roster-import.py sundayService roster.json
    python3 scripts/preview-roster-import.py children roster.json

只讀 Firestore，不寫入任何東西，也不會碰服事表。
"""

import json
from datetime import date, datetime, timedelta
import pathlib
import re
import subprocess
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
TYPES = {"sundayService": "主日", "youth": "青崇", "children": "兒主"}


def project_id() -> str:
    """repo 是公開的，專案 id 不寫死在版控裡。"""
    import os

    value = os.environ.get("FIREBASE_PROJECT_ID", "").strip()
    if value:
        return value
    path = ROOT / ".local" / "project-id"
    if path.exists():
        return path.read_text().strip()
    sys.exit(
        "找不到 Firebase 專案 id。二選一：\n"
        "  export FIREBASE_PROJECT_ID=你的專案id\n"
        "  echo 你的專案id > .local/project-id"
    )


BASE = (
    f"https://firestore.googleapis.com/v1/projects/{project_id()}"
    "/databases/(default)/documents"
)


def token() -> str:
    result = subprocess.run(
        ["gcloud", "auth", "print-access-token"], capture_output=True, text=True
    )
    if result.returncode != 0 or len(result.stdout.strip()) < 50:
        sys.exit(
            "拿不到 access token。先跑 gcloud auth login，"
            f"並確認該帳號讀得到該專案。\n{result.stderr.strip()}"
        )
    return result.stdout.strip()


def get(path: str, tok: str) -> dict:
    request = urllib.request.Request(
        f"{BASE}/{path}", headers={"Authorization": f"Bearer {tok}"}
    )
    with urllib.request.urlopen(request) as response:
        return json.load(response)


def paged(path: str, tok: str) -> list[dict]:
    docs, page = [], None
    while True:
        joiner = "&" if "?" in path else "?"
        suffix = f"{joiner}pageToken={page}" if page else ""
        data = get(f"{path}{suffix}", tok)
        docs.extend(data.get("documents", []))
        page = data.get("nextPageToken")
        if not page:
            break
    return docs


def dart_literal(value) -> str:
    """把 Python 資料轉成 Dart 字面值。JSON 字串跟 Dart 字串語法夠接近，
    但單引號與 $ 要跳脫（Dart 的字串內插用 $）。"""
    if isinstance(value, str):
        escaped = value.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$")
        return f"'{escaped}'"
    if isinstance(value, list):
        return "[" + ", ".join(dart_literal(v) for v in value) + "]"
    if isinstance(value, set):
        return "{" + ", ".join(dart_literal(v) for v in sorted(value)) + "}"
    if isinstance(value, dict):
        return (
            "{"
            + ", ".join(f"{dart_literal(k)}: {dart_literal(v)}" for k, v in value.items())
            + "}"
        )
    raise TypeError(type(value))


def main() -> None:
    if len(sys.argv) != 3 or sys.argv[1] not in TYPES:
        sys.exit(__doc__)
    service_type, json_path = sys.argv[1], pathlib.Path(sys.argv[2])
    if not json_path.exists():
        sys.exit(f"找不到 {json_path}")

    raw = json_path.read_text()
    try:
        rows = json.loads(raw)
    except json.JSONDecodeError as e:
        sys.exit(f"這份 JSON 本身就解析不了：{e}")
    if not isinstance(rows, list):
        sys.exit("最外層必須是陣列")

    tok = token()

    # ── 名單與「誰能做哪個服事」──────────────────────────────────────────
    users = paged("users?pageSize=300", tok)
    candidate_names, name_to_id, allowed = [], {}, {}
    for doc in users:
        fields = doc.get("fields", {})
        name = fields.get("name", {}).get("stringValue", "").strip()
        if not name:
            continue
        candidate_names.append(name)
        uid = doc["name"].split("/")[-1].strip()
        if uid:
            name_to_id[name] = uid
        for zone in fields.get("zones", {}).get("arrayValue", {}).get("values", []):
            zf = zone.get("mapValue", {}).get("fields", {})
            if zf.get("serviceType", {}).get("stringValue") != service_type:
                continue
            for m in zf.get("ministries", {}).get("arrayValue", {}).get("values", []):
                role = m.get("stringValue", "").strip()
                if role:
                    allowed.setdefault(role, set()).add(name)

    # ── 服事項目樣板與活動選單 ────────────────────────────────────────────
    templates = get("settings/roster_templates", tok).get("fields", {})
    template_roles = [
        v["stringValue"]
        for v in templates.get(service_type, {}).get("arrayValue", {}).get("values", [])
    ]
    options = get("settings/event_options", tok).get("fields", {})
    catalog = [
        v["mapValue"]["fields"]["name"]["stringValue"]
        for v in options.get(service_type, {}).get("arrayValue", {}).get("values", [])
    ]

    # ── app 看得到的服事表日期（決定哪幾天匯不進去）──────────────────────
    #
    # 光看 Firestore 有沒有那份文件是不夠的：app 只載入
    # 「今天 ~ 下一季末」這個區間（firestore_roster_repository 的
    # _filterAndSortRosters），過去的文件還在資料庫裡但匯入時看不到，
    # 一樣會被算成「這幾天沒有匯入」。這裡照同一個區間過濾。
    today = date.today()
    quarter_start_month = ((today.month - 1) // 3) * 3 + 1
    is_last_month = today.month == quarter_start_month + 2
    raw_end_month = quarter_start_month + (5 if is_last_month else 2)
    end_year = today.year + (raw_end_month - 1) // 12
    end_month = (raw_end_month - 1) % 12 + 1
    window_end = date(end_year + end_month // 12, end_month % 12 + 1, 1) - timedelta(days=1)

    existing = set()
    for d in paged("rosters?pageSize=300", tok):
        doc_id = d["name"].split("/")[-1]
        stamp = d.get("fields", {}).get("date", {}).get("timestampValue")
        if not stamp:
            continue
        when = datetime.fromisoformat(stamp.replace("Z", "+00:00")).astimezone().date()
        if today <= when <= window_end:
            existing.add(doc_id)

    # ── 產生一支暫時的 Dart 測試，呼叫真正的 parser ──────────────────────
    test_path = ROOT / "test" / "zz_import_preview_test.dart"
    test_path.write_text(
        f"""// 由 scripts/preview-roster-import.py 產生，跑完會自動刪掉。
import 'package:flutter_test/flutter_test.dart';
import 'package:church_staff_pwa/features/roster/domain/entities/event_option.dart';
import 'package:church_staff_pwa/features/roster/presentation/screens/roster_import_parser.dart';

void main() {{
  test('preview', () {{
    const input = r\"\"\"{raw}\"\"\";
    final result = parseRosterImportJson(
      input: input,
      candidateNames: {dart_literal(candidate_names)},
      allowedByRole: {dart_literal({k: v for k, v in allowed.items()})},
      catalogByName: {{
        for (final name in {dart_literal(catalog)})
          name: EventOption(name: name, color: 0),
      }},
      nameToIdMap: {dart_literal(name_to_id)},
    );
    if (result.error != null) {{
      print('OUT|error|${{result.error}}');
      return;
    }}
    for (final n in result.notInRosterNames) {{ print('OUT|notInList|$n'); }}
    for (final e in result.roleMismatchDetails.entries) {{
      print('OUT|roleMismatch|${{e.key}}|${{e.value.join('、')}}');
    }}
    for (final n in result.otherNames) {{ print('OUT|ambiguous|$n'); }}
    for (final n in result.notInEventCatalog) {{ print('OUT|noColor|$n'); }}
    for (final d in result.dutiesProvidedDates) {{ print('OUT|dutiesDate|$d'); }}
    for (final d in result.eventsProvidedDates) {{ print('OUT|eventsDate|$d'); }}
    // 排序後的樣子，確認每天的項目順序
    for (final e in result.dutiesByDate.entries) {{
      final ordered = orderDutiesByTemplate(e.value, {dart_literal(template_roles)});
      print('OUT|order|${{e.key}}|${{ordered.map((d) => d.role).join(' > ')}}');
    }}
  }});
}}
"""
    )
    try:
        run = subprocess.run(
            ["flutter", "test", str(test_path)],
            capture_output=True,
            text=True,
            cwd=ROOT,
        )
    finally:
        test_path.unlink(missing_ok=True)

    lines = [
        m.group(1)
        for m in re.finditer(r"OUT\|(.*)", run.stdout.replace("\r", "\n"))
    ]
    if not lines:
        sys.exit(
            "parser 沒有跑起來，flutter test 的輸出：\n"
            + (run.stdout[-3000:] or run.stderr[-3000:])
        )

    buckets: dict[str, list[str]] = {}
    for line in lines:
        kind, _, rest = line.partition("|")
        buckets.setdefault(kind, []).append(rest)

    if "error" in buckets:
        print(f"✗ 整份會被擋下來：{buckets['error'][0]}")
        sys.exit(1)

    dates = sorted(set(buckets.get("dutiesDate", []) + buckets.get("eventsDate", [])))
    missing = [
        d for d in dates if f"{d.replace('-', '')}_{service_type}" not in existing
    ]

    print(f"=== 乾式匯入：{TYPES[service_type]} / {json_path.name} ===")
    print(f"共 {len(dates)} 天，其中 {len(dates) - len(missing)} 天匯得進去")

    def section(title: str, items: list[str], note: str = "") -> None:
        if not items:
            return
        print(f"\n{title}{'  ' + note if note else ''}")
        for item in items:
            print(f"  ・{item}")

    section("這幾天沒有匯入", missing, "（服事表裡沒有這些日期）")
    section(
        "沒有設定這個服事",
        [r.replace("|", "：") for r in buckets.get("roleMismatch", [])],
        "（會照樣排進去）",
    )
    section("名單裡沒有這個人", buckets.get("notInList", []), "（會照樣排進去，但收不到提醒）")
    section("不確定是哪一位", buckets.get("ambiguous", []), "（沒有對到帳號）")
    section("活動沒有固定顏色", buckets.get("noColor", []))

    if not any(
        buckets.get(k) for k in ("roleMismatch", "notInList", "ambiguous", "noColor")
    ) and not missing:
        print("\n✓ 全部對得上，匯入後不會有任何未匹配")

    print("\n--- 排序後每天的服事項目 ---")
    for entry in sorted(buckets.get("order", [])):
        day, _, roles = entry.partition("|")
        print(f"  {day}  {roles}")


if __name__ == "__main__":
    main()
