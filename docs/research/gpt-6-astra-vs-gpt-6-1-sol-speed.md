# GPT-6 Astra 與 GPT-6.1 Sol 速度

查核日期：2026-10-09。沿用 `docs/research/` 的英文連字號檔名、繁體中文與編號來源慣例；另建速度筆記，不覆蓋既有模型選型筆記。僅查公開資料，未執行付費 benchmark、未讀取 API key、未更動程式或設定、未發布外部文件。

## 精簡結論

**找到可比較的公開 API 速度量測：Artificial Analysis 本次直接讀取的 Max 對照，Sol 約 55 tokens/s、Astra 約 45 tokens/s；Sol 串流輸出約快兩成。** 首個答案 token 的等待時間在同一對照為 Sol 326.94 秒、Astra 410.56 秒，包含推理等待。這是特定 effort 的動態量測，不能概括為每次聊天或整個 agent 任務都快兩成。[4][5][6]

**首答不一定 Sol 較快。** 同站 release 對照的 medium 為 Astra 5.13 秒、Sol 5.76 秒；low 為 Astra 2.59 秒、Sol 2.80 秒。不同 effort 應分開比較。[5][6]

兩者有 OpenAI 正式 model page 與 API ID：`gpt-6-astra`、`gpt-6.1-sol`，不是只有環境標籤。[1][2] 不過，使用者提供的 Claude Code `/model` 與環境名稱只識別顯示名稱；本次未核實該環境的實際供應商路由、service tier、reasoning effort 或額外 agent 開銷，不能把公開 API 數據直接當成該環境的耗時保證。

## 同站、同 effort 的數據

下表逐列取自 Artificial Analysis release comparison 本次直接讀取內容；不是搜尋結果摘要。[5] Output Speed 在該表取整；延遲單位依同站 comparison 與方法頁為秒。[4][6]

| Effort | Astra 輸出速度（tokens/s） | Sol 輸出速度（tokens/s） | Astra 首個答案 token（秒） | Sol 首個答案 token（秒） |
| --- | ---: | ---: | ---: | ---: |
| max | 45 | 55 | 410.56 | 326.94 |
| xhigh | 43 | 53 | 203.08 | 140.76 |
| high | 42 | 49 | 83.11 | 58.26 |
| medium | 41 | 49 | 5.13 | 5.76 |
| low | 42 | 47 | 2.59 | 2.80 |

這些列的 `Time to First Token` 與 `Time to First Answer Token` 本次數值相同。[4][5] 方法頁一般定義中，兩者仍不同：若模型暴露推理串流，首 token 可是推理 token；首個答案 token 則要等推理完成。[6] 因此，解讀上表宜稱「首答等待」，不要把它當成開始內部推理前的純網路延遲。

Max 專用 comparison 同樣列出 55／45 tokens/s；其 FAQ 顯示較精細的 Sol 54.9、Astra 44.5 tokens/s。[4] 「約快兩成」是粗略換算，並非 OpenAI 的速度承諾；不使用取整資料產生看似精確的倍數。

## 三種速度不能混用

### 輸出 tokens/s

這是串流開始後的 token 生成速率，不包含開始回答前的等待。[4][6] Artificial Analysis 對未完整暴露推理 tokens 的模型，以答案最後 80% 的 chunks 計算 output speed；性能量測以 `tiktoken/o200k_base` 統一計數，不等於所有模型自身 tokenizer 或帳單計數。[6]

### 首 token／推理等待

首個答案 token 指送出請求到第一個答案 token 的時間，包含推理等待。[4][6] Max 對照約 327／411 秒，不能說每次請求都要等這麼久：同站 medium、low 數值已明顯不同，且量測依工作負載和統計方式而變。[5][6]

### Agent 任務全程耗時

本次未核實到可直接套用 Claude Code、同條件的兩模型完整 agent 任務 wall-clock 對照。

不能把 Artificial Analysis 的兩個相關欄位當作它：[4]

- **End-to-End Response Time**：comparison 頁說明為用首 token／推理等待及生成速率計算的 **500-token 回覆**時間。Max 列為 Sol 336.04 秒、Astra 421.78 秒，是單次回覆的計算指標，不是完整 agent 工作。
- **Time per Task**：頁面定義為 Intelligence Index 每題 output tokens 除以 output speed 的 weighted decode-time 指標；subtitle 明寫 **excludes TTFT and overhead time**。同頁還有 subtitle 用 minutes、定義用 seconds 的單位不一致，因此不拿這個欄位推論真實 agent 任務總耗時或勝負。

## 量測條件與不確定性

- **原始量測站，而非轉述文章**：上述速度與延遲直接取自 Artificial Analysis 自有 comparison 頁；這是獨立量測，不是 OpenAI 官方延遲保證。[4][5]
- **動態資料**：比較頁未給每列量測時間或服務 tier。方法頁說一般結果採過去 72 小時 P50，100k workload 採過去 14 天 P50；網站預設為約 10k input tokens、至少 1,500 answer tokens。這些是全站方法，不代表本次取得每列的完整原始樣本或 run count。[6]
- **供應商資訊有限**：比較頁說有第一方 API 時使用第一方，否則使用跨供應商中位數；release 頁也列出各模型的供應商，但不應把供應商清單誤當成每列實際測量 endpoint 或 service tier 的證明。[4][5]
- **地點與 prompt 影響**：方法頁列測試主機為 Google Cloud `us-central1-a`，首 token 時間包括網路延遲；output speed 也會受輸出型態與 speculative decoding 等因素影響。[6]
- **搜尋索引與直接頁面不同**：搜尋摘要曾出現其他速度值；本筆記只採直接讀到的指定頁面數據，不混合搜尋快照、不同 effort 或不同頁面的數值。未找到原始測量 timestamp 或信賴區間，不能宣稱細小差異統計顯著。[4][5][6]
- **Service tier 不能混用**：OpenAI Ultrafast 文件目前列兩者 broadly available，稱其為 API 最快 service tier，但本文未讀到兩者同 tier 的具體 tokens/s 或首答秒數。文件亦提醒非 persistent connection 的網路開銷可削弱速度收益。AA 比較未明列 tier，不能視為 Ultrafast benchmark。[3][4][5]
- 不把「up to 8x」「300 tokens/s」等搜尋結果轉述直接用來對比兩模型：本次沒有在已直接讀取的官方文件核實這些數字的完整條件，也不能用同模型跨 tier 增益取代 Astra／Sol 同條件比較。

## 查核範圍與取得限制

本次進行四組有限搜尋：兩模型精確名稱與 speed、OpenAI 官方限定、官方／AA 限定的 speed／tokens／latency、AA 方法頁。優先直接讀取官方 model pages、Ultrafast 文件、AA 原始 comparison 與方法頁；不再延伸搜尋或跑付費測試。

OpenAI 的 Sol 發布公告直接讀取回 HTTP 403，因此未用其搜尋摘要聲稱模型間的速度倍數。[7] The New Stack 的結果摘要曾列實際任務耗時，但本次抓取未取得完整文章主體與測試條件，故不採納其具體秒數。[8] 「本次未核實」不表示所有公開資料均不存在。

## 來源

1. [OpenAI — GPT-6 Astra model page](https://developers.openai.com/api/docs/models/gpt-6-astra)：直接讀取；正式名稱、API ID。未提供具體 tokens/s／首答延遲。
2. [OpenAI — GPT-6.1 Sol model page](https://developers.openai.com/api/docs/models/gpt-6.1-sol)：直接讀取；正式名稱、API ID、Ultrafast 用法。未提供具體 tokens/s／首答延遲。
3. [OpenAI — Ultrafast mode](https://developers.openai.com/api/docs/guides/ultrafast-mode)：直接讀取；兩模型可用性、tier 與 persistent-connection 限制。沒有同條件模型間速度數值。
4. [Artificial Analysis — GPT-6.1 Sol (Max) vs GPT-6 Astra (Max)](https://artificialanalysis.ai/models/comparisons/gpt-6-1-sol-vs-gpt-6-astra)：直接讀取；Max 輸出速度、首答等待、500-token 回覆指標與 Time per Task 定義。
5. [Artificial Analysis — Release comparison](https://artificialanalysis.ai/models/releases/comparisons/gpt-6-1-sol-vs-gpt-6-astra)：直接讀取；max／xhigh／high／medium／low 的同 effort 對照。
6. [Artificial Analysis — Language Model API Performance Benchmarking](https://artificialanalysis.ai/methodology/performance-benchmarking)：直接讀取；速度／延遲定義、workload、P50、統計窗口、tokenizer、測試地點與限制。
7. [OpenAI — Introducing GPT-6.1 Sol](https://openai.com/index/introducing-gpt-6-1-sol/)：直接讀取回 403；不作本筆記具體速度數字的證據。
8. [The New Stack — GPT-6.1 Sol vs. GPT-6 Astra](https://thenewstack.io/gpt-6-1-sol-vs-gpt-6-astra/)：抓取未取得完整正文；不採納搜尋摘要的實際任務耗時。
