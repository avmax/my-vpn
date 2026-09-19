#!/bin/sh
# Runs ON the Keenetic (Entware). Whole-home VPN switch for XKeen in no-policy mode.
#   vpn-mode on            foreign traffic via VPN (Russian direct)   = xkeen -start
#   vpn-mode off           everything direct                          = xkeen -stop
#   vpn-mode via reality   XKeen outbound = VLESS Reality (default)
#   vpn-mode via awg       XKeen outbound = native AmneziaWG policy (fallback; needs xkeen_awg_mark in 04_outbounds.json)
#   vpn-mode status
# Install: scp to /opt/bin/vpn-mode, chmod +x. Routing files come from clients/out/keenetic/xkeen/.
set -e
D=/opt/etc/xray/configs
S=/opt/etc/xkeen/vpn-mode.state
case "${1:-status}" in
  on)  xkeen -start >/dev/null 2>&1 || true; echo on > "$S"; echo "vpn: on (foreign via VPN, Russian direct)";;
  off) xkeen -stop  >/dev/null 2>&1 || true; echo off > "$S"; echo "vpn: off (everything direct)";;
  via)
    case "${2:-}" in
      reality|awg) cp "$D/05_routing_via_$2.json" "$D/05_routing.json"; echo "$2" > "$S.via"
                   [ "$(cat "$S" 2>/dev/null)" = on ] && xkeen -restart >/dev/null 2>&1; echo "outbound: $2";;
      *) echo "usage: vpn-mode via reality|awg" >&2; exit 1;;
    esac;;
  status) echo "vpn: $(cat "$S" 2>/dev/null || echo unknown), outbound: $(cat "$S.via" 2>/dev/null || echo reality)"; xkeen -status 2>/dev/null | head -3 || true;;
  *) echo "usage: vpn-mode on|off|via reality|awg|status" >&2; exit 1;;
esac
