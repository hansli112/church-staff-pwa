"""Offline tests; only an explicitly selected loopback emulator may receive HTTP."""

import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
from types import ModuleType
import unittest
from unittest.mock import patch
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parent.parent


def load_script():
    # Import the real publisher without loading private config or gcloud tokens.
    config = ModuleType("_church_config")
    config.CONFIG = {"timeZone": "UTC"}
    config.TYPES = {
        "sundayService": "主日",
        "mid-week": "週間",
        "other_service": "其他",
    }
    firestore = ModuleType("_firestore")
    firestore.ROOT = ROOT
    firestore.LOCAL = ROOT / "unused-test-data"
    firestore.TYPES = config.TYPES

    def forbidden(*args, **kwargs):
        raise AssertionError("Tests must not read credentials or real Firestore")

    for name in ("base_url", "get", "project_id", "token"):
        setattr(firestore, name, forbidden)
    spec = importlib.util.spec_from_file_location(
        "build_import_prompt", ROOT / "scripts/build-import-prompt.py"
    )
    module = importlib.util.module_from_spec(spec)
    with (
        patch.dict(
            os.environ,
            {"CHURCH_CONFIG_FILE": str(ROOT / "config/church.example.json")},
        ),
        patch.dict(sys.modules, {"_church_config": config, "_firestore": firestore}),
    ):
        spec.loader.exec_module(module)
    return module


SCRIPT = load_script()


class PublishPromptTests(unittest.TestCase):
    def capture_request(self, prompts):
        with (
            patch.object(
                SCRIPT.urllib.request, "urlopen", return_value=io.BytesIO(b"{}")
            ) as send,
            contextlib.redirect_stdout(io.StringIO()),
        ):
            SCRIPT.publish("https://example.invalid/documents", "test-token", prompts)
        send.assert_called_once()
        return send.call_args.args[0]

    def test_hyphenated_service_is_one_quoted_and_url_encoded_field(self):
        request = self.capture_request({"mid-week": "test prompt"})
        url = urllib.parse.urlsplit(request.full_url)
        self.assertEqual(url.path, "/documents/settings/import_prompts")
        self.assertEqual(url.query, "updateMask.fieldPaths=%60mid-week%60")
        self.assertEqual(
            urllib.parse.parse_qs(url.query),
            {"updateMask.fieldPaths": ["`mid-week`"]},
        )
        self.assertEqual(request.get_method(), "PATCH")
        self.assertEqual(
            json.loads(request.data),
            {"fields": {"mid-week": {"stringValue": "test prompt"}}},
        )

    def test_only_requested_services_are_in_each_update_mask_and_payload(self):
        prompts = {"mid-week": "new midweek", "other_service": "new other"}
        request = self.capture_request(prompts)
        self.assertEqual(
            urllib.parse.parse_qs(urllib.parse.urlsplit(request.full_url).query),
            {"updateMask.fieldPaths": ["`mid-week`", "`other_service`"]},
        )
        self.assertEqual(set(json.loads(request.data)["fields"]), set(prompts))
        self.assertNotIn("sundayService", request.full_url)
        self.assertNotIn("sundayService", json.loads(request.data)["fields"])

    def test_legacy_service_ids_remain_top_level_fields(self):
        request = self.capture_request({"sundayService": "legacy prompt"})
        self.assertEqual(
            urllib.parse.parse_qs(urllib.parse.urlsplit(request.full_url).query),
            {"updateMask.fieldPaths": ["`sundayService`"]},
        )
        self.assertEqual(
            json.loads(request.data)["fields"],
            {"sundayService": {"stringValue": "legacy prompt"}},
        )

    @unittest.skipUnless(
        os.environ.get("FIRESTORE_EMULATOR_HOST"),
        "Set FIRESTORE_EMULATOR_HOST to a dedicated loopback emulator",
    )
    def test_emulator_preserves_other_prompts_when_publishing_hyphenated_id(self):
        host = os.environ["FIRESTORE_EMULATOR_HOST"]
        target = urllib.parse.urlsplit(f"http://{host}")
        self.assertIn(target.hostname, {"127.0.0.1", "localhost", "::1"})
        self.assertIsNotNone(target.port)
        self.assertIsNone(target.username)
        self.assertIsNone(target.password)
        self.assertEqual(target.path, "")
        self.assertEqual(target.query, "")
        self.assertEqual(target.fragment, "")
        base = (
            f"http://{host}/v1/projects/demo-prompt-mask"
            "/databases/(default)/documents"
        )
        url = f"{base}/settings/import_prompts"
        original = {"fields": {"sundayService": {"stringValue": "keep this"}}}
        seed = urllib.request.Request(
            url,
            data=json.dumps(original).encode(),
            method="PATCH",
            headers={"Content-Type": "application/json", "Authorization": "Bearer owner"},
        )
        with urllib.request.urlopen(seed, timeout=5) as response:
            self.assertEqual(response.status, 200)
        with contextlib.redirect_stdout(io.StringIO()):
            SCRIPT.publish(base, "owner", {"mid-week": "new prompt"})
        read = urllib.request.Request(url, headers={"Authorization": "Bearer owner"})
        with urllib.request.urlopen(read, timeout=5) as response:
            actual = json.load(response)
        self.assertEqual(
            actual["fields"],
            {**original["fields"], "mid-week": {"stringValue": "new prompt"}},
        )


if __name__ == "__main__":
    unittest.main()
