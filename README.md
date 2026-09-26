# avmax personal VPN

A self-hosted split-tunnel VPN for a Moscow household. Foreign traffic leaves through your own server abroad, disguised
from Roskomnadzor's DPI as ordinary HTTPS (VLESS + Reality); Russian sites keep seeing your Russian address. At home the
Keenetic router covers every device; away from home the MacBook and iPhone switch on by themselves.

- **[user-manual.md](user-manual.md):** setup of the cloud server, MacBook, iPhone and router, plus everyday use and troubleshooting.
- **[architecture.md](architecture.md):** how the pieces fit, protocols, routing rules, constraints and why.
- **[tests/RESULTS.md](tests/RESULTS.md):** every measurement the decisions rest on.

## Status (2026-09-27)

| Step | State |
|---|---|
| Network recon (home MGTS, Tinkoff mobile) | done |
| Exit server | `timeweb-almaty` (Timeweb, Almaty) running as a temporary exit on port 8443; routes through Moscow, so an EU server comes next |
| MacBook | done: Shadowrocket, split rules, Amnezia retired |
| iPhone | done: Shadowrocket via QR code + AirDropped rules |
| Keenetic router (KN-1012, KeeneticOS 5.1.6) | prepared (USB tooling, configs), not started |
| EU exit server (VDSina Amsterdam or UpCloud Helsinki) | after the router |
| Moscow node for travelling | later |

## Layout

```
ansible/          site.yml (dedicated exit: base, awg, caddy, xray, awg-link), xray-only.yml (shared hosts), group_vars
inventory/        hosts.yml (gitignored; copy from hosts.example.yml); group no_deploy protects shared hosts from site.yml
secrets/          secrets.yml from scripts/init-secrets.py (gitignored; back it up)
clients/gen.py    writes clients/out/ (gitignored): server links + QR codes, avmax-split.conf, subscriptions, XKeen and AWG files
rules/            custom.json (your overrides), expand.py (grow a list from one domain)
router/           make-usb.sh (Entware stick), vpn-mode.sh (runs on the router), keenetic-policy.sh (per-device policies)
tests/            recon, matrix (tunnel), availability (from the server), leak-check; remote.sh runs them on the test Mac
```

## Everyday commands

```bash
.venv/bin/python clients/gen.py                                   # regenerate every client file after any change
cd ansible && ../.venv/bin/ansible-playbook site.yml -l <server>  # deploy or update a dedicated exit
UT=0 tests/availability.sh <server>                               # route, geolocation and service checks from the server
tests/remote.sh matrix <server> home quick                        # tunnel test from the test Mac
tests/leak-check.sh                                               # what Russian and foreign sites see from this device
```

## Safety notes

- `timeweb-almaty` is also the production host of here4you.space and cognitiveos.app. It only ever gets `xray-only.yml`;
  its membership in `no_deploy` keeps `site.yml` off it. Check with `ansible-playbook site.yml --list-hosts` after inventory edits.
- Keep the server on Xray **26.7.28**: Shadowrocket 2.2.92 cannot connect to 26.9.8 or newer.
- Server links, QR codes and `secrets/` are logins. Share them only between your own devices.
