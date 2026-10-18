#!/bin/bash
# Tells Bing, Yandex and the other IndexNow search engines that the pages of agentvalley.app changed,
# so they crawl them soon rather than some day. Run it once a deploy is live; it sends every page in
# the live sitemap. The key is public by design: the engines check it at /indexnow.txt.
#   testing/indexnow.sh
set -euo pipefail
cd "$(dirname "$0")/.."
KEY="$(tr -d '\n' < site/public/indexnow.txt)"
URLS="$(curl -fsS https://agentvalley.app/sitemap.xml | grep -o '<loc>[^<]*</loc>' | sed -e 's/<loc>//' -e 's/<\/loc>//')"
BODY="$(python3 -I -c 'import json,sys; print(json.dumps({"host": "agentvalley.app", "key": sys.argv[1], "keyLocation": "https://agentvalley.app/indexnow.txt", "urlList": sys.argv[2].split()}))' "$KEY" "$URLS")"
curl -sS -o /dev/null -w "IndexNow answered %{http_code} for $(echo "$URLS" | wc -l | tr -d ' ') pages\n" \
  -X POST https://api.indexnow.org/indexnow -H 'Content-Type: application/json; charset=utf-8' -d "$BODY"
