#!/usr/bin/env bash
# Is a freshly rented server reachable from Russia? Run BEFORE installing anything on it.
#   tests/reach.sh 203.0.113.10 [port]
# 1. From the home line directly: the router's own traffic goes out over MGTS, not through XKeen.
# 2. From check-host.net nodes: several in Russia (different ISPs) plus Finland as the control.
# A server that fails 1 is useless as an exit, whatever it passes elsewhere (VDSina AMS 146.103.101.8, 2026-09-28).
set -u
ip="${1:?server IP}"; port="${2:-22}"
echo "== home line (router, direct MGTS) =="
# Busybox nc has no flags: `(sleep N) | nc` holds the flow open. curl telnet:// returned nothing even for good hosts.
# 443: "refused" in 0s = packets reach the host; a timeout = dropped. The real TLS test comes after install.
ssh -o BatchMode=yes -o ConnectTimeout=8 root@192.168.1.1 "echo \"  ping: \$(ping -c 3 -W 2 $ip 2>&1 | tail -1)\"
echo \"  tcp $port silent: \$( (sleep 5) | /opt/bin/nc $ip $port 2>&1 | head -n1 | head -c 50 | tr -d '\r')\"
echo \"  tcp $port with SSH client banner: \$( (printf 'SSH-2.0-OpenSSH_10.3\r\n'; sleep 5) | /opt/bin/nc $ip $port 2>&1 | head -n1 | head -c 50 | tr -d '\r')\"
curl -sk -o /dev/null --connect-timeout 8 https://$ip/; echo \"  tcp 443: curl rc=\$? (7 = refused/reachable, 28 = dropped, 0/35 = TLS answered)\"" 2>&1
echo "== check-host.net nodes =="
id=$(curl -s --max-time 15 -H 'Accept: application/json' "https://check-host.net/check-tcp?host=$ip:$port&node=ru1.node.check-host.net&node=ru2.node.check-host.net&node=ru3.node.check-host.net&node=ru4.node.check-host.net&node=fi1.node.check-host.net" | grep -oE '"request_id":"[a-z0-9]+"' | cut -d'"' -f4)
[ -n "$id" ] || { echo "  check-host.net unavailable"; exit 0; }
for i in 1 2 3 4 5 6; do r=$(curl -s --max-time 15 -H 'Accept: application/json' "https://check-host.net/check-result/$id"); [ "$(echo "$r" | grep -o null | wc -l | tr -d ' ')" = 0 ] && break; sleep 4; done
echo "$r" | tr '{}' '\n\n' | grep -oE '"[a-z0-9]+\.node[^:]*|"time":[0-9.]+|"error":"[^"]*"' | tr -d '"' | paste - - | sed 's/.node.check-host.net//; s/^/  /'
