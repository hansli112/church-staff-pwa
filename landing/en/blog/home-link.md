---
title: "Home page link: new content every day"
date: 2026-11-19
description: Put one link at the top of everyone’s home page. Keep it fixed, or fetch the day’s title, description, and link from a URL every day.
---

Admins can put one link at the top of everyone’s home page: the giving page, the bulletin, a daily devotional. It’s in Settings → Church info → Home page link.

## A fixed link

Fill in the title, a description (optional), and the link, then tap Save.

## New content every day

If you have something new every day, such as a daily devotional, fill in the content URL. Martha, sit fetches it once a day at the time you set and replaces the title, description, and link with that day’s.

The URL has to return JSON like this:

```json
{
  "date": "2026-11-19",
  "title": "Daily bread",
  "body": "May God’s word be your strength each day",
  "link": "https://example.org/daily/2026-11-19"
}
```

- Exactly these four fields: `date`, `title`, `body`, `link`.
- `date` is today in the church’s time zone, as `YYYY-MM-DD`. Any other day counts as no content for today yet.
- `title` can’t be blank and shows up to 30 characters; `body` may be blank and shows up to 120.
- `link` and the content URL both need `https://`.
- The site has to answer within 5 seconds, with no more than 64 KB.

If it can’t be fetched or isn’t in this format, the page says why, and you can tap Update now.

A URL like this is usually made by someone with n8n, Make, or code of their own. If nobody at church writes code, a fixed link is all you need.
