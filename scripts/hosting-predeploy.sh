#!/usr/bin/env bash
# Puts the website (landing page, support page, blog, legal pages) into the
# web build before a Hosting deploy. The landing page is the site's front
# page (index.html), so the Flutter app shell moves to app.html, where every
# other path is rewritten.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
web="$root/app/build/web"

# Only a fresh Flutter build has its shell in index.html; a second run must
# not move the landing page over it.
if grep -q flutter_bootstrap "$web/index.html"; then
  mv "$web/index.html" "$web/app.html"
fi

# Fonts named after their contents, so a new build's icons are never drawn
# with an old cached font (scripts/fingerprint-fonts.mjs).
node "$root/scripts/fingerprint-fonts.mjs" "$web"

# The website, built from landing/ (scripts/build-site.mjs).
# TODO(M7): the production origin becomes the bought domain.
if [ "${GCLOUD_PROJECT:-}" = marthasit ]; then
  origin="https://marthasit.web.app"
else
  origin="https://${GCLOUD_PROJECT:-marthasit-dev}.web.app"
fi
[ -d "$root/landing/node_modules" ] || npm ci --prefix "$root/landing" --silent
# 線上支持 (NewebPay) on the support page: off unless the deploy asks for it,
# e.g. SUPPORT_PAYMENTS=on scripts/deploy.sh dev --only hosting. Turn it on
# only where newebpayStart is set up (docs/firebase-setup.md).
pages="$(node "$root/scripts/build-site.mjs" "$web" --origin "$origin" --project "${GCLOUD_PROJECT:-}" \
  --payments "${SUPPORT_PAYMENTS:-off}")"

# Search engines see only the production site, and not the church pages
# (a church's name is not meant to show up in search results).
if [ "${GCLOUD_PROJECT:-}" = marthasit ]; then
  printf 'User-agent: *\nDisallow: /c/\n\nSitemap: %s/sitemap.xml\n' "$origin" > "$web/robots.txt"
  cat > "$web/sitemap.xml" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
$(printf '%s\n' "$pages" | sed "s|.*|  <url><loc>$origin&</loc></url>|")
</urlset>
XML
else
  printf 'User-agent: *\nDisallow: /\n' > "$web/robots.txt"
  rm -f "$web/sitemap.xml"
fi
