# Install & use manual

Run commands from the repo root on this Mac. Why things are this way: [architecture.md](architecture.md).

1. [Control Mac (once)](#1-control-mac-once)
2. [Exit server](#2-exit-server)
3. [MacBook](#3-macbook)
4. [iPhone](#4-iphone)
5. [Keenetic router](#5-keenetic-router)
6. [Daily use](#6-daily-use)
7. [Troubleshooting](#7-troubleshooting)

---

## 1. Control Mac (once)

```bash
python3 -m venv .venv && .venv/bin/pip install ansible pyyaml cryptography "qrcode[pil]" anthropic
.venv/bin/python scripts/init-secrets.py          # secrets/secrets.yml; back it up
cp inventory/hosts.example.yml inventory/hosts.yml
```

---

## 2. Exit server

### Where to rent (tested from the home MGTS line)

| Provider | Result |
|---|---|
| **hostung.net**, VPS S-1, Germany (Cherry Servers) | **in use.** $3.19/month, 100–280 Mbit/s |
| HostKey (Helsinki, Amsterdam) | fast, but its terms exclude Russian residents |
| VDSina (Amsterdam) | blocked: TLS on 443 never connects |
| Avoid | Hetzner, Vultr, Linode, Scaleway, Contabo (blocked or throttled); Aeza, PQ.Hosting (sanctioned); Timeweb (routes via Russia) |

### New server: steps

1. **Rent:** Ubuntu 24.04, monthly billing, cheapest plan (1 vCPU / 1 GB is enough).
2. **Check from home before anything else:**
   ```bash
   tests/reach.sh <ip>
   ```
   Keep it only if ping works, both `tcp 22` lines show `SSH-2.0-…`, and `tcp 443` shows `rc=7` (`28` means blocked).
3. **Add your SSH key.** You type the root password from the provider's email:
   ```bash
   ssh-copy-id -i ~/.ssh/id_ed25519.pub root@<ip>
   ```
4. **DNS:** GoDaddy → avmax.me → DNS → add record **A**, name `vpn<name>`, value `<ip>`, TTL 600.
5. **Inventory** (`inventory/hosts.yml`, under `eu_candidates`):
   ```yaml
           new-server:
             ansible_host: <ip>
             vpn_domain: vpn<name>.avmax.me
             ready: false
   ```
6. **Install** (firewall, SSH hardening, website + certificate, Xray on 443, AmneziaWG):
   ```bash
   cd ansible && ../.venv/bin/ansible-playbook site.yml -l new-server && cd ..
   ```
   If a brand-new server fails with `Could not get lock /var/lib/dpkg`, Ubuntu's first-boot updates are running. Wait 15 minutes and run it again.
7. **Test from home:**
   ```bash
   .venv/bin/python clients/gen.py
   tests/router-tunnel.sh new-server       # exit country, Instagram/YouTube/Claude, 100 MB speed
   UT=0 tests/availability.sh new-server   # services as the server sees them
   ```
   Pass: the exit shows the server's country, speed is above 50 Mbit/s, and there's no `RUSSIAN HOP`. YouTube should show the
   server's country, and Netflix should land on `/xx-en/` (not 403). Curl gets a 403 "challenge" from claude.ai and chatgpt.com;
   that's normal, so check those in a browser.
8. **Give it to devices:** delete `ready: false`, run `clients/gen.py`, and publish (next section). Then pick it in Shadowrocket.
9. **Give it to the router:** see [5.6](#56-change-the-routers-exit-server).

### Publish subscriptions (vpn.avmax.me)

Devices pull their server list and rules from `https://vpn.avmax.me/s/<token>/…`. The exact URLs are in
`clients/out/SUBSCRIPTION-URLS.txt`. Today they're served from Almaty (DNS `vpn` → 92.118.115.34).

```bash
.venv/bin/python clients/gen.py
cd ansible && ../.venv/bin/ansible-playbook sub-shared.yml -l timeweb-almaty && cd ..
```

Run this after any change to servers or rules. Devices pick it up on their next refresh.

### Shared host (Almaty): Xray only

```bash
cd ansible && ../.venv/bin/ansible-playbook xray-only.yml -l timeweb-almaty && cd ..
```

Keep it in group `no_deploy`, with port 8443 and Reality target `kolesa.kz`. Its web server and firewall stay untouched.

To remove it completely (and move the `vpn` DNS record to wherever subscriptions go next):

```bash
ssh root@92.118.115.34 'systemctl disable --now xray xray-geo-update.timer; rm -rf /usr/local/bin/xray /usr/local/etc/xray /usr/local/share/xray /etc/systemd/system/xray*; ufw delete allow 8443/tcp'
ssh root@92.118.115.34 'sed -i "/import \/etc\/caddy\/avmax-vpn.caddy/d" /etc/caddy/Caddyfile && rm -rf /etc/caddy/avmax-vpn.caddy /var/www/avmax-vpn && systemctl reload caddy'
```

### Moscow node (later, for travelling)

Put a cheap Moscow VPS under `msk` in the inventory, then:

```bash
cd ansible && ../.venv/bin/ansible-playbook site.yml -l msk && ../.venv/bin/ansible-playbook site.yml -l eu -e msk_link_enabled=true && cd ..
.venv/bin/python clients/gen.py
```

---

## 3. MacBook

1. Install **Shadowrocket** from the Mac App Store (non-Russian Apple ID).
2. **Servers:** with Shadowrocket open, run:
   ```bash
   u=$(awk '/^mac:/ {print $2}' clients/out/SUBSCRIPTION-URLS.txt)
   open "shadowrocket://add/sub://$(printf %s "$u" | base64 | tr '+/' '-_' | tr -d '=\n')?remark=avmax"
   ```
   Group **avmax** appears. (Manual way: **+ → Type: Subscribe → URL**. The **Import…** button won't take links.)
3. **Rules:** **Config** tab → **+** → paste the `avmax-split.conf` URL from `SUBSCRIPTION-URLS.txt` → **Use Config**.
   Then on **Home**, set **Global Routing → Config**.
4. Turn off any other VPN. Select **avmax-hostung-de** and turn the switch on.
5. **Settings → On Demand:** on, with *connect* on Wi-Fi and Ethernet. At home it's fine to leave it on: the router sends the
   tunnel straight out.
6. **Check:** `tests/leak-check.sh`. The foreign view should show the exit; ip.beget.ru should show your home address.

To swap the rules file, switch to **default.conf** first. Shadowrocket won't delete the config in use.

---

## 4. iPhone

1. Install **Shadowrocket** from the App Store (non-Russian Apple ID).
2. On the Mac, open the two QR codes and scan each with Shadowrocket's scan icon (top left):
   ```bash
   open clients/out/iphone/shadowrocket-1-subscribe.png     # servers
   open clients/out/iphone/shadowrocket-2-rules.png         # rules
   ```
   The QR codes contain your login. Close them afterwards and don't share them.
3. **Config → avmax-split.conf → Use Config**, then **Home → Global Routing → Config**.
4. Select **avmax-hostung-de** and turn the switch on.
5. **Settings → On Demand:** *connect* on Cellular and Wi-Fi.
6. **Check** on mobile data: ip.beget.ru should show your mobile address, and ipinfo.io the exit.

**Update servers:** swipe the **avmax** group left → **Update**.

---

## 5. Keenetic router

Keenetic Giga KN-1012, KeeneticOS 5.1.6, admin at `http://192.168.1.1`. Devices in policy `xkeen` get the VPN with no app:
Russian sites go direct, the rest via the exit.

### 5.1 Web admin

1. **System → Components:** add **OPKG** and **Kernel modules for Netfilter**. The router reboots.
2. **Internet → DNS:** enable DNS-over-HTTPS (dns.google, cloudflare-dns.com).
3. **System → Access:** move the web admin off port 443.
4. **Internet → ISP connection:** IPv6 off.
5. **Network accelerator off.** It takes over long UDP streams and skips XKeen, so call audio dies every few minutes:
   ```bash
   ssh root@192.168.1.1 'ndmc -c "no ppe software"; ndmc -c "no ppe hardware"; ndmc -c "system configuration save"'
   ```

### 5.2 USB stick (Entware)

On this Mac. It erases the stick and refuses anything that isn't an external USB disk:

```bash
HOMEBREW_NO_AUTO_UPDATE=1 brew install e2fsprogs
router/make-usb.sh            # lists disks, e.g. disk4
router/make-usb.sh disk4
```

Plug it into the router → **Applications → OPKG → Drive: OPKG → Save**. Wait until **Diagnostics → System log** says
Entware is installed.

### 5.3 SSH key

In your own Terminal (you type the passwords):

1. `ssh root@192.168.1.1`, password `keenetic`, answer `yes`.
2. `passwd` sets a new root password. Keep it in your password manager.
3. Add this Mac's key. It goes in `/opt/etc/dropbear/`, not `~/.ssh/`:
   ```sh
   echo '<line from ~/.ssh/id_ed25519.pub>' >> /opt/etc/dropbear/authorized_keys && chmod 600 /opt/etc/dropbear/authorized_keys
   ```
4. `exit`, then check: `ssh -o BatchMode=yes root@192.168.1.1 true` should succeed with no password prompt.

### 5.4 XKeen and our files

Install it in a real terminal, because the setup asks questions:

```bash
ssh -t root@192.168.1.1 'opkg update && opkg install curl tar && sh -c "$(curl -fsSL https://raw.githubusercontent.com/jameszeroX/XKeen/main/install.sh)" x -s'
```

Answers: core **1** (Xray) → release **9** → `v26.7.28` → GeoSite **0** → GeoIP **0** → exclude Russian IPs **1** →
auto-update **1**, 05:00 → start on boot **1**.

Copy our files. The router has no SFTP, so `scp` needs `-O`:

```bash
.venv/bin/python clients/gen.py
R=root@192.168.1.1; X=clients/out/keenetic/xkeen
scp -O $X/04_outbounds.json $X/05_routing.json $R:/opt/etc/xray/configs/
ssh $R mkdir -p /opt/etc/xray/routing && scp -O $X/routing/*.json $R:/opt/etc/xray/routing/     # never into configs/
scp -O $X/ip_exclude.lst $R:/opt/etc/xkeen/
scp -O router/vpn-mode.sh $R:/opt/bin/vpn-mode
ssh $R 'chmod +x /opt/bin/vpn-mode && vpn-mode geo && XRAY_LOCATION_ASSET=/opt/etc/xray/dat xray run -test -confdir /opt/etc/xray/configs && vpn-mode on'
```

### 5.5 Choose which devices get the VPN

XKeen only proxies members of the connection policy `xkeen`:

1. **Internet → Connection priorities → Add policy** `xkeen`, and tick **Провайдер 1** in it.
2. **Policy bindings:** drag devices from **Default policy** onto `xkeen`.
3. Whole home: make `xkeen` the default policy of the **Home** segment.

### 5.6 Change the router's exit server

The router uses the **first host in group `eu`** of the inventory. Put the new server there, then:

```bash
.venv/bin/python clients/gen.py
R=root@192.168.1.1; X=clients/out/keenetic/xkeen
ssh $R cp /opt/etc/xray/configs/04_outbounds.json /opt/etc/xray/04_outbounds.prev.json      # backup for rollback
scp -O $X/04_outbounds.json $X/05_routing.json $R:/opt/etc/xray/configs/ && scp -O $X/ip_exclude.lst $R:/opt/etc/xkeen/
ssh $R 'XRAY_LOCATION_ASSET=/opt/etc/xray/dat xray run -test -confdir /opt/etc/xray/configs && xkeen -restart'
ssh $R "netstat -tn | grep -c '<new ip>:443 .*ESTABLISHED'"       # above 0 = home traffic uses it
```

**Rollback** to the previous server (currently Almaty):

```bash
ssh root@192.168.1.1 'cp /opt/etc/xray/04_outbounds.prev.json /opt/etc/xray/configs/04_outbounds.json && xkeen -restart'
```

### 5.7 VPN on/off

```bash
ssh root@192.168.1.1 vpn-mode off       # everything direct: Russian sites work, blocked ones don't
ssh root@192.168.1.1 vpn-mode on        # Russian direct, the rest via VPN
ssh root@192.168.1.1 vpn-mode status
```

- **Without a terminal:** `http://192.168.1.1` → **Internet → Connection priorities → Policy bindings**, then move the devices
  from `xkeen` back to **Default policy**.
- **Last resort:** unplug the USB stick.
- **One tap:** make a Shortcuts app shortcut with **Run Script Over SSH** (host `192.168.1.1`, port `22`, user `root`,
  script `vpn-mode off`), and a second one for `on`.
- **One device always direct:** leave it in **Default policy** (5.5).

### 5.8 Fallback if Reality gets blocked

This only works with our own exit, which runs AmneziaWG (Almaty doesn't).

1. **Internet → Other connections → WireGuard → Load from file:** `clients/out/keenetic/awg-<server>.conf`.
2. Create policy `awg-fallback` containing only that tunnel. Assign no devices to it.
3. Run `ssh root@192.168.1.1 xkeen -pbr codes`. Put the code for `awg-fallback` into `ansible/group_vars/all/main.yml` as
   `xkeen_awg_mark`, run `gen.py`, and copy `04_outbounds.json` again.
4. `ssh root@192.168.1.1 vpn-mode via awg`. To go back: `vpn-mode via reality`.

---

## 6. Daily use

**Send a site direct or via VPN.** Edit `rules/custom.json`:

```json
{ "direct": ["example-bank.com", "203.0.113.0/24"], "proxy": ["some-site.ru"], "block": [] }
```

`example.com` covers it and all subdomains. `full:api.example.com` is one exact host, and `geosite:yandex` is a whole category.
Then run `gen.py`, publish subscriptions (section 2), and copy the router files (5.4).

**Find all of a company's domains:**

```bash
.venv/bin/python rules/expand.py yandex.ru                  # preview
.venv/bin/python rules/expand.py yandex.ru --ai             # also ask Claude (needs an Anthropic API key)
.venv/bin/python rules/expand.py yandex.ru --apply direct   # write to custom.json
```

**Switch server on Mac or iPhone:** tap another server in the **avmax** group.

**VPN off on Mac or iPhone:** turn **On Demand** off first, then the switch. Otherwise it reconnects.

**Abroad:** select `avmax-<server>-abroad`. This needs the Moscow node.

---

## 7. Troubleshooting

| Symptom | Fix |
|---|---|
| Home internet is broken | `ssh root@192.168.1.1 vpn-mode off`, then rollback (5.6) |
| In calls, others stop hearing you every ~5 min | The router's accelerator is back on. Turn it off (5.1, step 5) |
| Claude on this Mac stops after a VPN change | Shadowrocket off, Amnezia on, then investigate |
| Shadowrocket says connected, but nothing loads | Server Xray is newer than 26.7.28. Keep `xray_version: 26.7.28` |
| Instagram fails now and then | The exit routes through Russia (Almaty). Use `hostung-de` |
| New server: `tcp 443 rc=28` in `reach.sh` | Blocked from MGTS. Cancel it; a new IP from the same provider won't help |
| `scp` to the router fails | Add `-O` |
| Shadowrocket Import: "not in the correct format" | Use a Subscribe URL, a QR code, or `open "vless://…"` |
| `curl https://www.gosuslugi.ru` fails | It refuses curl. Check in a browser |
