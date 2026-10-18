# GPT-6 Astra 與 GPT-6.1 Sol

查核日期：2026-10-09。依 `docs/research/` 現有英文連字號檔名、繁體中文內容與編號來源慣例記錄。僅使用公開第一方資料；未檢查私人連接器或本機模型設定，未更動程式與設定，未發布線上文件。

## 精簡結論

**追求最高能力、棘手推理與除錯：優先 Astra；日常 coding／agent 的成本效益：優先 6.1 Sol。** 這是根據官方定位與有限實測指標的選型建議，不表示 Astra 在所有任務都勝出，也不能因為 6.1 版本號較大就認定 Sol 較強。[1][2][3]

兩者均為 **OpenAI 正式公開模型名稱與 API ID**，不是只有未證實的社群別名：`gpt-6-astra`、`gpt-6.1-sol` 都有官方 model page。[1][2] GPT-6.1 Sol 的 system card 發布於 2026-09-29。[4]

## 可核對的比較

| 面向 | GPT-6 Astra | GPT-6.1 Sol | 證據與限制 |
| --- | --- | --- | --- |
| 整體能力定位 | 最具能力、最高 intelligence，針對最艱難 reasoning／coding | near-Astra performance，平衡 intelligence／cost／speed | 官方定性描述，不是全面勝率。[1][2][3] |
| 困難研究除錯 | 78.05% | 75.52% | Internal Research Debugging Evaluation 的 mean rubric score；Astra 高 2.53 個百分點。偏 AI research／self-improvement 的內部評估，不能當一般專案 coding 成功率。[4] |
| 軟體工程 DeepSWE v1.1 | 官方公告稱 Sol 可匹敵 Astra | 官方公告稱約 Astra 五分之一成本達到相當表現 | 僅核對到官方公告搜尋索引文字；公告全文 WebFetch 回 403，未能取得完整分數、effort 對照、樣本數與誤差，因此不列未核實的數字。[5] |
| Standard API 輸入 | US$10／百萬 tokens | US$2／百萬 tokens | 未超過 272K input tokens 的基本費率。[1][2] |
| Standard API 輸出 | US$50／百萬 tokens | US$10／百萬 tokens | Sol 的基本輸入／輸出單價為 Astra 的 20%，即便宜 80%；不等於任務總成本必然便宜 80%。[1][2] |
| Cached input | US$1／百萬 tokens | US$0.10／百萬 tokens | 快取輸入另有不同價格比，不能把所有項目概括成五分之一。[1][2] |
| 速度／延遲 | 本次未找到可直接比較的公開測量值 | 官方定位強調 speed／affordability，但無可比秒數 | 不宣稱 Sol 快幾倍；應按同一任務、effort、service tier、工具與重試條件實測。[3][4][6] |

價格限制：兩者 input 超過 272K tokens 時，全請求適用 input／cache 2 倍、output 1.5 倍費率；Fast／Ultrafast、Batch／Flex、區域處理與工具呼叫也可能改變帳單。因此上表只比較標準基本 token 價格，不推算每次任務的固定成本。[1][2]

## 沒有證實的部分

- **沒有找到可據以宣稱全方位推理勝負的、兩者同條件公開 GPQA／一般 reasoning 數值。** Astra 的旗艦定位不能替代每個 benchmark 的直接比較。[3][4]
- **沒有核實到同條件 token/s、首 token 延遲、任務完成秒數或速度倍數。** 官方「balanced speed」是定位，不是延遲保證。[3][4]
- 研究除錯指標所在段落沒有給出此評估的 reasoning effort、樣本數或信賴區間；2.53 個百分點差距不能據此宣稱統計顯著或普遍優勢。[4]
- DeepSWE 的相當表現由 OpenAI 公告搜尋索引提供；兩次直接讀取公告（原網址與搜尋提供的參數網址）均被 403 阻擋。本筆記明確區分這項較受限證據與已直接讀到的 model pages／system card。[5]
- 本次數據均是供應商第一方資料，不是自行執行或獨立重現的 benchmark。搜尋未找到某資料，不代表資料或模型不存在。

## 實務建議

先以 **6.1 Sol 處理日常 coding／agent 工作**；若難題反覆修不好、跨模組診斷或高風險推理需要最高品質，再用 **Astra**。這是依官方模型定位與基本單價的建議，不是特定使用者專案的實測結論。[1][2][3] 官方選型指南也建議以同樣輸入比較，保留符合品質門檻的最輕設定；不同 reasoning effort 與服務層級會影響比較公平性。[6]

## 逐條官方來源

1. [GPT-6 Astra model page](https://developers.openai.com/api/docs/models/gpt-6-astra)：已直接讀取，官方名稱、API ID、能力定位、定價與長 context 費率。
2. [GPT-6.1 Sol model page](https://developers.openai.com/api/docs/models/gpt-6.1-sol)：已直接讀取，官方名稱、API ID、near-Astra 定位、定價與費率限制。
3. [Using GPT-6／latest-model guide](https://developers.openai.com/api/docs/guides/latest-model)：已直接讀取，Astra highest intelligence、Sol balanced speed／cost／intelligence 的官方定位。
4. [GPT-6.1 Sol System Card](https://deploymentsafety.openai.com/gpt-6-1-sol)：已直接讀取，發布日期、§9.1.3.1 Internal Research Debugging Evaluation 與 75.52%／78.05%；無一般推理全面對照或延遲量測。
5. [Introducing GPT-6.1 Sol](https://openai.com/index/introducing-gpt-6-1-sol/)：官方搜尋索引可讀，DeepSWE v1.1 近 Astra／約五分之一成本敘述；全文直接讀取回 403，未核實完整圖表與測試條件。
6. [Model selection](https://developers.openai.com/api/docs/guides/model-selection)：已直接讀取，對成本與延遲不敏感時選 Astra，並以同任務比較 Sol／Astra；選最輕且達到品質門檻的設定。
