#!/usr/bin/env python3
"""打包一個可以上傳到 claude.ai 的獨立技能。

用途：人不在這台電腦前（例如只有手機）時，照樣能把服事表照片轉成匯入用的
JSON。上傳一次，之後在 claude.ai 附上照片說「轉 json」就好。

跟本機的 /roster-import 技能的差別：
  - 本機版會做乾式匯入（呼叫 app 真正的 parser 驗一次）
  - 這個版本沒有那步 —— claude.ai 上沒有 repo 也沒有 Firestore。
    規則全部寫死在技能裡，錯了要等 app 的匯入結果視窗才會知道。

用法：
    python3 scripts/build-claude-skill.py

產物在 .local/claude-skill/（已 gitignore）：
    roster-import/SKILL.md
    roster-import.zip      ← 上傳這個

⚠ 產物內含同工姓名。上傳等於把名單送到 claude.ai，是否可接受請自行判斷。
"""

import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LOCAL = ROOT / ".local"
OUT = LOCAL / "claude-skill"
TYPES = {"sundayService": "主日", "youth": "青崇", "children": "兒主"}

FRONTMATTER = """---
name: roster-import
description: 把教會服事表的照片轉成可以匯入服事表 app 的 JSON。使用者附上服事表照片、或說「服事表轉 json」「這張表幫我轉」時使用。
---

# 服事表照片轉匯入 JSON

## 第一步：判斷是哪一個崇拜

照片標題通常寫得出來（例如「青年崇拜服事表」「兒童主日學服事表」）。
判斷不出來就**問使用者**，不要猜 —— 三個崇拜的服事項目不一樣
（主日是「投影」，青崇是「PPT」），弄錯整份都會對不上。

對應到下面的章節：

| 標題出現 | 用哪一節 |
|---|---|
| 主日崇拜、主日 | 主日 |
| 青年崇拜、青崇 | 青崇 |
| 兒童主日學、兒主 | 兒主 |

## 第二步：照那一節的規則轉

只輸出 JSON，不要任何說明文字，不要用程式碼圍欄包起來。
使用者要的是可以直接複製貼進 app 的東西。

## 第三步：轉完提醒一句

轉完之後用一句話說明：哪些名字你不太確定、哪些日期可能不在 app 的範圍內
（app 只有本季與下季的服事表）。使用者匯入後 app 也會再報一次。

---
"""


def main() -> None:
    # 先把三份最新的 prompt 產生出來（會從 Firestore 抓現況）。
    build = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "build-import-prompt.py")],
        cwd=ROOT,
    )
    if build.returncode != 0:
        sys.exit("build-import-prompt.py 失敗，先把那支修好")

    sections = []
    for service_type, label in TYPES.items():
        path = LOCAL / f"roster-import-prompt.{service_type}.md"
        if not path.exists():
            print(f"⚠ 找不到 {path.name}，跳過 {label}")
            continue
        body = path.read_text().strip()
        # 每一節的標題降一級，避免跟技能本身的 H1/H2 打架。
        body = re.sub(r"^## ", "### ", body, flags=re.M)
        sections.append(f"## {label}\n\n{body}\n")

    if not sections:
        sys.exit("一份 prompt 都沒有，中止")

    skill_dir = OUT / "roster-import"
    if OUT.exists():
        shutil.rmtree(OUT)
    skill_dir.mkdir(parents=True)
    (skill_dir / "SKILL.md").write_text(FRONTMATTER + "\n".join(sections))

    archive = shutil.make_archive(str(OUT / "roster-import"), "zip", OUT, "roster-import")
    size = pathlib.Path(archive).stat().st_size

    print()
    print(f"技能已產生：{skill_dir.relative_to(ROOT)}/SKILL.md")
    print(f"上傳這個：  {pathlib.Path(archive).relative_to(ROOT)}（{size // 1024} KB）")
    print()
    print("⚠ 內含同工姓名。上傳等於把名單送到 claude.ai。")
    print("   名單有異動時重跑這支，再上傳一次覆蓋。")


if __name__ == "__main__":
    main()
