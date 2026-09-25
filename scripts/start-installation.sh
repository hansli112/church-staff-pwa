#!/usr/bin/env bash
# Bootstrap only: official pinned tools, then the private installer. No cloud
# resource is created until the person authorizes and confirms in the wizard.
set -euo pipefail
umask 077

if [[ "${1:-}" == '--help' ]]; then
  printf '%s\n' 'Usage: bash scripts/start-installation.sh' '在自己的 Google Cloud Shell 準備固定版本工具，啟動私人安裝精靈；不會自動建立雲端資源。'
  exit 0
fi
if [[ $# -ne 0 ]]; then printf '%s\n' '不接受額外參數。' >&2; exit 1; fi
if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 || "${CLOUD_SHELL:-}" != true ]]; then
  printf '%s\n' '請在自己的 Google Cloud Shell 執行此入口（Linux x86_64）。' >&2
  exit 1
fi
for tool in curl tar xz sha256sum sha512sum base64 awk df mktemp stat od tr; do
  command -v "$tool" >/dev/null || { printf '缺少必要工具：%s\n' "$tool" >&2; exit 1; }
done
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
[[ -f "$ROOT/scripts/install-core.mjs" ]] || { printf '%s\n' '找不到安裝主程式，請重新開啟完整教學。' >&2; exit 1; }
# The VM disk, not Cloud Shell's 5 GB persistent home, holds SDKs and caches.
AVAILABLE_KB="$(df -Pk /tmp | awk 'NR==2 {print $4}')"
if [[ ! "$AVAILABLE_KB" =~ ^[0-9]+$ || "$AVAILABLE_KB" -lt 8388608 ]]; then
  printf '%s\n' 'Cloud Shell VM 暫存磁碟至少需要 8 GiB 可用空間；請重啟 Cloud Shell 後再試。' >&2
  exit 1
fi
BASE="/tmp/church-core-installer-${UID}"
if [[ -e "$BASE" || -L "$BASE" ]]; then
  [[ -d "$BASE" && ! -L "$BASE" && -O "$BASE" && "$(stat -c %a "$BASE")" == 700 ]] || { printf '%s\n' '安裝器暫存目錄權限不符，已停止。' >&2; exit 1; }
else
  mkdir -m 700 "$BASE"
fi
# Only this launcher's marked, same-owner, no-longer-running sessions qualify.
# Never enumerate or remove the operator's ~/.wrangler or gcloud profiles.
for old in "$BASE"/session-*; do
  [[ -d "$old" && ! -L "$old" && -O "$old" && -f "$old/.installer-pid" && ! -L "$old/.installer-pid" ]] || continue
  read -r pid < "$old/.installer-pid" || continue
  if [[ "$pid" =~ ^[0-9]+$ ]] && ! kill -0 "$pid" 2>/dev/null; then rm -rf -- "$old"; fi
done
TOOLS="$(mktemp -d "$BASE/session-XXXXXXXX")"
printf '%s\n' "$$" > "$TOOLS/.installer-pid"
server_pid=''
cleanup() {
  trap - EXIT INT TERM
  if [[ -n "$server_pid" ]]; then kill -TERM "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; fi
  [[ -d "$TOOLS" && ! -L "$TOOLS" && -O "$TOOLS" ]] && rm -rf -- "$TOOLS"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

NODE_VERSION=22.22.0
FLUTTER_VERSION=3.41.0
WRANGLER_VERSION=4.138.0
# Official release manifests, pinned here rather than trusting a mutable latest.
NODE_SHA256=9aa8e9d2298ab68c600bd6fb86a6c13bce11a4eca1ba9b39d79fa021755d7c37
FLUTTER_SHA256=368ae5b6993c51861324e704c42d61c4e290fba7213a88fd0e9fec15ded54599
WRANGLER_SHA512_B64='jxNlOfssgyMo+eUcWBX+BxAuU6/AZAn8mNimicLv4igxbRH40OFRBMtGJT8z4kJwXPJriy1O4TB7A8lYjKb82w=='
download() { curl --proto '=https' --tlsv1.2 --fail --silent --show-error --retry 3 --max-time 900 "$1" -o "$2"; }
verify() { printf '%s  %s\n' "$1" "$2" | sha256sum --check --status || { printf '%s\n' '官方工具 checksum 不符，已停止；沒有執行下載內容。' >&2; exit 1; }; }
printf '%s\n' '正在準備固定版本 Node、Flutter 與 Wrangler（首次需要數分鐘）。'
download "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" "$TOOLS/node.tar.xz"
verify "$NODE_SHA256" "$TOOLS/node.tar.xz"
tar -xJf "$TOOLS/node.tar.xz" -C "$TOOLS"
rm "$TOOLS/node.tar.xz"
export PATH="$TOOLS/node-v${NODE_VERSION}-linux-x64/bin:$PATH"
download "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" "$TOOLS/flutter.tar.xz"
verify "$FLUTTER_SHA256" "$TOOLS/flutter.tar.xz"
tar -xJf "$TOOLS/flutter.tar.xz" -C "$TOOLS"
rm "$TOOLS/flutter.tar.xz"
mkdir -m 700 "$TOOLS/npm" "$TOOLS/npm-cache" "$TOOLS/pub-cache" "$TOOLS/builds" "$TOOLS/sessions"
: > "$TOOLS/npmrc"
: > "$TOOLS/global-npmrc"
download "https://registry.npmjs.org/wrangler/-/wrangler-${WRANGLER_VERSION}.tgz" "$TOOLS/wrangler.tgz"
EXPECTED="$(printf '%s' "$WRANGLER_SHA512_B64" | base64 -d | od -An -v -tx1 | tr -d ' \n')"
printf '%s  %s\n' "$EXPECTED" "$TOOLS/wrangler.tgz" | sha512sum --check --status || { printf '%s\n' 'Wrangler checksum 不符，已停止。' >&2; exit 1; }
# npm validates dependency tarball integrity. Disable lifecycle scripts and do
# not read ~/.npmrc, inherited auth, or the checkout's production environment.
(cd "$TOOLS/npm" && env -i PATH="$PATH" HOME="$TOOLS/npm" npm_config_cache="$TOOLS/npm-cache" \
  npm_config_userconfig="$TOOLS/npmrc" npm_config_globalconfig="$TOOLS/global-npmrc" \
  npm install --prefix "$TOOLS/npm" --ignore-scripts --no-audit --no-fund \
  --registry=https://registry.npmjs.org "$TOOLS/wrangler.tgz")
rm "$TOOLS/wrangler.tgz"
export INSTALLER_TOOL_ROOT="$TOOLS"
export INSTALLER_FLUTTER="$TOOLS/flutter/bin/flutter"
export INSTALLER_WRANGLER="$TOOLS/npm/node_modules/.bin/wrangler"
export INSTALLER_BUILD_ROOT="$TOOLS/builds"
export INSTALLER_SESSION_ROOT="$TOOLS/sessions"
export PUB_CACHE="$TOOLS/pub-cache"
export FLUTTER_SUPPRESS_ANALYTICS=true
export DART_SUPPRESS_ANALYTICS=true
# Do not replace HOME here: Google Cloud Shell's own authorization remains the
# operator identity. Adapters isolate their child-process environments instead.
printf '%s\n' '工具已就緒。開啟私人 Web Preview 後，仍須本人登入、填表並確認建立資源。'
unset NODE_OPTIONS NODE_EXTRA_CA_CERTS
node "$ROOT/scripts/install-core.mjs" --cloud-shell &
server_pid=$!
wait "$server_pid"
server_pid=''
