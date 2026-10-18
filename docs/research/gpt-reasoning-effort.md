# GPT reasoning effort：官方預設與起始建議

查核日期：2026-10-09。只採 OpenAI 官方文件；區分「API 不傳參數時的預設」與「特定工具／任務的建議起點」。Repo 未有研究筆記慣例，依本次指定存於 `docs/research/`。未修改設定或程式。

## 精簡結論

**不是所有 GPT 都同一個預設。** 當前公開文件已列出 **GPT-6.1 Sol**，其 API `reasoning.effort` 預設是 **`medium`**；這是公開 model page 的證據，不是從執行環境模型 ID 推定。[1][2]

**寫程式／agent：先用該模型與 client 的官方預設，再依任務難度提高。** 最新 Codex 文件對 GPT-6.1 Sol 建議從 client default 開始；對 Luna 建議 High、Astra 建議 Light（設定值 `low`），所以不能將所有最新模型都一律設成 `medium`。[4] API reasoning guide 將 `medium` 作為多數工作負載起點，複雜 workflow／agentic task 建議 `high`，並依複雜度比較 `medium` 與 `high`；`xhigh` 應在 eval 證明額外延遲與成本值得時才用。[3]

## API default（省略 effort 參數）

Responses API 的參數名稱是 `reasoning.effort`；Chat Completions 使用 `reasoning_effort`。支援的值與預設取決於模型，不能把通用參數說明套用到所有型號。[3]

| 模型 | 官方明載預設 | 證據／範圍 |
| --- | --- | --- |
| GPT-6.1 Sol (`gpt-6.1-sol`) | `medium` | Model page 明載；支援 `low/medium/high/xhigh/max`，不支援 `none/minimal`。[1] |
| GPT-6 Sol、GPT-6 Luna | `medium` | 當前 reasoning guide 明載。[3] |
| GPT-6 Astra | 本次引用的 latest-model／reasoning guide 未明載其 API default | 不從 Sol 的 default 或 Codex 建議反推。[2][3] |
| GPT-5.6 | `medium` | Reasoning guide 明載，`standard`／`pro` 兩種 mode 都一樣。[3] |
| GPT-5.5 | `medium` | Reasoning guide 明載。[3] |
| GPT-5.2 (`gpt-5.2`，非 Pro) | `none` | Model page 與該代 migration guide 一致。[6][7] |
| GPT-5.1 (`gpt-5.1`) | `none` | Model page 與該代 migration guide 一致。[5][7] |
| GPT-5 (`gpt-5`) | `medium` | GPT-5.2 migration guide 明確比較三代預設。[7] |

上述為具名模型，不能外推至其 Pro、Codex、mini 等變體。`reasoning.mode` 的 `standard` 預設也不是 effort 的預設；官方說兩者獨立。[3]

## 官方建議不是 API default

- **當前 Codex**：[4] 原文：
  - “For GPT-6.1 Sol, start with the reasoning effort available by default in your client and adjust based on the task.”
  - “Start with **High** for Luna or **Light** for Astra.”／“In configuration, Astra’s Light setting is `low`.”
  - 一般原則：“Start with the default effort and increase it when the task needs deeper planning or analysis.”
  - 文件提醒不同世代的 effort 不完全對等；client／account 的 Power default 不是統一 API default。
- **API 多數工作負載 vs. 複雜 agent**：[3] `medium` 為 “Default configuration for most workloads”，包含 agentic coding；`high` 為 “Recommended for complex workflows and agentic tasks”，並建議按複雜度評估兩者。
- **GPT-5.3-Codex 世代的官方 prompting guide**：[8] “We recommend ‘medium’ reasoning effort as a good all-around interactive coding model that balances intelligence and speed.”；最難任務可用 `high`／`xhigh`。這是該代寫程式的起始建議，文件未據此宣告省略 API 參數的 default，也不應覆蓋最新 Astra／Luna 建議。
- **GPT-5.2 migration guide（歷史／已封存）**：[7] GPT-5／5.1 遷移原則為保留既有 effort（`minimal` → `none`）；GPT-4o／4.1 → 5.2 則從 `none` 開始，eval 出現退步才提高。不能拿這個歷史建議當作 GPT-6.1 的起點。

## 逐條官方來源

1. [GPT-6.1 Sol model page](https://developers.openai.com/api/docs/models/gpt-6.1-sol)：公開名稱、API ID、`medium (default)`、支援值與限制。
2. [Using GPT-6（latest-model）](https://developers.openai.com/api/docs/guides/latest-model)：目前列出 Astra、GPT-6.1 Sol、Luna；Sol 的 effort default 與 migration 說明。
3. [Reasoning models](https://developers.openai.com/api/docs/guides/reasoning)：模型別 defaults、effort 建議、mode 與 effort 獨立。
4. [Codex Models](https://learn.chatgpt.com/docs/models)：最新 coding／agent 模型與各模型建議起點。由 [原官方 Codex Models URL](https://developers.openai.com/codex/models) 回傳 308 redirect 後，實際讀取此目的頁。
5. [GPT-5.1 model page](https://developers.openai.com/api/docs/models/gpt-5.1)：`none (default)`。
6. [GPT-5.2 model page](https://developers.openai.com/api/docs/models/gpt-5.2)：`none` 預設，標準 `gpt-5.2`。
7. [GPT-5.2 Prompting Guide](https://developers.openai.com/cookbook/examples/gpt-5/gpt-5-2_prompting_guide)：原文 “default reasoning level for GPT-5 is medium, and for GPT-5.1 and GPT-5.2 is none.”；migration 起點，作歷史版本證據。
8. [Codex Prompting Guide](https://developers.openai.com/cookbook/examples/gpt-5/codex_prompting_guide)：GPT-5.3-Codex 世代的 interactive coding `medium`／hardest tasks `high/xhigh` 建議。
