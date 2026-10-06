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
