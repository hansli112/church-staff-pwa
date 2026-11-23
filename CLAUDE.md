# 馬大別忙

設計：`docs/design.md`。資料模型與權限規格：`docs/data-model.md`。用語：`CONTEXT.md`。介面原則：`docs/design-principles.md`（審查畫面用 `apple-design` skill）。

## 驗證

改完先跑相關的測試就好，不要每改一點就跑 `scripts/check.sh`，整套要兩分鐘左右。

- App：`cd app && flutter test --no-pub test/<相關的檔>`，再跑 `flutter analyze`。改了 `.arb` 先跑 `flutter gen-l10n`。
- Functions：`cd functions && npm run typecheck`，測試只跑相關的檔：`npx firebase emulators:exec --only firestore,auth,storage --project demo-martha --config ../firebase.json "node --import tsx --test --test-concurrency=1 test/<相關的檔>.test.ts"`。
- Rules：`cd firestore-tests && npm test`。
- 改到 Backend 介面時，才跑 `scripts/check.sh contract`。
- commit 前，對改到的部分跑一次 `scripts/check.sh app`、`functions` 或 `rules`。

## 長時間的指令

- build、emulator、上架這類超過一分鐘的指令，用 background 跑。不要寫 `until … sleep` 迴圈守著。
- push 後不要在 session 裡等 CI。回報已 push 就結束這一輪。發版這類要靠 CI 結果才能往下走的，用 background 跑 `gh run watch`。

## Agent skills

### Issue tracker

Issues and specs live in GitHub Issues on `hansli112/church-staff-pwa`, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
