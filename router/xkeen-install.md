# Keenetic Giga: XKeen 2.0 (Reality on the router) + native AmneziaWG

Two Keenetic policies give the one-tap router toggle:

| Policy in Keenetic UI | What it does | Devices assigned |
|---|---|---|
| `xkeen` (Split) | XKeen transparent proxy: RU direct, everything else via VLESS-Reality | TV, consoles, guests, anything without its own client |
| `Full` | The only internet connection in this policy is the native AmneziaWG tunnel | any device you move here (one tap: Keenetic app or `router/keenetic-policy.sh`) |
| Default | plain ISP | whatever must never touch the VPN |

## 0. Prerequisites
1. KeeneticOS 5.1 or newer (System → Update). AmneziaWG 2.0 parameters need 5.1.
2. USB stick formatted ext4 in the router (Applications → Disks), component "OPKG" installed.
3. Router DNS: enable DNS-over-TLS/HTTPS profiles in Internet → DNS (XKeen requires encrypted DNS on the router).
4. Web UI port 443 moved elsewhere (System → Access): XKeen TProxy needs 443 free.
5. SSH to the router's Entware: `ssh root@192.168.1.1 -p 222` (port 222 = Entware sshd, set during Entware install).

## 1. Entware
Follow https://support.keenetic.com/hero/kn-1012/en/20980-installing-the-entware-repository-on-a-usb-drive.html

## 2. XKeen
```sh
opkg update && opkg upgrade && opkg install curl tar && cd /tmp
sh -c "$(curl -sSL https://raw.githubusercontent.com/jameszeroX/XKeen/main/install.sh)"
```
Choose: latest XKeen 2.x → core **Xray** → version **26.7.28** (option "enter manually") → geosite/geoip: any, we overwrite them below → mode **TProxy** → policy **xkeen**.

Then copy our files (from the Mac):
```sh
scp -P 222 clients/out/keenetic/xkeen/04_outbounds.json root@192.168.1.1:/opt/etc/xray/configs/
scp -P 222 clients/out/keenetic/xkeen/05_routing_split.json clients/out/keenetic/xkeen/05_routing_full.json root@192.168.1.1:/opt/etc/xray/configs/
scp -P 222 router/vpn-mode.sh root@192.168.1.1:/opt/bin/vpn-mode
ssh -p 222 root@192.168.1.1 'chmod +x /opt/bin/vpn-mode && vpn-mode split'
```
Russia-aware geo files (same ones the server and Happ use):
```sh
ssh -p 222 root@192.168.1.1 'cd /opt/etc/xray/dat && curl -fsSL -o geoip.dat https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geoip.dat && curl -fsSL -o geosite.dat https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geosite.dat && xkeen -restart'
```
In the Keenetic UI create policy **xkeen** (Internet → Policies) with the ISP connection only, and move the client-less devices into it. XKeen intercepts their traffic on 80/443 (extend the port list in `/opt/etc/xkeen/xkeen.json` if needed).

## 3. Native AmneziaWG (policy "Full")
Internet → Other connections → WireGuard → **Load from file** → `clients/out/keenetic/awg-<server>.conf` (the generated file already carries Jc/Jmin/Jmax/S1/S2/H1–H4/I1). Tick "Use for Internet access". Create policy **Full** with only this connection.

## 4. One-tap switching
- Per device: `router/keenetic-policy.sh --list`, then `router/keenetic-policy.sh <name> full` / `split`. Wrap in a Shortcut (see `router/shortcuts.md`).
- Whole router (XKeen rules): `ssh -p 222 root@192.168.1.1 vpn-mode full` / `split`.

## 5. Checks
From a device inside policy `xkeen` with no VPN app: `tests/leak-check.sh` must show the home ISP IP on 2ip.ru and the EU IP on ifconfig.co. Move it to `Full`: both must show the EU IP.

Throughput ceiling on MT7621 Gigas (KN-1010/1011) is about 250–300 Mbps through Xray; the AWG policy is kernel-path and faster.
