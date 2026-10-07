#!/usr/bin/env bash
# Puts the landing page and legal pages into the web build before a Hosting
# deploy. The landing page is the site's front page (index.html), so the
# Flutter app shell moves to app.html, where every other path is rewritten.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
web="$root/app/build/web"

# Only a fresh Flutter build has its shell in index.html; a second run must
# not move the landing page over it.
if grep -q flutter_bootstrap "$web/index.html"; then
  mv "$web/index.html" "$web/app.html"
fi
cp "$root/landing/index.html" "$web/index.html"
cp "$root/landing/privacy.html" "$root/landing/terms.html" "$root/landing/site.css" "$web/"

# Search engines see only the production site, and not the church pages
# (a church's name is not meant to show up in search results).
# TODO(M7): the origin becomes the bought domain.
if [ "${GCLOUD_PROJECT:-}" = marthasit ]; then
  origin="https://marthasit.web.app"
  printf 'User-agent: *\nDisallow: /c/\n\nSitemap: %s/sitemap.xml\n' "$origin" > "$web/robots.txt"
  cat > "$web/sitemap.xml" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>$origin/</loc></url>
</urlset>
XML
else
  printf 'User-agent: *\nDisallow: /\n' > "$web/robots.txt"
  rm -f "$web/sitemap.xml"
fi
