export async function onRequestGet() {
  // Cloudflare Workers may have SSL verification issues with some external HTTPS
  // hosts. Try HTTP first (server will redirect if needed), then HTTPS.
  const urls = [
    'http://www.breadoflife.taipei/news/daily-bible/',
    'https://www.breadoflife.taipei/news/daily-bible/',
  ];

  let lastErr = '';
  for (const url of urls) {
    try {
      const res = await fetch(url, {
        redirect: 'follow',
        headers: {
          'User-Agent': 'Mozilla/5.0 (compatible; church-staff-pwa)',
          Accept: 'text/html,application/xhtml+xml',
        },
      });
      const body = await res.text();
      return new Response(body, {
        status: 200,
        headers: {
          'Content-Type': 'text/html; charset=utf-8',
          'Access-Control-Allow-Origin': '*',
          'Cache-Control': 'no-store',
        },
      });
    } catch (err) {
      lastErr = `${url} → ${err}`;
    }
  }

  return new Response(`upstream fetch failed: ${lastErr}`, {
    status: 502,
    headers: {
      'Content-Type': 'text/plain',
      'Access-Control-Allow-Origin': '*',
    },
  });
}
