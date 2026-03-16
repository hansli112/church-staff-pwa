export async function onRequest() {
  const upstream = await fetch(
    'https://www.breadoflife.taipei/news/daily-bible/',
    {
      headers: {
        'User-Agent': 'Mozilla/5.0 (compatible; church-staff-pwa)',
        Accept: 'text/html',
      },
    }
  );

  const body = await upstream.text();

  return new Response(body, {
    status: upstream.status,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Access-Control-Allow-Origin': '*',
      'Cache-Control': 'no-store',
    },
  });
}
