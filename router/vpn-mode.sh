#!/bin/sh
# Runs ON the Keenetic (Entware). Whole-home VPN switch for XKeen.
#   vpn-mode on            foreign traffic via VPN, Russian direct   (xkeen -start)
#   vpn-mode off           everything direct                        (xkeen -stop)
#   vpn-mode via reality   outbound = VLESS Reality (default)
#   vpn-mode via awg       outbound = native AmneziaWG policy (needs xkeen_awg_mark in 04_outbounds.json)
#   vpn-mode geo           refresh runetfreedom geoip/geosite, restart if running
#   vpn-mode servers       list exits (* = in use); files from clients/gen.py in /opt/etc/xray/servers/
#   vpn-mode server NAME   switch the exit (config tested first; the previous one is kept as 04_outbounds.prev.json)
#   vpn-mode status
# Routing variants live in /opt/etc/xray/routing/, NOT in configs/: Xray loads every .json in configs/.
set -e
C=/opt/etc/xray/configs
V=/opt/etc/xray/routing
S=/opt/etc/xkeen/vpn-mode.via
D=/opt/etc/xray/servers
running() { ps | grep -q '[x]ray run'; }
current() { for f in "$D"/*.json; do cmp -s "$f" "$C/04_outbounds.json" && basename "$f" .json; done; true; }
case "${1:-status}" in
  on)  xkeen -start >/dev/null 2>&1 || true; echo "vpn: on (foreign via VPN, Russian direct)";;
  off) xkeen -stop  >/dev/null 2>&1 || true; echo "vpn: off (everything direct)";;
  via)
    case "${2:-}" in
      reality|awg) cp "$V/05_routing_via_$2.json" "$C/05_routing.json"; echo "$2" > "$S"
                   running && xkeen -restart >/dev/null 2>&1; echo "outbound: $2";;
      *) echo "usage: vpn-mode via reality|awg" >&2; exit 1;;
    esac;;
  servers) cur=$(current); for f in "$D"/*.json; do n=$(basename "$f" .json); [ "$n" = "$cur" ] && echo "* $n" || echo "  $n"; done;;
  server)
    f="$D/${2:-}.json"; [ -n "${2:-}" ] && [ -f "$f" ] || { echo "usage: vpn-mode server NAME   (names: vpn-mode servers)" >&2; exit 1; }
    cp "$C/04_outbounds.json" /opt/etc/xray/04_outbounds.prev.json && cp "$f" "$C/04_outbounds.json"
    if XRAY_LOCATION_ASSET=/opt/etc/xray/dat xray run -test -confdir "$C" >/dev/null 2>&1; then
      running && xkeen -restart >/dev/null 2>&1; echo "server: $2"
    else
      cp /opt/etc/xray/04_outbounds.prev.json "$C/04_outbounds.json"; echo "config test failed, still on the previous server" >&2; exit 1
    fi;;
  geo)
    u=https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download
    for f in geoip.dat geosite.dat; do curl -fsSL --retry 3 -o /opt/etc/xray/dat/$f.new "$u/$f" && mv /opt/etc/xray/dat/$f.new /opt/etc/xray/dat/$f; done
    running && xkeen -restart >/dev/null 2>&1; echo "geo files refreshed";;
  status) echo "vpn: $(running && echo on || echo off), server: $(current), outbound: $(cat "$S" 2>/dev/null || echo reality)";;   # on = xray actually running (XKeen starts at boot)
  *) echo "usage: vpn-mode on|off|servers|server NAME|via reality|awg|geo|status" >&2; exit 1;;
esac
