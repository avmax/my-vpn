#!/usr/bin/env bash
# Phase 0: characterise the current network before renting anything.
# Run on home Wi-Fi with every VPN app DISCONNECTED, then again with the Mac on the iPhone hotspot.
#   tests/recon.sh home      -> tests/out/recon-home-<date>.md
#   tests/recon.sh mobile    -> tests/out/recon-mobile-<date>.md
set -u
label="${1:-net}"
cd "$(dirname "$0")/.."
mkdir -p tests/out
out="tests/out/recon-${label}-$(date +%Y%m%d-%H%M).md"
SAMPLE_MB="${SAMPLE_MB:-30}"
CURL="curl -s --max-time 25"

say() { printf '%s\n' "$*" | tee -a "$out"; }
row() { printf '| %s |\n' "$(IFS='|'; echo "$*")" | tee -a "$out"; }

say "# Recon: $label, $(date)"
say ""
if netstat -rn -f inet 2>/dev/null | grep -qE '^0/1 .*utun|^128\.0/1 .*utun'; then
  say "**WARNING: a full-tunnel VPN (utun) is active. Results describe the VPN exit, not this network. Disconnect and rerun.**"
fi

say "## Public identity"
ipinfo=$($CURL https://ipinfo.io/json)
say '```'; say "$ipinfo"; say '```'
say ""

say "## DNS behaviour"
say "Plain UDP DNS to 8.8.8.8 and 1.1.1.1 (intercepted by RU ISPs since Aug 2026), DoH to the same, and Yandex."
say ""
say "| resolver | query | answer |"
say "|---|---|---|"
for r in 8.8.8.8 1.1.1.1 77.88.8.8; do
  for q in instagram.com rutracker.org ya.ru; do
    a=$(dig +short +time=3 +tries=1 @"$r" "$q" A 2>/dev/null | tr '\n' ' ')
    row "udp $r" "$q" "${a:-NO ANSWER}"
  done
done
# whoami-style check: which resolver actually answered a query sent to 8.8.8.8
w=$(dig +short +time=3 +tries=1 @8.8.8.8 o-o.myaddr.l.google.com TXT 2>/dev/null | tr '\n' ' ')
row "udp 8.8.8.8" "o-o.myaddr.l.google.com TXT (client subnet seen by Google)" "${w:-NO ANSWER}"
for u in "https://dns.google/resolve?name=instagram.com&type=A" "https://cloudflare-dns.com/dns-query?name=instagram.com&type=A" "https://common.dot.dns.yandex.net/dns-query?name=instagram.com&type=A"; do
  a=$($CURL -H 'accept: application/dns-json' "$u" | jq -r '.Answer[]?.data' 2>/dev/null | tr '\n' ' ')
  row "DoH $u" "instagram.com" "${a:-FAILED}"
done
say ""

say "## UDP reachability (STUN binding to foreign servers; this is the path WireGuard/AWG would use)"
say '```'
python3 - <<'PY' | tee -a "$out"
import socket, struct, os, time
for host, port in (("stun.l.google.com", 19302), ("stun.cloudflare.com", 3478), ("stun.nextcloud.com", 3478)):
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(3)
        tid = os.urandom(12)
        s.sendto(struct.pack("!HHI", 0x0001, 0, 0x2112A442) + tid, (host, port))
        t = time.time(); data, _ = s.recvfrom(1024); rtt = (time.time() - t) * 1000
        print(f"{host}:{port}  OK  {len(data)} bytes  {rtt:.0f} ms")
    except Exception as e:
        print(f"{host}:{port}  FAIL  {e}")
PY
say '```'
say ""

say "## Hoster reachability and throughput"
say "Controls are ranges known to be on TSPU AS lists; a stall at ~16 KB or a tiny Mbps figure is the expected signature."
say ""
say "| provider | location | role | ping ms | tcp443 | Mbps (${SAMPLE_MB} MB) | note |"
say "|---|---|---|---|---|---|---|"
grep -vE '^\s*(#|$)' tests/endpoints.txt | while IFS='|' read -r prov loc host url role; do
  p=$(ping -c 3 -t 3 "$host" 2>/dev/null | awk -F'/' '/avg/ {print $5}')
  t=$(nc -z -G 4 "$host" 443 >/dev/null 2>&1 && echo ok || echo no)
  if [ -n "$url" ]; then
    r=$(curl -s -o /dev/null --max-time 40 -r "0-$((SAMPLE_MB*1024*1024-1))" -w '%{speed_download} %{size_download} %{http_code}' "$url" 2>/dev/null)
    spd=$(echo "$r" | awk '{printf "%.1f", $1*8/1000000}')
    got=$(echo "$r" | awk '{printf "%.1f", $2/1048576}')
    code=$(echo "$r" | awk '{print $3}')
    note="got ${got} MB, http ${code}"
    if [ -n "$r" ] && awk -v g="$(echo "$r" | awk '{print $2}')" 'BEGIN{exit !(g>0 && g<32768)}'; then note="STALLED at <32 KB (freeze signature)"; fi
  else spd="-"; note="ping only"; fi
  row "$prov" "$loc" "$role" "${p:-timeout}" "$t" "$spd" "$note"
done
say ""
say "Saved to $out"
