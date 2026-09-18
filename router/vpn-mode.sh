#!/bin/sh
# Runs ON the Keenetic (Entware). Swaps the XKeen routing file and restarts the core.
#   /opt/bin/vpn-mode split|full|status
# Install: copy this file to /opt/bin/vpn-mode (chmod +x) together with
#   /opt/etc/xray/configs/05_routing_split.json and 05_routing_full.json (from clients/out/keenetic/xkeen/).
set -e
D=/opt/etc/xray/configs
case "${1:-status}" in
  split|full)
    cp "$D/05_routing_$1.json" "$D/05_routing.json"
    echo "$1" > /opt/etc/xkeen/vpn-mode
    xkeen -restart >/dev/null 2>&1 || xkeen -start
    echo "router mode: $1" ;;
  status) cat /opt/etc/xkeen/vpn-mode 2>/dev/null || echo "unknown (never set)"; xkeen -status 2>/dev/null | head -5 ;;
  *) echo "usage: vpn-mode split|full|status" >&2; exit 1 ;;
esac
