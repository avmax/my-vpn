#!/usr/bin/env bash
# Run a test script on the second ("test") Mac over SSH. This Mac stays on its own tunnel; the test Mac is clean.
#   tests/remote.sh sync                               # rsync repo (no secrets) + generated test configs to the test Mac
#   tests/remote.sh recon home                         # run tests/recon.sh home there, stream output
#   tests/remote.sh recon mobile --detached            # start under nohup; switch the test Mac to the hotspot; collect later
#   tests/remote.sh matrix vdsina-ams home             # tests/matrix.sh (interactive prompts for AWG/WG legs are answered by you there)
#   tests/remote.sh leak                               # tests/leak-check.sh
#   tests/remote.sh collect                            # copy tests/out/* back from the test Mac
# Runs are wrapped in caffeinate so the test Mac does not sleep mid-test.
#   tests/remote.sh ssh [cmd]                          # shell / arbitrary command
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f tests/remote.env ] || { echo "create tests/remote.env from tests/remote.env.example" >&2; exit 1; }
. tests/remote.env
T="${TEST_MAC_USER}@${TEST_MAC_HOST}"; D="${TEST_MAC_DIR}"
SSH="ssh -o ConnectTimeout=10 $T"

sync() {
  $SSH "mkdir -p $D"
  rsync -az --delete --exclude '.git' --exclude '.venv' --exclude 'secrets' --exclude 'tests/bin' --exclude 'tests/out' \
        --exclude 'clients/out' ./ "$T:$D/"
  $SSH "mkdir -p $D/clients/out/test $D/tests/bin $D/tests/out"
  # only the local Xray *test* client configs go over (no keys, no AWG confs)
  if [ -d clients/out/test ]; then rsync -az --delete clients/out/test/ "$T:$D/clients/out/test/"; fi
  # the pinned Xray binary + geo files, so the test Mac never needs GitHub
  if [ -x tests/bin/xray ]; then rsync -az tests/bin/xray tests/bin/geoip.dat tests/bin/geosite.dat "$T:$D/tests/bin/"; fi
  echo "synced to $T:$D"
}

run() {   # run <[ENV=val ]script> <args...>; honours --detached and --wait anywhere in args
  local script="$1"; shift; local detached=0 wait=0 args=() envp="" pre=""
  for a in "$@"; do case "$a" in --detached) detached=1;; --wait) wait=1;; *) args+=("$a");; esac; done
  case "$script" in *=*\ *) envp="${script%% *} "; script="${script#* }";; esac
  [ $wait = 1 ] && pre="tests/wait-net.sh $($SSH 'curl -4 -s --max-time 8 https://ipinfo.io/ip') && "
  local cmd="cd $D && mkdir -p tests/out && ${pre}${envp}caffeinate -is tests/$script ${args[*]}"
  if [ $detached = 1 ]; then
    $SSH "nohup sh -c '$cmd' > $D/tests/out/${script%.sh}-detached.log 2>&1 &" \
      && echo "started tests/$script ${args[*]} on $T (log: tests/out/${script%.sh}-detached.log). Switch networks now; later: tests/remote.sh collect"
  else
    ssh -t -o ConnectTimeout=10 "$T" "$cmd"
  fi
}

case "${1:-}" in
  sync)    sync ;;
  recon)   shift; sync >/dev/null; run recon.sh "$@" ;;
  matrix)  shift; sync >/dev/null
           srv="$1"; ip=$(.venv/bin/python -c "import yaml; h=yaml.safe_load(open('inventory/hosts.yml'))['all']['children']; print(next(v['ansible_host'] for g in h.values() for k,v in (g.get('hosts') or {}).items() if k=='$srv'))")
           run "SERVER_IP=$ip matrix.sh" "$@" ;;
  leak)    shift; sync >/dev/null; run leak-check.sh "$@" ;;
  collect) mkdir -p tests/out && rsync -az "$T:$D/tests/out/" tests/out/ && ls -t tests/out | head ;;
  ssh)     shift; ssh -t "$T" "cd $D && ${*:-\$SHELL -l}" ;;
  *)       sed -n '2,10p' "$0"; exit 1 ;;
esac
