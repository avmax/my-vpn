#!/usr/bin/env bash
# Phase 1 protocol shoot-out. Run from the Mac at home, then on the iPhone hotspot, with every VPN app OFF.
#   tests/matrix.sh <server-name> [home|mobile] [quick]
# Needs: clients/out/test/<server>/*.json (from clients/gen.py) and tests/bin/xray (downloaded on first run).
# Reality/XHTTP legs run through a local Xray SOCKS proxy. For the AWG and plain-WG legs the script pauses and
# asks you to connect the AmneziaWG / WireGuard app with the generated conf, then measures the tunnel directly.
set -u
srv="${1:?server name from inventory}"; net="${2:-home}"; quick="${3:-}"
cd "$(dirname "$0")/.."
XRAY_VER=$(grep -E '^xray_version' ansible/group_vars/all/main.yml | cut -d'"' -f2)
mkdir -p tests/bin tests/out
out="tests/out/matrix-${srv}-${net}-$(date +%Y%m%d-%H%M).md"
ip="${SERVER_IP:-}"
[ -z "$ip" ] && [ -x .venv/bin/python ] && ip=$(.venv/bin/python -c "import yaml; h=yaml.safe_load(open('inventory/hosts.yml'))['all']['children']; print(next(v['ansible_host'] for g in h.values() for k,v in (g.get('hosts') or {}).items() if k=='$srv'))")
[ -z "$ip" ] && { echo "SERVER_IP not set and no local venv to read inventory" >&2; exit 1; }
STAB_MIN=${STAB_MIN:-45}; [ "$quick" = quick ] && STAB_MIN=3
BIG_MB=${BIG_MB:-500};   [ "$quick" = quick ] && BIG_MB=50
DL_URL="https://speed.cloudflare.com/__down?bytes="
UL_URL="https://speed.cloudflare.com/__up"

say() { printf '%s\n' "$*" | tee -a "$out"; }

if [ ! -x tests/bin/xray ]; then
  arch=$(uname -m); [ "$arch" = arm64 ] && z="Xray-macos-arm64-v8a.zip" || z="Xray-macos-64.zip"
  echo "downloading Xray v$XRAY_VER for the Mac ($arch)"
  curl -fsSL -o tests/bin/xray.zip "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VER}/${z}" && unzip -oq tests/bin/xray.zip -d tests/bin && chmod +x tests/bin/xray
  curl -fsSL -o tests/bin/geoip.dat https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geoip.dat
  curl -fsSL -o tests/bin/geosite.dat https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geosite.dat
fi
export XRAY_LOCATION_ASSET="$PWD/tests/bin"

# measure <label> <curl-proxy-args...>
measure() {
  local label="$1"; shift
  local P=("$@")
  say "### $label"
  local seen; seen=$(curl -s --max-time 20 "${P[@]}" https://ifconfig.co/json | jq -r '.ip + " " + (.asn_org // .asn // "")' 2>/dev/null)
  if [ -z "$seen" ]; then say "- handshake: **FAIL** (no response through the tunnel)"; say ""; return 1; fi
  say "- handshake: OK, exit seen as \`$seen\`"
  local ttfb; ttfb=$(curl -s -o /dev/null --max-time 20 "${P[@]}" -w '%{time_starttransfer}' "${DL_URL}1000")
  say "- time to first byte (1 KB): ${ttfb}s"
  local r; r=$(curl -s -o /dev/null --max-time 60 "${P[@]}" -w '%{speed_download} %{size_download}' "${DL_URL}100000000")
  say "- download 100 MB: $(echo "$r" | awk '{printf "%.1f Mbps, got %.0f MB", $1*8/1e6, $2/1048576}')"
  head -c 20000000 /dev/zero > /tmp/ul20.bin
  r=$(curl -s -o /dev/null --max-time 60 "${P[@]}" -w '%{speed_upload}' -X POST --data-binary @/tmp/ul20.bin "$UL_URL")
  say "- upload 20 MB: $(echo "$r" | awk '{printf "%.1f Mbps", $1*8/1e6}')"
  r=$(curl -s -o /dev/null --max-time 900 "${P[@]}" -w '%{speed_download} %{size_download} %{time_total}' "${DL_URL}$((BIG_MB*1000000))")
  say "- sustained ${BIG_MB} MB: $(echo "$r" | awk -v m="$BIG_MB" '{printf "%.1f Mbps, got %.0f MB of %d in %.0fs%s", $1*8/1e6, $2/1e6, m, $3, ($2<m*1e6*0.98)?"  **CUT SHORT**":""}')"
  local n=0 fail=0 slow=0 end=$((SECONDS + STAB_MIN*60))
  while [ $SECONDS -lt $end ]; do
    local t; t=$(curl -s -o /dev/null --max-time 8 "${P[@]}" -w '%{time_total} %{http_code}' "${DL_URL}20000")
    n=$((n+1)); case "$t" in *" 200") awk -v x="${t% *}" 'BEGIN{exit !(x>3)}' && slow=$((slow+1));; *) fail=$((fail+1));; esac
    sleep 10
  done
  say "- stability ${STAB_MIN} min: $n probes, $fail failed, $slow slower than 3 s"
  say ""
}

freeze_probe() {
  # June-2026 TSPU behaviour: >3 parallel TLS sessions to one SNI from a Chrome fingerprint may freeze the flow for 120 s.
  say "### Freeze probe (6 parallel Chrome-fingerprint handshakes, then watch the Firefox tunnel for 3 min)"
  tests/bin/xray run -config "clients/out/test/$srv/reality-chrome.json" >/dev/null 2>&1 & local cpid=$!
  sleep 2
  for i in 1 2 3 4 5 6; do curl -s -o /dev/null --max-time 20 --proxy socks5h://127.0.0.1:1082 "${DL_URL}1000" & done; wait
  kill $cpid 2>/dev/null
  local worst=0 end=$((SECONDS + 180))
  while [ $SECONDS -lt $end ]; do
    local t; t=$(curl -s -o /dev/null --max-time 30 --proxy socks5h://127.0.0.1:1080 -w '%{time_total}' "${DL_URL}1000")
    awk -v a="$t" -v b="$worst" 'BEGIN{exit !(a>b)}' && worst=$t
    sleep 10
  done
  say "- worst request time after the burst: ${worst}s $(awk -v w="$worst" 'BEGIN{print (w>20)?"**FROZEN**":"(no freeze)"}')"
  say ""
}

say "# Matrix: $srv ($ip) from $net, $(date)"
say ""
say "## Reality + Vision (firefox fp), via local SOCKS 1080"
tests/bin/xray run -config "clients/out/test/$srv/reality.json" >/dev/null 2>&1 & XP=$!
sleep 2; measure "reality" --proxy socks5h://127.0.0.1:1080 && freeze_probe; kill $XP 2>/dev/null
say "## XHTTP over TLS (firefox fp), via local SOCKS 1081"
tests/bin/xray run -config "clients/out/test/$srv/xhttp.json" >/dev/null 2>&1 & XP=$!
sleep 2; measure "xhttp" --proxy socks5h://127.0.0.1:1081; kill $XP 2>/dev/null
if [ -t 0 ]; then
  say "## AmneziaWG 2.0"
  echo ">>> Connect the AmneziaWG app with clients/out/mac/awg-${srv}.conf, then press Enter (or 's' to skip)"; read -r a
  [ "$a" != s ] && measure "amneziawg"
  echo ">>> Disconnect AmneziaWG. Now connect the WireGuard app with clients/out/mac/wg-control-${srv}.conf (plain WG control), then press Enter (or 's')"; read -r a
  [ "$a" != s ] && measure "plain-wireguard-control"
  echo ">>> Disconnect WireGuard."
else
  say "## AmneziaWG / plain WireGuard: skipped (no terminal to prompt for Connect in the apps)"
fi
say "Saved to $out"
