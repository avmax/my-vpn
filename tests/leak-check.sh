#!/usr/bin/env bash
# Per device x mode leak check. Run with the mode active (Happ/AWG) and compare against README expectations.
#   Split : RU-hosted echo shows your home ISP / carrier IP, foreign echo shows the EU node IP
#   Full  : both show the EU node IP
#   Abroad: RU-hosted echo shows the Moscow VPS IP, foreign echo shows the EU node IP
set -u
CURL="curl -s --max-time 15"
echo "foreign view (ifconfig.co):  $($CURL https://ifconfig.co/json | jq -r '"\(.ip)  \(.asn_org // .asn)  \(.country)"')"
echo "foreign view (ipinfo.io):    $($CURL https://ipinfo.io/json | jq -r '"\(.ip)  \(.org)  \(.country)"')"
ru=$($CURL -A 'Mozilla/5.0' https://2ip.ru/ | grep -oE 'class="ip"[^<]*<span[^>]*>[^<]+' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
[ -z "$ru" ] && ru=$($CURL https://yandex.ru/internet/api/v0/ip | jq -r '.ip? // empty' 2>/dev/null)
echo "russian view (2ip.ru/yandex): ${ru:-unavailable}"
echo "ipv6 (should be empty/fail): $($CURL -6 https://ifconfig.co 2>/dev/null || echo none)"
id=$(uuidgen | tr 'A-Z' 'a-z' | tr -d '-')
echo "dns resolver seen by ipleak: $($CURL "https://${id}.ipleak.net/dnsdetect/" 2>/dev/null || echo unavailable)"
echo "webrtc: open https://browserleaks.com/webrtc in the browser and confirm no home IP is listed"
