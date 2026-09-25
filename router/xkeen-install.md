# Keenetic Giga: whole-home split VPN with XKeen 2.0 (no apps on home devices)

Every device on home Wi-Fi is proxied by the router: Russian destinations stay direct, everything else goes through the
EU node over VLESS-Reality. One switch for the whole house: `vpn-mode on|off`.

## 0. Prerequisites (this router: Keenetic Giga KN-1012, ARM64, KeeneticOS 5.1.6)
1. KeeneticOS 5.1+ — already on 5.1.6.
2. Components (System → Components): **OPKG** ("Open Package support"). Saving reboots the router.
3. USB stick, prepared on the Mac (erases it; refuses non-USB disks):
   ```sh
   router/make-usb.sh            # find the stick, e.g. disk4
   router/make-usb.sh disk4      # ext4 partition "OPKG" with install/EN_aarch64-installer.tar.gz
   ```
4. Plug the stick into the router → Applications → OPKG → Drive: the `OPKG` stick → Save. Watch Diagnostics → System log
   until Entware reports it is installed.
5. Router DNS: enable DNS-over-TLS/HTTPS profiles (Internet → DNS). XKeen requires encrypted DNS on the router.
6. Move the web admin off port 443 (System → Access): XKeen TProxy needs 443 free.
7. Entware SSH is on port 222, user `root`, default password `keenetic`. Once, from the Mac, change it and add the Mac's key
   (you type the password; after this every login is key-based):
   ```sh
   ssh -p 222 root@192.168.1.1 'passwd && mkdir -p /opt/root/.ssh && cat >> /opt/root/.ssh/authorized_keys' < ~/.ssh/id_ed25519.pub
   ```
8. **IPv6**: MGTS gives LAN devices native IPv6 (seen 2026-09-19), which would let foreign sites with IPv6 bypass the tunnel.
   Turn IPv6 off on the ISP connection (Internet → connection → IPv6) or use XKeen's IPv6 handling; from a LAN device
   `curl -6 https://ifconfig.co` must fail.

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
KN-1012 (MT7981, 512 MB) has headroom well above the 250–300 Mbps ceiling of the older MT7621 Gigas.
