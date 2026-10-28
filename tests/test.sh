#!/usr/bin/env bash
# Usage: DOMAIN=example.com BUCKET=my-bucket REGION=ap-south-1 ./tests/test.sh
DOMAIN="${DOMAIN:?Set DOMAIN}"; BUCKET="${BUCKET:-}"; REGION="${REGION:-ap-south-1}"
URL="https://$DOMAIN"
pass=0; fail=0
ok()  { echo "  ✅ $1"; pass=$((pass+1)); }
bad() { echo "  ❌ $1"; fail=$((fail+1)); }
hdr() { curl -sI "$@" | tr -d '\r'; }
section() { echo; echo "== $1"; }

section "1. DNS (Route 53)"
dig +short A "$DOMAIN" | head -2 | grep -q . && ok "A record resolves" || bad "A record missing"
dig +short AAAA "$DOMAIN" | grep -q . && ok "AAAA record resolves" || bad "AAAA missing"
dig +short CNAME "www.$DOMAIN" >/dev/null; dig +short A "www.$DOMAIN" | grep -q . && ok "www resolves" || bad "www missing"
dig +short TXT "$DOMAIN" | grep -q . && ok "TXT: $(dig +short TXT "$DOMAIN" | tr '\n' ' ')" || bad "TXT missing"
dig +short CAA "$DOMAIN" | grep -q . && ok "CAA present" || bad "CAA missing"
dig +short NS  "$DOMAIN" | grep -q awsdns && ok "NS delegated to Route 53" || bad "NS not Route 53"

section "2. HTTP -> HTTPS redirect"
code=$(curl -s -o /dev/null -w '%{http_code}' "http://$DOMAIN/")
[[ "$code" == "301" || "$code" == "302" ]] && ok "http redirects ($code)" || bad "no redirect (got $code)"

section "3. TLS / ACM"
cert=$(echo | openssl s_client -servername "$DOMAIN" -connect "$DOMAIN:443" 2>/dev/null | openssl x509 -noout -issuer -enddate -subject 2>/dev/null)
echo "$cert" | sed 's/^/    /'
echo "$cert" | grep -qi amazon && ok "Certificate issued by Amazon (ACM)" || bad "Not an ACM cert"
echo | openssl s_client -tls1_1 -servername "$DOMAIN" -connect "$DOMAIN:443" 2>&1 | grep -q "Cipher is (NONE)\|handshake failure\|alert" && ok "TLS 1.1 rejected" || bad "TLS 1.1 accepted?"

section "4. Protocols"
curl -sI --http2 "$URL/" -o /dev/null -w '%{http_version}\n' | grep -q '^2' && ok "HTTP/2 works" || bad "HTTP/2 failed"
curl -sI --http3 "$URL/" -o /dev/null -w '%{http_version}\n' 2>/dev/null | grep -q '^3' && ok "HTTP/3 works" || echo "  ⚠ HTTP/3 not testable (curl build without http3)"

section "5. index.html is NOT cached"
for i in 1 2 3; do h=$(hdr "$URL/index.html"); echo "    try $i: $(echo "$h" | grep -i '^x-cache')"; done
echo "$h" | grep -qi 'x-cache:.*hit' && bad "index.html served from cache!" || ok "index.html never a Hit"
echo "$h" | grep -qi 'cache-control:.*no-cache' && ok "Cache-Control no-cache present" || bad "no-cache header missing"

section "6. Static assets ARE cached"
for path in /css/style.css /js/app.js /images/hero.svg /videos/demo.mp4; do
  curl -s -o /dev/null "$URL$path"                       # warm
  h=$(hdr "$URL$path")
  echo "$h" | grep -qi 'x-cache:.*hit' && ok "$path -> Hit ($(echo "$h" | grep -i '^age' | tr -d '\n'))" || bad "$path not a Hit: $(echo "$h" | grep -i '^x-cache')"
  echo "$h" | grep -i '^cache-control' | sed 's/^/      /'
done

section "7. Compression"
enc=$(curl -sI -H 'Accept-Encoding: br,gzip' "$URL/css/style.css" | tr -d '\r' | grep -i '^content-encoding')
[ -n "$enc" ] && ok "$enc" || bad "css not compressed"

section "8. Video Range requests (seeking)"
rc=$(curl -s -o /dev/null -w '%{http_code}' -H 'Range: bytes=0-1023' "$URL/videos/demo.mp4")
[ "$rc" = "206" ] && ok "206 Partial Content" || bad "Range gave $rc"

section "9. Security headers"
h=$(hdr "$URL/")
for n in strict-transport-security x-content-type-options x-frame-options referrer-policy; do
  echo "$h" | grep -qi "^$n" && ok "$n" || bad "$n missing"
done

section "10. S3 origin is PRIVATE"
if [ -n "$BUCKET" ]; then
  c=$(curl -s -o /dev/null -w '%{http_code}' "https://$BUCKET.s3.$REGION.amazonaws.com/index.html")
  [ "$c" = "403" ] && ok "Direct S3 URL -> 403 (blocked)" || bad "Direct S3 URL returned $c"
  aws s3api get-public-access-block --bucket "$BUCKET" --query 'PublicAccessBlockConfiguration' 2>/dev/null
  aws s3api get-bucket-versioning --bucket "$BUCKET" 2>/dev/null | grep -q Enabled && ok "Versioning enabled" || bad "Versioning not enabled"
else echo "  (skipped - set BUCKET)"; fi

section "11. Custom 404"
c=$(curl -s -o /dev/null -w '%{http_code}' "$URL/does-not-exist-$RANDOM.html")
[ "$c" = "404" ] && ok "404 page served" || bad "missing file gave $c"

echo; echo "Result: $pass passed, $fail failed"
