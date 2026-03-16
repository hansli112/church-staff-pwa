export async function onRequestGet() {
  const response = await fetch(
    'https://www.breadoflife.taipei/news/daily-bible/',
    {
      headers: {
        'User-Agent': 'Mozilla/5.0 (compatible; church-staff-pwa)',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      },
    }
  );
  const body = await response.text();
  return new Response(body, {
    status: response.status,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Access-Control-Allow-Origin': '*',
      'Cache-Control': 'no-store',
    },
  });
}
