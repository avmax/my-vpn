# Keenetic Giga: whole-home split VPN with XKeen 2.0 (no apps on home devices)

Every device on home Wi-Fi is proxied by the router: Russian destinations stay direct, everything else goes through the
EU node over VLESS-Reality. One switch for the whole house: `vpn-mode on|off`.

## 0. Prerequisites (avmax, in the Keenetic UI)
1. KeeneticOS 5.1 or newer (System → Update). AmneziaWG 2.0 parameters (fallback path) need 5.1.
2. USB stick formatted ext4 in the router, component **OPKG** installed → Entware:
   https://support.keenetic.com/hero/kn-1012/en/20980-installing-the-entware-repository-on-a-usb-drive.html
3. Router DNS: enable DNS-over-TLS/HTTPS profiles (Internet → DNS). XKeen requires encrypted DNS on the router.
4. Move the web UI off port 443 (System → Access): XKeen TProxy needs 443 free.
5. Entware SSH: `ssh root@192.168.1.1 -p 222`.
6. **IPv6**: the home ISP (MGTS) hands out IPv6 to LAN clients (seen 2026-09-19). Any foreign site with an AAAA record would then bypass the
   tunnel over IPv6. Disable IPv6 on the ISP connection in the Keenetic UI (Internet → connection → IPv6 off) or use XKeen's IPv6 handling;
   verify with `curl -6 https://ifconfig.co` from a LAN device: it must fail.

## 1. XKeen 2.0 (jameszeroX fork)
```sh
opkg update && opkg upgrade && opkg install curl tar && cd /tmp
sh -c "$(curl -sSL https://raw.githubusercontent.com/jameszeroX/XKeen/main/install.sh)"
```
Installer answers: latest XKeen 2.x → core **Xray** → version **26.7.28** (option "enter manually") → any geosite/geoip (overwritten
below) → mode **TProxy** → **no policy** ("маршрутизация без политики для всех клиентов", i.e. all router clients).

## 2. Our configs
From the Mac (after `clients/gen.py`):
```sh
R=root@192.168.1.1; P=222
scp -P $P clients/out/keenetic/xkeen/04_outbounds.json clients/out/keenetic/xkeen/05_routing*.json $R:/opt/etc/xray/configs/
scp -P $P clients/out/keenetic/xkeen/ip_exclude.lst $R:/opt/etc/xkeen/ip_exclude.lst      # LAN IPs / CIDRs that must stay direct
scp -P $P router/vpn-mode.sh $R:/opt/bin/vpn-mode
ssh -p $P $R 'chmod +x /opt/bin/vpn-mode; cd /opt/etc/xray/dat && \
  curl -fsSL -o geoip.dat https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geoip.dat && \
  curl -fsSL -o geosite.dat https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geosite.dat && vpn-mode on'
```
How "Russian = direct" is decided on the router (two layers): XKeen's ipsets keep Russian subnets (`geo_exclude`, refreshed with
`xkeen -ug`) and your `ip_exclude.lst` entries out of the proxy chain entirely; Xray's `05_routing.json` then applies your
`rules/custom.json` overrides, `geosite:category-ru`, `.ru/.su/.рф` and `geoip:ru` for domains. Everything else → `vless-reality`.

## 3. Switch
- `ssh -p 222 root@192.168.1.1 vpn-mode off` → everything direct; `vpn-mode on` → split. `vpn-mode status`.
- One tap from the phone/Mac: `router/shortcuts.md`. Browser button: install an XKeen UI panel (links in the XKeen README).
- Exclude a device permanently: add its LAN IP to `ip_exclude.lst` (or assign it a Keenetic policy without XKeen).

## 4. Fallback if Reality stops working: native AmneziaWG through XKeen
1. Internet → Other connections → WireGuard → Load from file → `clients/out/keenetic/awg-<server>.conf` (AWG 2.0 params included).
2. Create policy `awg-fallback` (Internet → Policies) whose only connection is that tunnel. Do not assign devices to it.
3. `ssh -p 222 root@192.168.1.1 'xkeen -pbr codes'` → note the number for `awg-fallback`; put it into
   `ansible/group_vars/all/main.yml` as `xkeen_awg_mark`, run `clients/gen.py`, copy `04_outbounds.json` again.
4. `vpn-mode via awg` (back: `vpn-mode via reality`). Same split rules, foreign traffic now leaves through the AWG tunnel.

## 5. Checks
From a home device with no VPN app: `tests/leak-check.sh` → ip.beget.ru shows the home ISP, ifconfig.co the EU IP; `vpn-mode off` →
both show the home ISP. YouTube/ChatGPT/claude.ai load with `on`; Yandex/Gosuslugi/Sber see the home IP in both states.
MT7621 Gigas (KN-1010/1011) top out around 250–300 Mbps through Xray.
