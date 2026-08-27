#!/usr/bin/env bash
#
# 把行事曆寫入需要的執行期變數推到 Cloudflare Pages。
#
# 為什麼要有這支：GOOGLE_SERVICE_ACCOUNT_JSON 是一整份多行 JSON，貼進
# dashboard 的輸入框很容易漏字或被改成單行，而失敗的樣子是部署後才發現
# 「伺服器設定不完整」。用 CLI 從檔案直接送就沒有這個問題。
#
# 這三個是 **執行期** 變數（Pages Functions 讀的），跟 build 階段的
# --dart-define 是兩套，要分開設。
#
# 用法：
#     wrangler login          # 只有第一次，或 token 過期時
#     bash scripts/push-calendar-secrets.sh
#
# 需要 .local/service-account.json（已 gitignore）。
#
# LINE 通知（選用）：另外再讀 .local/n8n-notify-url 和 .local/n8n-notify-secret，
# 兩個都在才會推，而且只推 production —— Preview 站點不該把測試資料發進群組。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_NAME="${CLOUDFLARE_PAGES_PROJECT:-church-staff-pwa}"
KEY_FILE="$ROOT/.local/service-account.json"

WRANGLER=(npx --yes wrangler)

if [[ ! -f "$KEY_FILE" ]]; then
  echo "找不到 $KEY_FILE" >&2
  echo "先產生 service account 金鑰再跑這支。" >&2
  exit 1
fi

# Firebase 專案 id 決定 Function 去哪個 Firestore 查管理員身分。讀錯專案的話
# 每個人都會被判成沒有權限。
firebase_project_id() {
  if [[ -n "${FIREBASE_PROJECT_ID:-}" ]]; then
    printf '%s' "$FIREBASE_PROJECT_ID"
  elif [[ -f "$ROOT/.local/project-id" ]]; then
    tr -d '[:space:]' < "$ROOT/.local/project-id"
  else
    gh variable get FIREBASE_PROJECT_ID --repo "$(gh repo view --json nameWithOwner -q .nameWithOwner)"
  fi
}

calendar_id() {
  if [[ -n "${GOOGLE_CALENDAR_ID:-}" ]]; then
    printf '%s' "$GOOGLE_CALENDAR_ID"
  elif [[ -f "$ROOT/.local/calendar-id" ]]; then
    tr -d '[:space:]' < "$ROOT/.local/calendar-id"
  else
    gh variable get GOOGLE_CALENDAR_ID --repo "$(gh repo view --json nameWithOwner -q .nameWithOwner)"
  fi
}

PROJECT_ID="$(firebase_project_id)"
CALENDAR_ID="$(calendar_id)"

if [[ -z "$PROJECT_ID" || -z "$CALENDAR_ID" ]]; then
  echo "拿不到 FIREBASE_PROJECT_ID 或 GOOGLE_CALENDAR_ID。" >&2
  echo "用環境變數指定，或先跑 gh auth login。" >&2
  exit 1
fi

# Production 與 Preview 是分開的兩組設定。只設 production 的話，push 到 dev
# 產生的預覽站點會回「伺服器設定不完整」，而 production 看起來一切正常。
for environment in production preview; do
  echo "── $environment ──"

  # 全部走 secret：值不會回顯在 dashboard 或 wrangler 的輸出裡，而 Function
  # 讀的方式完全相同。
  "${WRANGLER[@]}" pages secret put GOOGLE_SERVICE_ACCOUNT_JSON \
    --project-name "$PROJECT_NAME" --env "$environment" < "$KEY_FILE"

  printf '%s' "$PROJECT_ID" | "${WRANGLER[@]}" pages secret put FIREBASE_PROJECT_ID \
    --project-name "$PROJECT_NAME" --env "$environment"

  printf '%s' "$CALENDAR_ID" | "${WRANGLER[@]}" pages secret put GOOGLE_CALENDAR_ID \
    --project-name "$PROJECT_NAME" --env "$environment"
done

# ── LINE 通知（選用）────────────────────────────────────────────────────────
# 兩個檔案都在才推。缺一個就整個跳過：Function 那邊也是任一沒設就關掉通知，
# 只推一半只會得到「設了卻不會動」這種最難查的狀態。
notify_url() {
  if [[ -n "${NOTIFY_WEBHOOK_URL:-}" ]]; then
    printf '%s' "$NOTIFY_WEBHOOK_URL"
  elif [[ -f "$ROOT/.local/n8n-notify-url" ]]; then
    tr -d '[:space:]' < "$ROOT/.local/n8n-notify-url"
  fi
}

notify_secret() {
  if [[ -n "${NOTIFY_WEBHOOK_SECRET:-}" ]]; then
    printf '%s' "$NOTIFY_WEBHOOK_SECRET"
  elif [[ -f "$ROOT/.local/n8n-notify-secret" ]]; then
    tr -d '[:space:]' < "$ROOT/.local/n8n-notify-secret"
  fi
}

NOTIFY_URL="$(notify_url)"
NOTIFY_SECRET="$(notify_secret)"

echo
if [[ -n "$NOTIFY_URL" && -n "$NOTIFY_SECRET" ]]; then
  echo "── LINE 通知（production only）──"
  printf '%s' "$NOTIFY_URL" | "${WRANGLER[@]}" pages secret put NOTIFY_WEBHOOK_URL \
    --project-name "$PROJECT_NAME" --env production
  printf '%s' "$NOTIFY_SECRET" | "${WRANGLER[@]}" pages secret put NOTIFY_WEBHOOK_SECRET \
    --project-name "$PROJECT_NAME" --env production
else
  echo "略過 LINE 通知：找不到 .local/n8n-notify-url 或 .local/n8n-notify-secret。"
fi

echo
echo "完成。下一次部署才會生效 —— 現有的 deployment 不會自動帶到新設定。"
