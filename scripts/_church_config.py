"""共用公開設定；交給部署生成器的同一個 validator，避免兩份 schema 漂移。"""

import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LOCAL = ROOT / ".local"


def load_config() -> dict:
    result = subprocess.run(
        ["node", str(ROOT / "scripts" / "read-church-config.mjs")],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode:
        sys.exit(result.stderr.strip())
    return json.loads(result.stdout)


CONFIG = load_config()
TYPES = {service["id"]: service["label"] for service in CONFIG["services"]}
