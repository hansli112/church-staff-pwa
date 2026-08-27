// 事件新增成功後通知 n8n，由 n8n 發 LINE 群組訊息。
//
// 為什麼不在這裡直接打 LINE Messaging API：channel access token 和訊息排版
// 都已經在 n8n 裡（那邊還有一條「LINE 群組訊息 → 建事件 → 回覆」的流程）。
// 從這裡再接一次 LINE，等於把同一段排版邏輯養在兩個系統，改一邊忘了另一邊
// 是遲早的事。這裡只負責把「發生了什麼」講清楚，長什麼樣交給 n8n。
//
// 只有新增會通知。編輯和刪除沒接，是因為目前群組只想知道有新聚集；真要加的話
// 編輯可以照抄下面的用法（PATCH 的回應就是完整事件），刪除則要在刪掉之前先
// GET 一次才拿得到標題 —— Google 的 DELETE 回 204 空 body。

/// 通知是附帶效果，不該讓使用者為它多等。比對外的 Google 呼叫更短。
const NOTIFY_TIMEOUT_MS = 5000;

/// 把 Google 的 event resource 攤平成 n8n 好處理的形狀。
///
/// n8n 那端不必知道 Google 用 `date` 表示全天、用 `dateTime` 表示定時，也不必
/// 知道 `end.date` 是排他的。那些差異在這裡一次弭平。
export function notifyPayload(action, event, actorUid) {
  const allDay = Boolean(event?.start?.date);
  return {
    action,
    source: 'pwa',
    id: event?.id ?? null,
    title: event?.summary ?? null,
    allDay,
    start: event?.start?.dateTime ?? event?.start?.date ?? null,
    end: allDay
      ? inclusiveEndDate(event?.end?.date)
      : (event?.end?.dateTime ?? null),
    location: event?.location ?? '',
    description: event?.description ?? '',
    link: event?.htmlLink ?? null,
    actorUid,
  };
}

/// Google 的 `end.date` 是排他的：8/20 的單日活動存進去是 end.date=8/21。
/// buildGoogleEvent() 進去時加了一天，出來給人看要減回來，否則群組收到的訊息
/// 會晚一天。
function inclusiveEndDate(date) {
  if (typeof date !== 'string') return null;
  const stamp = Date.parse(`${date}T00:00:00Z`);
  if (Number.isNaN(stamp)) return null;
  return new Date(stamp - 86400000).toISOString().slice(0, 10);
}

/// 送出通知。失敗只會留在 log 裡，不會往外拋。
///
/// 呼叫到這裡時事件已經寫進 Google 了。LINE 發不出去是件該修的事，但不是使用者
/// 的操作失敗 —— 讓它變成 500 只會讓人以為活動沒建成，然後再按一次。
///
/// 兩個環境變數任一沒設就整個關掉：本機 `wrangler pages dev` 和 Preview 部署
/// 因此不會把測試資料推進真的群組。
export async function notifyN8n(env, payload, fetchImpl = fetch) {
  const url = env?.NOTIFY_WEBHOOK_URL;
  const secret = env?.NOTIFY_WEBHOOK_SECRET;
  if (!url || !secret) return;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), NOTIFY_TIMEOUT_MS);
  try {
    const response = await fetchImpl(url, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        // n8n Webhook node 的 Header Auth 憑證，名稱要跟這裡一致。
        'x-notify-secret': secret,
      },
      body: JSON.stringify(payload),
      signal: controller.signal,
    });
    if (!response.ok) {
      console.error('n8n notify rejected', response.status);
    }
  } catch (error) {
    console.error('n8n notify failed', error);
  } finally {
    clearTimeout(timer);
  }
}

/// 把通知丟進背景，讓回應先回給使用者。
///
/// `waitUntil` 由 Pages 執行期提供，但單元測試是直接呼叫 handler 的，那裡沒有。
/// 沒有就退回「就地等完」—— 慢一點，但不會因為缺一個 context 欄位就整支炸掉。
export function scheduleNotify(waitUntil, promise) {
  if (typeof waitUntil === 'function') {
    waitUntil(promise);
    return;
  }
  return promise;
}
