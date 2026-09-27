# Architecture

How the avmax personal VPN is put together, and why. For step-by-step setup see [user-manual.md](user-manual.md);
for measurements behind the decisions see [tests/RESULTS.md](tests/RESULTS.md).

## Goal

A VPN for a Moscow household that survives Roskomnadzor's DPI (TSPU), sends only **foreign** traffic abroad, and keeps
**Russian** services on a Russian address. At home the router does the work for every device; away from home the Mac and the
iPhone use an app that switches itself on. A Moscow exit is planned for travelling abroad.

## Picture

```
 HOME (Moscow, MGTS)                                  EXIT SERVER (foreign VPS)
 ┌───────────────────────────────┐   VLESS+Reality   ┌────────────────────────────────────────┐
 │ Keenetic Giga KN-1012         │──────────────────►│ Xray 26.7.28                            │──► foreign internet
 │ XKeen (Xray) for all clients  │   (planned)       │  Reality + Vision  (443, or 8443 on a   │    ChatGPT, Claude, YouTube,
 │ vpn-mode on | off             │                   │  shared host)                           │    Google, Netflix …
 └───────────────────────────────┘                   │ Caddy: real website + subscriptions     │
   devices on home Wi-Fi: no apps                    │ AmneziaWG (UDP fallback)                │
                                                     │ awg link to Moscow (planned) ───┐       │
 AWAY (cellular / other Wi-Fi)                       └─────────────────────────────────┼───────┘
 ┌───────────────────────────────┐   VLESS+Reality          ▲                           ▼
 │ MacBook, iPhone: Shadowrocket │──────────────────────────┘         ┌──────────────────────────────┐
 │ On Demand, split rules        │                                    │ Moscow VPS (planned)         │──► Russian internet
 └───────────────────────────────┘                                    │ AmneziaWG + NAT, RU address  │    when you are abroad
 Russian destinations always leave directly from wherever the device is └──────────────────────────────┘
```

**Today (2026-09-27):** the exit is `timeweb-almaty` (Timeweb, Almaty, AS9123), a *shared* production host running Xray alone
on port 8443. The MacBook runs Shadowrocket against it. iPhone, router and the Moscow node are next. The exit is temporary:
its traffic to Europe transits Moscow, so some Russia-blocked services (Instagram) fail intermittently. See *Constraints*.

## Modes

| Where | State | Russian destinations | Foreign destinations | How it switches |
|---|---|---|---|---|
| Home Wi-Fi (router) | `vpn-mode on` | direct | exit server | one tap: Shortcut → SSH to the router |
| Home Wi-Fi (router) | `vpn-mode off` | direct | direct | same |
| Mac / iPhone away | Shadowrocket connected | direct | exit server | automatic (On Demand) |
| Mac / iPhone abroad | `avmax-<server>-abroad` selected | Moscow VPS, via the exit | exit server | pick that server in Shadowrocket |

## Components

| Part | Where it runs | What it does | Source |
|---|---|---|---|
| Xray (server) | exit VPS | VLESS + Reality + XTLS-Vision inbound; XHTTP inbound behind Caddy; "abroad" routing to the Moscow link | `ansible/roles/xray` |
| Caddy | exit VPS (dedicated only) | the real website Reality imitates ("steal oneself"), Let's Encrypt, private subscription files under `/s/<token>/` | `ansible/roles/caddy` |
| AmneziaWG | exit VPS (dedicated only), Moscow VPS | obfuscated WireGuard as the UDP fallback; server side of the Moscow link | `ansible/roles/awg`, `awg-link` |
| Base hardening | every dedicated VPS | key-only SSH, ufw, fail2ban, unattended upgrades, BBR, IPv6 off | `ansible/roles/base` |
| Shadowrocket | MacBook, iPhone | VLESS Reality client, split rules, On Demand | config from `clients/gen.py` |
| XKeen (Xray) | Keenetic router, Entware on USB | transparent proxy for every LAN device, same split rules | `router/`, `clients/gen.py` |
| Control Mac | this MacBook, the repo | Ansible, secrets, client-config generator, tests | whole repo |
| Test Mac | second MacBook on the LAN | runs every network test so a broken tunnel never cuts the working Mac | `tests/remote.sh` |

## Protocols

- **Primary: VLESS + Reality + XTLS-Vision over TCP.** To DPI it looks like a TLS 1.3 visit to a real website. Clients use
  the **firefox** TLS fingerprint (Chrome/Safari fingerprints are flagged since June 2026), no multiplexing.
  - Dedicated server: port 443, the imitated site is our own Caddy site on the server's own domain, so address, name and
    certificate all match.
  - Shared host (`timeweb-almaty`): port 8443 (Caddy owns 443 there), imitating `kolesa.kz` (TLS 1.3, HTTP/2, own network).
- **Secondary: VLESS over XHTTP** behind Caddy on the same 443, for when plain Reality gets frozen. Dedicated servers only.
- **Fallback: AmneziaWG 2.0** (UDP, junk packets + a QUIC-shaped I1 packet). The router supports it natively (KeeneticOS 5.1).
  Dedicated servers only.
- **Not used:** plain WireGuard, OpenVPN, IKEv2/L2TP (signature-blocked), Hysteria/TUIC as primary (UDP throttled),
  anything fronted by Cloudflare (throttled), big-brand Reality targets like Apple or Google (address mismatch is a trigger).

## Routing rules

One rule set, three layers, first match wins, compiled by `clients/gen.py` into every target:

1. **Your overrides** — `rules/custom.json` with `direct`, `proxy`, `block` lists (domains, `geosite:` tags, CIDRs).
2. **Automatic geo detection** — v2fly `category-ru` and `ru-available-only-inside`, the `.ru/.su/.рф` zones, `geoip:ru`,
   private ranges → direct.
3. **Everything else → VPN.**

| Target | Where layer 2 comes from |
|---|---|
| Shadowrocket (`avmax-split.conf`) | ~1,950 Russian domains inlined as `DOMAIN-SUFFIX,…,DIRECT`, then `.ru/.su/.рф`, `GEOIP,RU`, `FINAL,PROXY` |
| XKeen (`05_routing.json`) | runetfreedom geosite/geoip files on the router; plus XKeen's ipsets keep Russian subnets and `ip_exclude.lst` out of the proxy entirely |
| Server "abroad" rules | same geosite/geoip on the server; custom `direct` entries also go to Moscow |
| Happ (optional client) | `happ://routing/onadd/…` profile |

`rules/expand.py <domain>` grows a list from one domain (v2fly company lists, certificate-transparency subdomains, the
site's own links, optionally Claude) for review before it is appended to `custom.json`.

## Servers: two layouts

| | Dedicated exit (target) | Shared host (today: `timeweb-almaty`) |
|---|---|---|
| Playbook | `ansible/site.yml` (base, awg, caddy, xray) | `ansible/xray-only.yml` (xray only) |
| Open ports | 22, 80 (ACME + redirect), 443 (Reality; others see the real site), one UDP (AWG) | 8443 added; everything else untouched |
| Reality target | own Caddy site on `eu.<domain>` | a neutral site (`kolesa.kz`) |
| Subscriptions | own Caddy, `site.yml` | `sub-shared.yml`: one import line in the host's Caddy |
| Safety | — | host is in inventory group `no_deploy`, which both plays of `site.yml` exclude |

## Distributing configs to devices

Devices subscribe to **`vpn.avmax.me`** (A record at GoDaddy): `https://vpn.avmax.me/s/<token>/<device>` is the base64 list of that
device's server links, `…/avmax-split.conf` the rules, which name themselves as `update-url` so Shadowrocket refreshes them.
Wrong paths and the bare domain return 404.

- **Today:** the shared host `timeweb-almaty` publishes them: `ansible/sub-shared.yml` adds one validated `import` line and one site
  file to its Caddy and copies the files; its production sites are untouched.
- **Later:** a dedicated exit publishes them with its own Caddy (`site.yml`); moving the `vpn` DNS record moves the service,
  and the addresses on the devices never change.
- **Enrolment:** Mac via the `shadowrocket://add/sub://…` link and the config URL; iPhone by scanning two generated QR codes
  (`clients/out/<device>/shadowrocket-1-subscribe.png`, `…-2-rules.png`).

## Secrets

`scripts/init-secrets.py` creates `secrets/secrets.yml` once (gitignored, back it up): Reality X25519 key pair, per-device
UUIDs (home and abroad) and short IDs, AmneziaWG keys and obfuscation parameters, the Moscow-link keys, the XHTTP path and the
subscription token. Generated client files land in `clients/out/` (gitignored). Server links and QR codes are logins: share
them only between your own devices.

## DNS and IPv6

- Direct (Russian) names resolve locally, so Russian CDNs serve from Russia. Proxied names are resolved by the exit.
- The exit leaves over **IPv4 only**: Google geolocates Timeweb's IPv6 as Russia, and the dedicated servers disable IPv6.
- MGTS gives home devices native IPv6. The router phase must turn it off or proxy it, or foreign sites with IPv6 bypass the tunnel.

## Constraints and decisions

- **Xray stays on 26.7.28.** From 26.9.8, Reality servers demand an ML-KEM key share that Shadowrocket 2.2.92 does not send
  (connections look up, nothing loads). Upgrade only after Shadowrocket and XKeen's core handle it.
- **No Russian transit.** An exit whose route to Europe passes through Russia inherits Russian filtering. `tests/availability.sh`
  flags any Russian hop; `timeweb-almaty` fails this check.
- **Hosters.** Dead or frozen from the home line (measured 2026-09-19): Hetzner, Vultr, Linode, Scaleway. OVH downloaded at full
  speed at home but trickled on mobile. Sanctioned: Aeza, PQ.Hosting. Timeweb's foreign ranges are also reported as seen from Russia. Candidates: VDSina Amsterdam, UpCloud Helsinki.
- **Legal.** Personal use is not an offence in Russia; sharing or advertising the server is. Keep it to your own devices.

## Known limits

- Mobile "whitelist" shutdowns block every foreign server, whatever the protocol.
- Russian platforms degrade users seen from foreign addresses, which is why Russian traffic always goes direct.
- On Tinkoff mobile the tunnel reaches the link's own speed on sustained downloads, but two bulk transfers failed in both runs;
  cause not yet known.
