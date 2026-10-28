#!/usr/bin/env bash
# List versions:   BUCKET=b ./scripts/rollback.sh list index.html
# Restore version: BUCKET=b DIST_ID=E123 ./scripts/rollback.sh restore index.html <VersionId>
set -euo pipefail
: "${BUCKET:?Set BUCKET}"
cmd="${1:-}"; key="${2:-}"
case "$cmd" in
  list)
    aws s3api list-object-versions --bucket "$BUCKET" --prefix "$key" \
      --query 'Versions[].{VersionId:VersionId,Latest:IsLatest,Modified:LastModified,Size:Size}' --output table ;;
  restore)
    vid="${3:?VersionId required}"; : "${DIST_ID:?Set DIST_ID}"
    # copying an old version onto the same key makes it the NEW current version (history is kept)
    aws s3api copy-object --bucket "$BUCKET" --key "$key" \
      --copy-source "$BUCKET/$key?versionId=$vid" --metadata-directive COPY >/dev/null
    path="/$key"; [ "$key" = "index.html" ] && aws cloudfront create-invalidation --distribution-id "$DIST_ID" --paths "/" "$path" >/dev/null \
      || aws cloudfront create-invalidation --distribution-id "$DIST_ID" --paths "$path" >/dev/null
    echo "Restored $key to $vid and invalidated." ;;
  *) echo "usage: $0 list <key> | restore <key> <versionId>"; exit 1 ;;
esac
