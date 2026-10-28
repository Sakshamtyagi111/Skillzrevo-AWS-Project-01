#!/usr/bin/env bash
# Proves that a change to index.html / css shows up immediately.
# Usage: DOMAIN=example.com BUCKET=b DIST_ID=E123 ./tests/invalidation-test.sh
set -euo pipefail
: "${DOMAIN:?}"; : "${BUCKET:?}"; : "${DIST_ID:?}"
TAG="TEST-$(date +%s)"
echo ">> Before: $(curl -s https://$DOMAIN/ | grep -o 'name="build" content="[^"]*"')"
curl -s https://$DOMAIN/ | sed "s#</title>#</title><!-- $TAG -->#" > /tmp/index-test.html
aws s3 cp /tmp/index-test.html "s3://$BUCKET/index.html" --cache-control "no-cache, no-store, must-revalidate, max-age=0" --content-type "text/html; charset=utf-8" >/dev/null
aws cloudfront create-invalidation --distribution-id "$DIST_ID" --paths "/" "/index.html" >/dev/null
for i in $(seq 1 12); do
  if curl -s "https://$DOMAIN/" | grep -q "$TAG"; then echo "✅ Change visible after ~$((i*5))s"; exit 0; fi
  sleep 5
done
echo "❌ Change not visible after 60s"; exit 1
