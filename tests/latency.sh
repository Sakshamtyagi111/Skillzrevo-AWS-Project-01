#!/usr/bin/env bash
# Usage: ./tests/latency.sh https://example.com [runs]
# Run it from several regions (CloudShell / EC2 / VPS) and compare the results.
URL="${1:?url}"; N="${2:-10}"
PATHS=("/index.html" "/css/style.css" "/images/hero.svg")
echo "Location test from: $(curl -s https://ipinfo.io/city 2>/dev/null), $(curl -s https://ipinfo.io/country 2>/dev/null)"
for p in "${PATHS[@]}"; do
  echo; echo "== $URL$p  ($N runs)"
  printf '%-4s %-8s %-8s %-8s %-8s %-8s %-10s %s\n' run dns_ms tcp_ms tls_ms ttfb_ms total_ms x-cache pop
  tot=0; ttfbsum=0
  for i in $(seq 1 "$N"); do
    out=$(curl -s -o /dev/null -D /tmp/h.$$ -w '%{time_namelookup} %{time_connect} %{time_appconnect} %{time_starttransfer} %{time_total}' "$URL$p")
    read -r dns tcp tls ttfb total <<<"$out"
    xc=$(grep -i '^x-cache' /tmp/h.$$ | awk '{print $2}'); pop=$(grep -i '^x-amz-cf-pop' /tmp/h.$$ | awk '{print $2}' | tr -d '\r')
    ms() { awk -v v="$1" 'BEGIN{printf "%.0f", v*1000}'; }
    printf '%-4s %-8s %-8s %-8s %-8s %-8s %-10s %s\n' "$i" "$(ms $dns)" "$(ms $tcp)" "$(ms $tls)" "$(ms $ttfb)" "$(ms $total)" "$xc" "$pop"
    tot=$(awk -v a="$tot" -v b="$total" 'BEGIN{print a+b}'); ttfbsum=$(awk -v a="$ttfbsum" -v b="$ttfb" 'BEGIN{print a+b}')
  done
  awk -v t="$tot" -v f="$ttfbsum" -v n="$N" 'BEGIN{printf "AVG  ttfb=%.0f ms  total=%.0f ms\n", f/n*1000, t/n*1000}'
done
rm -f /tmp/h.$$
