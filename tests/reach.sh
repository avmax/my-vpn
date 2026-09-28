#!/usr/bin/env bash
# Is a freshly rented server reachable from Russia? Run BEFORE installing anything on it.
#   tests/reach.sh 203.0.113.10 [port]
# 1. From the home line directly: the router's own traffic goes out over MGTS, not through XKeen.
# 2. From check-host.net nodes: several in Russia (different ISPs) plus Finland as the control.
# A server that fails 1 is useless as an exit, whatever it passes elsewhere (VDSina AMS 146.103.101.8, 2026-09-28).
set -u
ip="${1:?server IP}"; port="${2:-22}"
echo "== home line (router, direct MGTS) =="
ssh -o BatchMode=yes -o ConnectTimeout=8 root@192.168.1.1 "echo \"  ping: \$(ping -c 3 -W 2 $ip 2>&1 | tail -1)\"; b=\$(curl -s --max-time 10 telnet://$ip:$port </dev/null 2>/dev/null | head -c 40 | tr -d '\r'); echo \"  tcp $port: \${b:-NO ANSWER}\"" 2>&1
echo "== check-host.net nodes =="
id=$(curl -s --max-time 15 -H 'Accept: application/json' "https://check-host.net/check-tcp?host=$ip:$port&node=ru1.node.check-host.net&node=ru2.node.check-host.net&node=ru3.node.check-host.net&node=ru4.node.check-host.net&node=fi1.node.check-host.net" | grep -oE '"request_id":"[a-z0-9]+"' | cut -d'"' -f4)
[ -n "$id" ] || { echo "  check-host.net unavailable"; exit 0; }
for i in 1 2 3 4 5 6; do r=$(curl -s --max-time 15 -H 'Accept: application/json' "https://check-host.net/check-result/$id"); [ "$(echo "$r" | grep -o null | wc -l | tr -d ' ')" = 0 ] && break; sleep 4; done
echo "$r" | tr '{}' '\n\n' | grep -oE '"[a-z0-9]+\.node[^:]*|"time":[0-9.]+|"error":"[^"]*"' | tr -d '"' | paste - - | sed 's/.node.check-host.net//; s/^/  /'
