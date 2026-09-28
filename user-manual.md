# User manual

Setup and everyday use of the avmax personal VPN. How it works and why: [architecture.md](architecture.md).
Measurements: [tests/RESULTS.md](tests/RESULTS.md).

| Section | Status (2026-09-27) |
|---|---|
| [0. Control Mac, one-time](#0-control-mac-one-time) | done |
| [1. Cloud server](#1-cloud-server) | `timeweb-almaty` running (temporary), publishing subscriptions on `vpn.avmax.me`; EU server next |
| [2. MacBook](#2-macbook) | done, subscribed to `vpn.avmax.me` |
| [3. iPhone](#3-iphone) | done, subscribed to `vpn.avmax.me` |
| [4. Keenetic router](#4-keenetic-router) | XKeen running; test Mac proxied via policy `xkeen`; whole home next |
| [5. Everyday use](#5-everyday-use) | |
| [6. Troubleshooting](#6-troubleshooting) | |

All commands run from the repository root on the control Mac unless stated otherwise.

---

## 0. Control Mac, one-time

```bash
python3 -m venv .venv && .venv/bin/pip install ansible pyyaml cryptography "qrcode[pil]" anthropic
.venv/bin/python scripts/init-secrets.py          # creates secrets/secrets.yml once; back it up
cp inventory/hosts.example.yml inventory/hosts.yml
cp tests/remote.env.example tests/remote.env      # the test Mac: host, user, folder
```

`ansible/group_vars/all/main.yml` sets `vpn_domain: vpn.avmax.me`, the name devices subscribe to (see 1.6).

---

## 1. Cloud server

### 1.1 Choose and rent

Rent **2 vCPU / 2 GB, Ubuntu 24.04**, hourly or daily billing, and paste this Mac's key (`~/.ssh/id_ed25519.pub`) into the
provider's SSH-key field. The server is only kept if it passes 1.3.

| Provider | Location | Notes |
|---|---|---|
| VDSina | Amsterdam | **failed 2026-09-28:** its address was unreachable from MGTS (blocked on part of Russian networks) |
| UpCloud | Helsinki | Finnish, no Russian network; foreign card needed |
| HostKey | Helsinki, Amsterdam | full speed from home, but its terms exclude Russian residents |
| Avoid | — | Hetzner, Vultr, Linode, Scaleway, DigitalOcean, Contabo (blocked or throttled); Aeza, PQ.Hosting (sanctioned); Timeweb (routes through Russia) |

### 1.2 Add it to the inventory

In `inventory/hosts.yml`, under `eu_candidates` (while testing) or `eu` (when kept):

```yaml
        vdsina-ams:
          ansible_host: 203.0.113.10
```

A host that already serves other things (like `timeweb-almaty`) also goes into group `no_deploy`, with a spare port and a
neutral Reality target, so `site.yml` can never touch it:

```yaml
        timeweb-almaty:
          ansible_host: 92.118.115.34
          xray_reality_port: 8443
          reality_target: "kolesa.kz:443"
          reality_server_name: kolesa.kz
```

### 1.3 Check it before installing anything

First, can your home line reach it at all? (VDSina Amsterdam 146.103.101.8 answered from Finland but not from MGTS or two of
three Russian test points.)

```bash
tests/reach.sh 203.0.113.10          # router-direct ping + SSH banner from home, and check-host.net nodes in Russia and Finland
```

Only if the home line reaches it, continue:

```bash
UT=0 tests/availability.sh vdsina-ams      # UT=1 also installs and runs the UnlockTests suite on the server
```

Keep the server only if all of these hold:
- the **path to Europe** shows no line marked `RUSSIAN HOP`;
- geolocation and Cloudflare (`loc=`) show the server's real country, not RU;
- Netflix title 70143836 returns 200 (full catalog), YouTube Premium region is the server's country;
- chatgpt.com and claude.ai: a `cf-mitigated: challenge` for curl is normal; a region redirect is not.

### 1.4 Install

**Dedicated server** (the normal case). Point the DNS A record of `vpn_domain` at the server first, then:

```bash
cd ansible && ../.venv/bin/ansible-playbook site.yml -l vdsina-ams && cd ..
```

This installs hardening, AmneziaWG, the Caddy website with the subscription files, and Xray on 443.

**Shared host** (a server that runs other things):

```bash
cd ansible && ../.venv/bin/ansible-playbook xray-only.yml -l timeweb-almaty && cd ..
ssh root@92.118.115.34 ufw allow 8443/tcp
```

Only Xray is installed; the host's web server, SSH and firewall rules stay as they were.

### 1.5 Generate client files and test the tunnel

```bash
.venv/bin/python clients/gen.py                      # writes clients/out/ (links, QR codes, rules, router files)
tests/remote.sh matrix vdsina-ams home quick         # tunnel test on the test Mac, home Wi-Fi (~10 min)
tests/remote.sh matrix vdsina-ams mobile quick --detached --wait
```

For the mobile run: start it while the test Mac is on home Wi-Fi, then switch the test Mac to the iPhone hotspot within
15 minutes, wait ~15 minutes, switch back and run `tests/remote.sh collect`. Record the results in `tests/RESULTS.md`.

### 1.6 Publish subscriptions on vpn.avmax.me

Devices subscribe to `https://vpn.avmax.me/s/<token>/<device>` (their server list) and load the rules from
`https://vpn.avmax.me/s/<token>/avmax-split.conf`; the rules file carries its own `update-url`, so Shadowrocket refreshes both.
The exact addresses are in `clients/out/SUBSCRIPTION-URLS.txt`. Anyone without the token gets 404.

- DNS: an **A record `vpn` → the publishing server** at GoDaddy (avmax.me → DNS). Today: `92.118.115.34`.
- Dedicated exit: `site.yml` publishes the files with its own Caddy.
- Shared host (today): one validated `import` line and one site file in its Caddy; nothing else there changes:
  ```bash
  cd ansible && ../.venv/bin/ansible-playbook sub-shared.yml -l timeweb-almaty && cd ..
  ```
- After any change (rules, servers): `.venv/bin/python clients/gen.py`, then re-run the same playbook. Devices pick it up on their
  next refresh (Shadowrocket: pull down on the server list, or wait).

### 1.7 Switch devices to a new server

Deploy the new server, add it to the inventory (move the old one out), `clients/gen.py`, publish (1.6). Devices get the new server
through their subscription. When the publishing server itself changes, move the `vpn` DNS record; the addresses on the devices stay
the same. Router: copy the regenerated `04_outbounds.json` (section 4.4) and run `vpn-mode on`.

### 1.8 Remove Xray from a shared host

```bash
ssh root@92.118.115.34 'systemctl disable --now xray xray-geo-update.timer; rm -rf /usr/local/bin/xray /usr/local/etc/xray /usr/local/share/xray /etc/systemd/system/xray*; ufw delete allow 8443/tcp'
```

And the subscription site (then move the `vpn` DNS record to wherever subscriptions are published next):

```bash
ssh root@92.118.115.34 'sed -i "/import \/etc\/caddy\/avmax-vpn.caddy/d" /etc/caddy/Caddyfile && rm -rf /etc/caddy/avmax-vpn.caddy /var/www/avmax-vpn && systemctl reload caddy'
```

### 1.9 Moscow node (later)

Rent the cheapest Moscow VPS, add it under `msk` in the inventory, then deploy it and the link from the exit:

```bash
cd ansible && ../.venv/bin/ansible-playbook site.yml -l msk && ../.venv/bin/ansible-playbook site.yml -l eu -e msk_link_enabled=true && cd ..
.venv/bin/python clients/gen.py
```

Devices then use the `avmax-<server>-abroad` entry when travelling; Russian sites see the Moscow address.

---

## 2. MacBook

Client: **Shadowrocket** from the Mac App Store (non-Russian Apple ID, $2.99, shared with the iPhone purchase).

### 2.1 Add the subscription (servers)

With Shadowrocket's window open:

```bash
u=$(awk '/^mac:/ {print $2}' clients/out/SUBSCRIPTION-URLS.txt)
open "shadowrocket://add/sub://$(printf %s "$u" | base64 | tr '+/' '-_' | tr -d '=\n')?remark=avmax"
```

A group **avmax** appears with the servers. Alternatively **+ → Type: Subscribe → URL** (the `mac:` line). Shadowrocket's **Import…**
button does *not* accept link files or Clash YAML. Without a domain, `open "vless://…"` adds a single server silently.

### 2.2 Add the rules (self-updating)

**Config** tab → **+** → paste `https://vpn.avmax.me/s/<token>/avmax-split.conf` → download → **Use Config**; on the Home tab
**Global Routing → Config**. Check with **Edit Plain Text**: the file starts with `update-url = …`.
Shadowrocket won't delete the config that's in use: switch to **default.conf** first when replacing it.

### 2.3 Connect

1. Disconnect any other VPN (Amnezia, WireGuard, Outline).
2. Select `avmax-timeweb-almaty`, turn on the main switch, allow the VPN configuration (password or Touch ID, first time only).
3. **Settings → On Demand:** on, rule *connect* on Wi-Fi and Ethernet, so it reconnects after sleep.
   After the router is set up (section 4), add *disconnect* on Wi-Fi SSID `Keenetic-0650`, because the router covers home.

### 2.4 Check

```bash
tests/leak-check.sh
```

Expected: *foreign view* = the exit server, *russian view (ip.beget.ru)* = your home or mobile address, IPv6 empty or the exit.
Then open chatgpt.com, claude.ai, youtube.com, and gosuslugi.ru in the browser.

---

## 3. iPhone

Client: **Shadowrocket** from the App Store with the non-Russian Apple ID.

### 3.1 Add the subscription and the rules

`clients/gen.py` writes two QR codes per device. Show them on the Mac and scan each with Shadowrocket's scan icon (top left):

```bash
open clients/out/iphone/shadowrocket-1-subscribe.png     # adds the subscription (group "avmax")
open clients/out/iphone/shadowrocket-2-rules.png         # adds the self-updating avmax-split.conf
```

Then select the server inside the **avmax** group, and **Config → avmax-split.conf → Use Config**, **Global Routing → Config**.
The codes carry the subscription token: close them afterwards and don't photograph or share them.
Fallback without a domain: `open clients/out/iphone/reality-<server>.png` (one server) and AirDrop `clients/out/sub/avmax-split.conf`.

### 3.2 Connect and set On Demand

Turn on the switch and allow the VPN configuration. **Settings → On Demand:** connect on **Cellular** and on **Wi-Fi**.
After the router is set up, add *disconnect* on SSID `Keenetic-0650`.

### 3.3 Check

On cellular, open `https://ip.beget.ru` (should show your mobile address) and `https://ifconfig.co` (should show the exit
server). Then open ChatGPT, Claude and YouTube.

---

## 4. Keenetic router

Every device on the home Wi-Fi uses the VPN without apps: Russian sites direct, the rest through the exit.
This router: **Keenetic Giga KN-1012** (ARM64), KeeneticOS **5.1.6**, admin at `http://192.168.1.1`.

### 4.1 In the web admin

1. **System → Components:** add **OPKG** ("Open Package support"). The router reboots.
2. **Internet → DNS:** enable DNS-over-TLS or DNS-over-HTTPS profiles (XKeen requires encrypted DNS on the router).
3. **System → Access:** move the web admin off port 443 (XKeen needs 443 free).
4. **Internet → ISP connection → IPv6 configuration:** set it to off (MGTS hands out IPv6; it would bypass the tunnel).
   On KeeneticOS 5 this may not stop the router handing out IPv6 addresses (seen 2026-09-27: devices still got `2a00:…`
   addresses). XKeen's installer offers its own IPv6 switch for this; use it in 4.4 and check with `curl -6 https://ifconfig.co`.

### 4.2 USB stick with Entware

On the control Mac (erases the stick; refuses anything that isn't an external USB disk; asks for your password once):

```bash
HOMEBREW_NO_AUTO_UPDATE=1 brew install e2fsprogs
router/make-usb.sh            # lists external disks, e.g. disk4
router/make-usb.sh disk4      # ext4 "OPKG" with install/EN_aarch64-installer.tar.gz
```

Plug it into the router → **Applications → OPKG → Drive:** the `OPKG` stick → **Save**. Watch **Diagnostics → System log**
until Entware reports it is installed.

### 4.3 Key-based access

Entware's SSH (dropbear) listens on **port 22** on this router (222 only if Keenetic's own SSH component is installed).
Once, in your own Terminal (you type the passwords; afterwards logins use the key):

1. `ssh root@192.168.1.1`, password `keenetic`, answer `yes` to the fingerprint question.
2. On the router: `passwd`, set a new root password (keep it in your password manager).
3. On the router, with the line from the Mac's `~/.ssh/id_ed25519.pub` pasted between the quotes. **This dropbear build reads
   `/opt/etc/dropbear/authorized_keys`**, not `~/.ssh/authorized_keys` (it silently ignored the latter; `dropbear -D` can override):
   ```sh
   echo '<public key line>' >> /opt/etc/dropbear/authorized_keys && chmod 600 /opt/etc/dropbear/authorized_keys
   ```
4. `exit`, then check from the Mac: `ssh -o BatchMode=yes root@192.168.1.1 true` (no password prompt = done).

### 4.4 XKeen and our rules

Router components needed (4.1 plus): **Kernel modules for Netfilter** (XKeen loads `xt_TPROXY.ko`, `xt_socket.ko`).

Install XKeen (the bootstrap installs the `xkeen` command, then starts its interactive setup, so run it in a real terminal):

```bash
ssh -t root@192.168.1.1 'opkg update && opkg install curl tar && sh -c "$(curl -fsSL https://raw.githubusercontent.com/jameszeroX/XKeen/main/install.sh)" x -s'
```

Answers: core **1** (Xray) → release **9**, then `v26.7.28` → GeoSite **0** and GeoIP **0** (we use runetfreedom's files) →
exclude Russian IPs **1** → auto-update **1**, daily 05:00 → start on boot **1**. Setup does not start proxying.

Our configs (from the Mac, after `clients/gen.py`):

```bash
R=root@192.168.1.1
scp clients/out/keenetic/xkeen/04_outbounds.json clients/out/keenetic/xkeen/05_routing.json $R:/opt/etc/xray/configs/
ssh $R mkdir -p /opt/etc/xray/routing && scp clients/out/keenetic/xkeen/routing/*.json $R:/opt/etc/xray/routing/   # never in configs/
scp router/vpn-mode.sh $R:/opt/bin/vpn-mode
ssh $R 'chmod +x /opt/bin/vpn-mode && vpn-mode geo && XRAY_LOCATION_ASSET=/opt/etc/xray/dat xray run -test -confdir /opt/etc/xray/configs'
```

**Who is proxied.** If a connection policy named `xkeen` exists, XKeen proxies only its members; without it, every home device.
Roll out in stages: **Internet → Connection policies → Add policy `xkeen`**, tick **Провайдер 1** in it (so its members keep
internet when XKeen is off), then **Policy Bindings → Default policy → drag devices onto `xkeen`**. Whole home later: make `xkeen`
the home segment's default policy. Check a binding from the router: `ndmc -c "show running-config" | grep 'host <mac>'` shows
`policy Policy0`. Then `vpn-mode on`.

### 4.5 The switch

```bash
ssh root@192.168.1.1 vpn-mode on       # Russian direct, foreign via VPN
ssh root@192.168.1.1 vpn-mode off      # everything direct
ssh root@192.168.1.1 vpn-mode status
```

**One tap:** in the Shortcuts app create "VPN on" / "VPN off" with the action **Run Script Over SSH** (host `192.168.1.1`,
port `22`, user `root`, script `vpn-mode on` / `vpn-mode off`). Add them to the Home Screen or the menu bar.

**Keep one device direct:** add its LAN IP to `ip_exclude.lst` and copy the file again.

### 4.6 Fallback if Reality stops working

Only for a dedicated exit (it runs AmneziaWG; `timeweb-almaty` doesn't).
1. **Internet → Other connections → WireGuard → Load from file:** `clients/out/keenetic/awg-<server>.conf`.
2. Create policy `awg-fallback` whose only connection is that tunnel; assign no devices.
3. `ssh root@192.168.1.1 xkeen -pbr codes` → put the number for `awg-fallback` into `ansible/group_vars/all/main.yml`
   as `xkeen_awg_mark`, run `clients/gen.py`, copy `04_outbounds.json` again.
4. `vpn-mode via awg` (back: `vpn-mode via reality`).

### 4.7 Check

From a device on the home Wi-Fi with no VPN app, `vpn-mode on`: ip.beget.ru shows the home address, ifconfig.co the exit;
`curl -6 https://ifconfig.co` fails. `vpn-mode off`: both show the home address.

---

## 5. Everyday use

### Rules: send a site direct or through the VPN

Edit `rules/custom.json`:

```json
{ "direct": ["example-bank.com", "203.0.113.0/24"], "proxy": ["some-site.ru"], "block": [] }
```

Entries: `example.com` (domain and all subdomains), `full:api.example.com` (exact host), `geosite:yandex` (a v2fly category),
a CIDR. To grow a list from one domain, review the output before applying:

```bash
.venv/bin/python rules/expand.py yandex.ru                   # company list + certificate transparency + homepage crawl
.venv/bin/python rules/expand.py yandex.ru --ai              # also asks Claude (needs an Anthropic API key)
.venv/bin/python rules/expand.py yandex.ru --apply direct    # append to custom.json
```

Then `.venv/bin/python clients/gen.py` and publish (1.6): the Mac and iPhone update themselves. Copy the XKeen files to the
router (4.4), and for the abroad rules redeploy the exit.

### Travelling abroad

Select `avmax-<server>-abroad` in Shadowrocket (needs the Moscow node, 1.9). Russian sites then see a Moscow address.

### Turning the VPN off

Mac/iPhone: turn off **On Demand** in Shadowrocket, then the switch (with On Demand on, the system switch won't stay off).
Home: `vpn-mode off`.

---

## 6. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| This Mac: Claude stops responding after a VPN change | Turn Shadowrocket off, turn Amnezia on, then investigate from the test Mac |
| Shadowrocket shows connected, nothing loads | Server's Xray is 26.9.8 or newer; Shadowrocket 2.2.92 can't talk to it. Keep `xray_version: 26.7.28` |
| Instagram (or another Russia-blocked site) fails intermittently | The exit's route passes through Russia (`timeweb-almaty` does). Move to an exit without a Russian hop |
| `curl https://www.gosuslugi.ru` fails | gosuslugi refuses macOS's command-line curl; check in a browser |
| A test on the test Mac takes far too long or reports nothing | The test Mac slept (it sleeps after 1 minute). Runs use `caffeinate`, but keep the lid open |
| Shadowrocket's Import says "isn't in the correct format" | Use `open "vless://…"`, the QR code, or Type **Subscribe** with a URL |
| Everything slow on mobile | Compare with the direct baseline at the top of the matrix report; if the link itself is slow, the tunnel isn't the cause |
