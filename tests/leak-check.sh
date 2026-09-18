#!/usr/bin/env bash
# Per device x mode leak check. Run with the mode active (Happ/AWG) and compare with the expectations:
#   Split : Russian view = your home ISP / carrier IP, foreign view = EU node IP
#   Full  : Russian view = EU node IP, foreign view = EU node IP
#   Abroad: Russian view = Moscow VPS IP, foreign view = EU node IP
# Resolver line: in Split, RU-hosted resolver; in Full/Abroad, the tunnel's resolver (never the ISP's).
set -u
CURL="curl -s --max-time 15"
echo "foreign view (ifconfig.co):  $($CURL https://ifconfig.co/json | jq -r '"\(.ip)  \(.asn_org // .asn // "")  \(.country)"')"
echo "foreign view (ipinfo.io):    $($CURL https://ipinfo.io/json | jq -r '"\(.ip)  \(.org)  \(.country)"')"
echo "russian view (ip.beget.ru):  $($CURL https://ip.beget.ru || echo unavailable)"
v6=$($CURL https://ipv6.icanhazip.com 2>/dev/null); echo "ipv6 (must be empty):        ${v6:-none, good}"
echo "resolver seen by akamai:     $(dig +short -t txt whoami.ds.akahelp.net 2>/dev/null | tr '\n' ' ')"
echo "resolver seen by google:     $(dig +short -t txt o-o.myaddr.l.google.com 2>/dev/null | tr '\n' ' ')"
echo "webrtc: open https://browserleaks.com/webrtc and confirm no home IP is listed"
