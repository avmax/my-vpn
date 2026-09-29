#!/usr/bin/env bash
# Reality tunnel from the home line: a temporary Xray client on the router (port 10808, beside XKeen) to one exit.
#   tests/router-tunnel.sh <inventory-host-name>      (after clients/gen.py; run from the repo root)
set -eu
cfg="clients/out/test/${1:?inventory host name}/reality.json"
sed 's/"port": 1080,/"port": 10808,/' "$cfg" | ssh -o BatchMode=yes root@192.168.1.1 'cat > /tmp/rt.json
/opt/sbin/xray run -c /tmp/rt.json >/tmp/rt.log 2>&1 & pid=$!; sleep 2
P="--socks5-hostname 127.0.0.1:10808"
echo "exit:   $(curl -s --max-time 15 $P https://ipinfo.io/json | tr -d "\n " | grep -oE "\"(ip|city|country|org)\":\"[^\"]*\"" | tr "\n" " ")"
for u in https://www.gstatic.com/generate_204 https://www.instagram.com/ https://www.youtube.com/ https://claude.ai/cdn-cgi/trace; do
  echo "$(curl -s --max-time 15 $P -o /dev/null -w "%{http_code} %{time_total}s" $u)  $u"; done
echo "100 MB: $(curl -s --max-time 60 $P -o /dev/null -w "%{speed_download}" http://cachefly.cachefly.net/100mb.test | awk "{printf \"%.0f Mbit/s\", \$1*8/1e6}")"
kill $pid'
