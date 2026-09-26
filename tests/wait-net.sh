#!/bin/sh
# Wait up to 15 min until this Mac's public IP differs from $1, i.e. it joined another network. Exit 1 on timeout.
echo "waiting until public IP != $1 (switch this Mac to the other network now)"
for i in $(seq 1 90); do
  cur=$(curl -4 -s --max-time 5 https://ipinfo.io/ip)
  if [ -n "$cur" ] && [ "$cur" != "$1" ]; then echo "network changed: public IP now $cur"; sleep 5; exit 0; fi
  sleep 10
done
echo "timed out: network never changed, not running"; exit 1
