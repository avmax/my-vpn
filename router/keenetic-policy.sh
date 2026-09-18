#!/usr/bin/env bash
# Move a LAN device between Keenetic connection policies through the RCI API (one call = one tap).
#   router/keenetic-policy.sh <device-mac-or-name> split|full|default
#   router/keenetic-policy.sh --list
# Config via env or ~/.config/keenetic.env: KEENETIC_URL (default http://192.168.1.1), KEENETIC_USER, KEENETIC_PASS,
# POLICY_SPLIT (Keenetic policy id of the XKeen policy, e.g. Policy0), POLICY_FULL (policy whose only connection is AWG).
set -euo pipefail
[ -f "$HOME/.config/keenetic.env" ] && . "$HOME/.config/keenetic.env"
URL="${KEENETIC_URL:-http://192.168.1.1}"; USER_="${KEENETIC_USER:?set KEENETIC_USER}"; PASS="${KEENETIC_PASS:?set KEENETIC_PASS}"
JAR=$(mktemp)
trap 'rm -f "$JAR"' EXIT

auth() {
  # Keenetic challenge auth: password = sha256(challenge + md5("login:realm:password")) in hex
  local hdr realm challenge md5 sha
  hdr=$(curl -s -i -c "$JAR" "$URL/auth")
  realm=$(echo "$hdr" | tr -d '\r' | awk -F': ' '/^X-NDM-Realm/ {print $2}')
  challenge=$(echo "$hdr" | tr -d '\r' | awk -F': ' '/^X-NDM-Challenge/ {print $2}')
  md5=$(printf '%s' "$USER_:$realm:$PASS" | md5 -q 2>/dev/null || printf '%s' "$USER_:$realm:$PASS" | md5sum | cut -d' ' -f1)
  sha=$(printf '%s' "$challenge$md5" | shasum -a 256 | cut -d' ' -f1)
  curl -s -f -b "$JAR" -c "$JAR" -H 'Content-Type: application/json' -X POST "$URL/auth" \
    -d "{\"login\":\"$USER_\",\"password\":\"$sha\"}" >/dev/null
}

rci() { curl -s -f -b "$JAR" -c "$JAR" -H 'Content-Type: application/json' -X POST "$URL/rci/" -d "$1"; }

auth
if [ "${1:-}" = "--list" ]; then
  echo "policies:"; curl -s -b "$JAR" "$URL/rci/show/ip/policy" | jq -r 'to_entries[] | "  \(.key)\t\(.value.description // "")"'
  echo "hosts:";    curl -s -b "$JAR" "$URL/rci/show/ip/hotspot" | jq -r '.host[] | "  \(.mac)\t\(.name // "")\t\(.policy // "default")\t\(.active)"'
  exit 0
fi
dev="${1:?device mac or hotspot name}"; mode="${2:?split|full|default}"
mac=$(curl -s -b "$JAR" "$URL/rci/show/ip/hotspot" | jq -r --arg d "$dev" '.host[] | select(.mac==($d|ascii_downcase) or .name==$d) | .mac' | head -1)
[ -z "$mac" ] && { echo "device '$dev' not found in hotspot list (try --list)" >&2; exit 1; }
case "$mode" in
  split)   pol="${POLICY_SPLIT:?set POLICY_SPLIT}" ;;
  full)    pol="${POLICY_FULL:?set POLICY_FULL}" ;;
  default) pol="" ;;
  *) echo "mode must be split|full|default" >&2; exit 1 ;;
esac
if [ -n "$pol" ]; then
  rci "{\"ip\":{\"hotspot\":{\"host\":{\"mac\":\"$mac\",\"policy\":\"$pol\"}}}}" >/dev/null
else
  rci "{\"ip\":{\"hotspot\":{\"host\":{\"mac\":\"$mac\",\"policy\":{\"no\":true}}}}}" >/dev/null
fi
rci '{"system":{"configuration":{"save":{}}}}' >/dev/null
echo "$mac -> $mode (${pol:-default policy})"
