# avmax personal VPN

Russian sites go direct, everything else goes through our server abroad over VLESS + Reality, which looks like ordinary HTTPS to DPI.
At home the Keenetic router covers every device. Away from home, the MacBook and iPhone use Shadowrocket.

- [user-manual.md](user-manual.md): install and daily use
- [architecture.md](architecture.md): how it works and why
- [tests/RESULTS.md](tests/RESULTS.md): measurements

## Status (2026-09-29)

| Part | State |
|---|---|
| Exit | `hostung-de` 213.209.135.6, hostung.net (Cherry Servers), Germany. The router uses it; Mac and iPhone can pick it |
| Backup exit | `timeweb-almaty` 92.118.115.34:8443. Routes via Moscow, so Instagram is flaky |
| Subscriptions | `vpn.avmax.me`, served from Almaty; devices refresh servers and rules themselves |
| MacBook, iPhone | Shadowrocket, subscribed |
| Router | XKeen, policy `xkeen`, exit `hostung-de` |
| Moscow node (travel) | not built |

## Router: VPN on/off, switch server

```bash
ssh root@192.168.1.1 vpn-mode off       # everything direct: Russian sites work, blocked ones don't
ssh root@192.168.1.1 vpn-mode on        # Russian direct, the rest via VPN
ssh root@192.168.1.1 vpn-mode status
ssh root@192.168.1.1 vpn-mode servers                 # exit servers; * = in use
ssh root@192.168.1.1 vpn-mode server timeweb-almaty   # switch the home exit (hostung-de | timeweb-almaty)
```

Without a terminal: `http://192.168.1.1` → **Internet → Connection priorities → Policy bindings**, then move the devices
from `xkeen` back to **Default policy**. Last resort: unplug the router's USB stick.

## Commands

```bash
.venv/bin/python clients/gen.py                                    # regenerate all client files after any change
cd ansible && ../.venv/bin/ansible-playbook sub-shared.yml -l timeweb-almaty && cd ..   # publish subscriptions
cd ansible && ../.venv/bin/ansible-playbook site.yml -l <server> && cd ..               # deploy or update an exit
tests/reach.sh <ip>                     # new server: reachable from the home line? (before installing)
tests/router-tunnel.sh <server>         # tunnel from the home line: exit country, sites, speed
UT=0 tests/availability.sh <server>     # services as seen from the server
tests/leak-check.sh                     # what Russian and foreign sites see from this Mac
```

## Layout

```
ansible/     site.yml (own exit), xray-only.yml + sub-shared.yml (shared host), group_vars/all/main.yml
inventory/   hosts.yml (gitignored; see hosts.example.yml)
secrets/     secrets.yml (gitignored; back it up)
clients/     gen.py → clients/out/ (gitignored): subscriptions, QR codes, rules, router files
rules/       custom.json (your overrides), expand.py (one domain → all its domains)
router/      vpn-mode.sh (on/off switch on the router), make-usb.sh (Entware stick), keenetic-policy.sh
tests/       reach, router-tunnel, availability, leak-check, matrix/remote (test Mac), RESULTS.md
```

## Don't break

- **Almaty is production** for here4you.space and cognitiveos.app. Only `xray-only.yml` and `sub-shared.yml` may touch it.
  Group `no_deploy` keeps `site.yml` off it. After editing the inventory, run `ansible-playbook site.yml --list-hosts`.
- **Xray stays at 26.7.28.** Shadowrocket 2.2.92 can't connect to 26.9.8 or newer.
- **Server links, QR codes and `secrets/` are logins.** Keep them on your own devices.
