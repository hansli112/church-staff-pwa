#!/usr/bin/env python3
"""把服事表照片丟給 Gemini，產生匯入用的 JSON，並接上乾式匯入驗一次。

這支是 app 內建「照片直接匯入」之前的試水溫版本：同一套 prompt、同一份
Firestore 現況、同一個 parser，只是跑在本機而不是 Cloudflare Function。
先用它確認 Gemini 讀不讀得懂那幾張表，值得再搬進 worker。

用法：
    uv run scripts/try-gemini-import.py youth 服事表.jpg
    uv run scripts/try-gemini-import.py youth 上半.jpg 下半.jpg --preview
    uv run scripts/try-gemini-import.py --list-models

    --preview   轉完直接接 scripts/preview-roster-import.py 做乾式匯入
    --model X   換一個模型（預設見 DEFAULT_MODEL，或用 GEMINI_MODEL 環境變數）

API key 二選一，**不要打在命令列上**（會進 shell 紀錄）：
    export GEMINI_API_KEY=...
    echo ... > .local/gemini-api-key

⚠ 送出去的內容包含同工姓名（prompt 裡的白名單）與整張服事表。AI Studio 的
  免費層，Google 會用送進去的資料改善產品；付費層不會。是否可接受請自行
  判斷 —— 這跟 build-claude-skill.py 上傳名單到 claude.ai 是同一個判斷題。

產物都在 .local/（已 gitignore）。
"""

import argparse
import base64
import json
import os
import pathlib
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
LOCAL = ROOT / ".local"
from _church_config import CONFIG, TYPES

# 模型名稱會改版，所以留得下來覆寫。跑 --list-models 看現在有哪些。
#
# 不用 `gemini-flash-latest` 這種別名：別名指到當紅那一支，最容易 503。
# 釘版本也讓同一張圖轉兩次結果一致。
DEFAULT_MODEL = "gemini-3.6-flash"
# v1，不是 v1beta —— 新的模型在 v1beta 上會回一個 0 byte 的 404，
# 看起來像模型不存在，其實是走錯版本。
API_BASE = "https://generativelanguage.googleapis.com/v1"

# Gemini 的 inline data 是整包塞進請求裡的，太大會被擋。超過這個大小先自己
# 縮圖，不要讓它跑到一半才失敗。
MAX_IMAGE_BYTES = 7 * 1024 * 1024

# 503（尖峰）與 429（額度）都是等一下就好的，免費層碰到是常態。
RETRY_CODES = {429, 503}
RETRY_DELAYS = (5, 15, 40)

MIME_BY_SUFFIX = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
    ".heic": "image/heic",
    ".heif": "image/heif",
}


def api_key() -> str:
    value = os.environ.get("GEMINI_API_KEY", "").strip()
    if value:
        return value
    path = LOCAL / "gemini-api-key"
    if path.exists():
        value = path.read_text().strip()
        if value:
            return value
    sys.exit(
        "找不到 Gemini API key。到 https://aistudio.google.com/apikey 拿一個，然後二選一：\n"
        "  export GEMINI_API_KEY=...\n"
        "  echo ... > .local/gemini-api-key"
    )


def call_api(path: str, key: str, body: dict | None = None) -> dict:
    """打 Gemini API。

    key 走 `X-goog-api-key` header，不走 query string —— query string 會進
    代理與伺服器的存取日誌，header 不會。
    """
    url = f"{API_BASE}/{path}"
    data = json.dumps(body).encode() if body is not None else None
    headers = {"X-goog-api-key": key}
    if data:
        headers["Content-Type"] = "application/json"

    for attempt, delay in enumerate((*RETRY_DELAYS, None)):
        request = urllib.request.Request(url, data=data, headers=headers)
        try:
            with urllib.request.urlopen(request) as response:
                return json.load(response)
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")[:1200]
            if e.code in RETRY_CODES and delay is not None:
                print(f"  HTTP {e.code}，{delay} 秒後重試（第 {attempt + 1} 次）…")
                time.sleep(delay)
                continue
            hint = ""
            if e.code == 404:
                hint = "\n模型名稱可能已經改版，跑 --list-models 看現在有哪些。"
            elif e.code == 429:
                hint = "\n額度用完了，等久一點再試。"
            elif e.code == 503:
                hint = "\n模型在尖峰，重試幾次都不行就換 --model 或晚點再跑。"
            elif e.code in (400, 403):
                hint = "\nkey 不對、或這個 key 沒開 Generative Language API。"
            sys.exit(f"Gemini 回 HTTP {e.code}{hint}\n{detail}")
    raise AssertionError("unreachable")


def list_models(key: str) -> None:
    data = call_api("models?pageSize=200", key)
    for model in data.get("models", []):
        name = model.get("name", "").removeprefix("models/")
        methods = model.get("supportedGenerationMethods", [])
        if "generateContent" not in methods:
            continue
        print(f"  {name}\t{model.get('displayName', '')}")


def build_prompt(service_type: str) -> str:
    """呼叫既有的 build-import-prompt.py，讀它產生的成品。

    prompt 的組法刻意不在這裡重寫一份 —— 那支是唯一的來源，兩邊各有一份
    早晚會不一樣，而不一樣的那天不會有人發現。
    """
    script = ROOT / "scripts" / "build-import-prompt.py"
    result = subprocess.run(
        [sys.executable, str(script), service_type],
        capture_output=True,
        text=True,
        cwd=ROOT,
    )
    if result.returncode != 0:
        sys.exit(f"產生 prompt 失敗：\n{result.stdout}{result.stderr}")
    path = LOCAL / f"roster-import-prompt.{service_type}.md"
    if not path.exists():
        sys.exit(f"build-import-prompt.py 跑完了，但沒看到 {path.relative_to(ROOT)}")
    print(result.stdout.strip())
    return path.read_text()


def image_part(path: pathlib.Path) -> dict:
    if not path.exists():
        sys.exit(f"找不到圖檔：{path}")
    mime = MIME_BY_SUFFIX.get(path.suffix.lower())
    if not mime:
        sys.exit(
            f"不支援的圖檔格式：{path.suffix}"
            f"（可用：{'、'.join(sorted(MIME_BY_SUFFIX))}）"
        )
    raw = path.read_bytes()
    if len(raw) > MAX_IMAGE_BYTES:
        sys.exit(
            f"{path.name} 有 {len(raw) / 1024 / 1024:.1f}MB，超過 "
            f"{MAX_IMAGE_BYTES // 1024 // 1024}MB。先縮一下，例如：\n"
            f"  magick {path} -resize 2000x {path.stem}-small.jpg"
        )
    return {"inline_data": {"mime_type": mime, "data": base64.b64encode(raw).decode()}}


def extract_json(text: str) -> str:
    """prompt 要求不要圍欄，但模型偶爾還是會加。寬容一點，不要為這個重跑一次。"""
    stripped = text.strip()
    fenced = re.match(r"^```(?:json)?\s*\n(.*?)\n```$", stripped, re.S)
    if fenced:
        return fenced.group(1).strip()
    return stripped


def main() -> None:
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("service_type", nargs="?", help=f"崇拜類別：{', '.join(TYPES)}")
    parser.add_argument("images", nargs="*", help="服事表照片，可以給多張")
    parser.add_argument("--model", default=os.environ.get("GEMINI_MODEL", DEFAULT_MODEL))
    parser.add_argument("--preview", action="store_true", help="轉完接乾式匯入")
    parser.add_argument("--list-models", action="store_true")
    args = parser.parse_args()

    key = api_key()

    if args.list_models:
        list_models(key)
        return

    if not args.service_type or not args.images:
        parser.error("要給崇拜類別與至少一張照片。用法見檔案開頭的 docstring。")
    if args.service_type not in TYPES:
        parser.error(f"未知的崇拜類別「{args.service_type}」，可用：{', '.join(TYPES)}")

    prompt = build_prompt(args.service_type)
    parts = [{"text": prompt}] + [
        image_part(pathlib.Path(p)) for p in args.images
    ]

    print(f"\n送 {len(args.images)} 張圖給 {args.model} …")
    response = call_api(
        f"models/{args.model}:generateContent",
        key,
        {
            "contents": [{"parts": parts}],
            "generationConfig": {
                # 服事表轉 JSON 沒有「創意」的空間，同一張圖每次都該轉出同一份。
                "temperature": 0,
                # 直接叫它吐 JSON，省掉圍欄與前後廢話。
                "responseMimeType": "application/json",
            },
        },
    )

    candidates = response.get("candidates") or []
    if not candidates:
        # 被安全過濾掉、或整份被擋下來時走這裡。原文印出來才查得下去。
        sys.exit(f"Gemini 沒有回任何結果：\n{json.dumps(response, ensure_ascii=False)[:1200]}")
    candidate = candidates[0]
    text = "".join(
        part.get("text", "") for part in candidate.get("content", {}).get("parts", [])
    )
    if not text.strip():
        reason = candidate.get("finishReason", "（沒說原因）")
        sys.exit(f"Gemini 回了空的內容，finishReason={reason}")

    payload = extract_json(text)
    try:
        parsed = json.loads(payload)
    except json.JSONDecodeError as e:
        out = LOCAL / f"roster-import.{args.service_type}.raw.txt"
        out.write_text(text)
        sys.exit(f"回來的不是合法 JSON（{e}）。原文留在 {out.relative_to(ROOT)}")

    LOCAL.mkdir(exist_ok=True)
    out = LOCAL / f"roster-import.{args.service_type}.json"
    out.write_text(json.dumps(parsed, ensure_ascii=False, indent=2) + "\n")

    days = len(parsed) if isinstance(parsed, list) else "?"
    usage = response.get("usageMetadata", {})
    print(f"✓ {days} 天 → {out.relative_to(ROOT)}")
    if usage:
        print(
            f"  token：輸入 {usage.get('promptTokenCount', '?')}、"
            f"輸出 {usage.get('candidatesTokenCount', '?')}"
        )

    if args.preview:
        print()
        subprocess.run(
            [
                sys.executable,
                str(ROOT / "scripts" / "preview-roster-import.py"),
                args.service_type,
                str(out),
            ],
            cwd=ROOT,
        )
    else:
        print(
            f"\n乾式匯入看一下對不對：\n"
            f"  uv run scripts/preview-roster-import.py {args.service_type} "
            f"{out.relative_to(ROOT)}"
        )


if __name__ == "__main__":
    main()
