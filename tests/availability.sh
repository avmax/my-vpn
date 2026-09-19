#!/usr/bin/env bash
# Service availability as seen FROM a candidate VPS (run from this Mac; needs SSH access to the host from inventory).
#   tests/availability.sh <inventory-host-name>
# Checks: geolocation across databases, Cloudflare's view for chatgpt.com/claude.ai, claude.ai region redirect, Netflix licensed title,
# YouTube Premium region, Google captcha flag, geofeed, then the UnlockTests suite (AI + streaming) if it installs.
set -u
srv="${1:?inventory host name}"
cd "$(dirname "$0")/.."
ip=$(.venv/bin/python -c "import yaml; h=yaml.safe_load(open('inventory/hosts.yml'))['all']['children']; print(next(v['ansible_host'] for g in h.values() for k,v in (g.get('hosts') or {}).items() if k=='$srv'))")
mkdir -p tests/out; out="tests/out/availability-${srv}-$(date +%Y%m%d-%H%M).md"
say() { printf '%s\n' "$*" | tee -a "$out"; }
say "# Availability from $srv ($ip), $(date)"
say ""
say '```'
ssh -o ConnectTimeout=15 root@"$ip" 'bash -s' <<'REMOTE' 2>&1 | tee -a "$out"
set -u
C="curl -s --max-time 20"
echo "== geolocation =="
echo "ipinfo:   $($C https://ipinfo.io/json | tr -d '\n' | sed -E 's/ +/ /g' | cut -c1-200)"
echo "ip-api:   $($C 'http://ip-api.com/json/?fields=country,regionName,city,isp,as,hosting,proxy' | tr -d '\n')"
echo "db-ip:    $($C https://api.db-ip.com/v2/free/self | tr -d '\n')"
echo "cloudflare loc: $($C https://www.cloudflare.com/cdn-cgi/trace | grep -E '^(loc|ip)=' | tr '\n' ' ')"
echo "geofeed:  $(whois -h whois.ripe.net "$(curl -s https://ifconfig.co)" 2>/dev/null | grep -i geofeed | head -1)"
echo
echo "== OpenAI / Anthropic (Cloudflare view + block type) =="
echo "chatgpt.com trace: $($C https://chatgpt.com/cdn-cgi/trace | grep -E '^loc=' )"
echo "chatgpt.com head:  $($C -o /dev/null -w '%{http_code}' -A 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) Firefox/128.0' https://chatgpt.com/)  $(curl -sI --max-time 20 https://chatgpt.com/ | grep -i '^cf-mitigated' | tr -d '\r')"
echo "claude.ai trace:   $($C https://claude.ai/cdn-cgi/trace | grep -E '^loc=' )"
echo "claude.ai head:    $(curl -sI --max-time 20 -A 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) Firefox/128.0' https://claude.ai/ | grep -iE '^HTTP|^location|^cf-mitigated' | tr -d '\r' | tr '\n' ' ')"
echo "api.anthropic.com: $($C -o /dev/null -w '%{http_code}' https://api.anthropic.com/v1/models)  (401 = reachable, needs key)"
echo
echo "== Netflix =="
echo "licensed title 70143836: $($C -o /dev/null -w '%{http_code}' -A 'Mozilla/5.0' https://www.netflix.com/title/70143836)   (200 full catalog, 404 originals-only, 403 blocked)"
echo "original title 81280792: $($C -o /dev/null -w '%{http_code}' -A 'Mozilla/5.0' https://www.netflix.com/title/81280792)"
echo
echo "== YouTube / Google =="
yt=$($C -L -A 'Mozilla/5.0' https://www.youtube.com/premium)
echo "youtube premium region: $(echo "$yt" | grep -oE '"INNERTUBE_CONTEXT_GL":"[A-Z]+"' | head -1)  not-available-string: $(echo "$yt" | grep -c 'Premium is not available')"
echo "google search status:   $($C -o /dev/null -w '%{http_code} %{redirect_url}' -A 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) Firefox/128.0' 'https://www.google.com/search?q=test')   (429 or /sorry = captcha-flagged)"
echo "drive.google.com:       $($C -o /dev/null -w '%{http_code}' https://drive.google.com/)"
echo
echo "== UnlockTests (oneclickvirt) =="
if command -v ut >/dev/null 2>&1 || curl -fsSL --max-time 60 https://raw.githubusercontent.com/oneclickvirt/UnlockTests/main/ut_install.sh | bash >/dev/null 2>&1; then
  ut -L en -m 4 -region 21 2>/dev/null | head -60 || true
  echo "--- streaming (Europe) ---"
  ut -L en -m 4 -region 2 2>/dev/null | head -60 || true
else
  echo "UnlockTests install failed; run: bash <(curl -L -s check.unlock.media) -M 4"
fi
REMOTE
say '```'
say "Saved to $out"
