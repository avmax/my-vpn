#!/usr/bin/env python3
"""Generate every client artefact from inventory + group_vars + secrets into clients/out/ (gitignored).

Per device (mac, iphone, keenetic):
  <dev>/reality-<server>.txt/.png      VLESS Reality URI + QR (home UUID)
  <dev>/xhttp-<server>.txt/.png        VLESS over XHTTP+TLS URI + QR (home UUID, secondary transport)
  <dev>/reality-abroad-<server>.txt    same with the abroad UUID (only for abroad: true devices)
  <dev>/awg-<server>.conf/.png         AmneziaWG config for the EU node (Full mode only)
  <dev>/awg-msk.conf                   direct AmneziaWG profile to the Moscow node (if msk exists)
  <dev>/wg-control-<server>.conf       plain WireGuard control profile (Phase 1 only, test_mode)
happ/routing-{split,full}.json + .deeplink.txt + .png   Happ routing profiles (one tap each)
sub/<dev>                              subscription body served by Caddy at https://<domain>/s/<token>/<dev>
keenetic/xkeen/04_outbounds.json, 05_routing_split.json, 05_routing_full.json
test/<server>/{reality,reality-chrome,xhttp}.json        local Xray client configs for tests/matrix.sh
"""
import base64
import json
import sys
import time
from pathlib import Path
from urllib.parse import quote

import qrcode
import yaml

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "clients" / "out"
GEOIP_URL = "https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geoip.dat"
GEOSITE_URL = "https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geosite.dat"

RU_DOMAINS = ["geosite:private", "geosite:category-ru", "geosite:ru-available-only-inside",
              "domain:ru", "domain:su", "domain:xn--p1ai"]
RU_IPS = ["geoip:private", "geoip:ru"]


def load_yaml(p):
    return yaml.safe_load(Path(p).read_text())


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def qr(path, data):
    img = qrcode.make(data, error_correction=qrcode.constants.ERROR_CORRECT_L, border=2)
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)


def inventory_hosts(inv):
    """Return ({name: ip} for exit nodes, msk ip or None)."""
    ch = inv["all"]["children"]
    exits, msk = {}, None
    for g in ("eu", "standby", "eu_candidates"):
        for name, h in (ch.get(g, {}).get("hosts") or {}).items():
            exits.setdefault(name, h["ansible_host"])
    for name, h in (ch.get("msk", {}).get("hosts") or {}).items():
        msk = h["ansible_host"]
    return exits, msk


def reality_uri(uuid, ip, v, sec, sid, label):
    q = (f"encryption=none&flow=xtls-rprx-vision&security=reality&sni={v['vpn_domain']}"
         f"&fp=firefox&pbk={sec['reality_public_key']}&sid={sid}&spx=%2F&type=tcp")
    return f"vless://{uuid}@{ip}:{v['xray_reality_port']}?{q}#{quote(label)}"


def xhttp_uri(uuid, ip, v, sec, label):
    q = (f"encryption=none&security=tls&sni={v['vpn_domain']}&fp=firefox&alpn=h2%2Chttp%2F1.1"
         f"&type=xhttp&host={v['vpn_domain']}&path=%2F{sec['xhttp_path']}&mode=auto")
    return f"vless://{uuid}@{ip}:{v['xray_reality_port']}?{q}#{quote(label)}"


def awg_conf(dev, dsec, server_pub, server_ip, port, params, mtu, plain=False):
    lines = ["[Interface]",
             f"PrivateKey = {dsec['private_key']}",
             f"Address = {dev}/32",
             "DNS = 1.1.1.1, 8.8.8.8",
             f"MTU = {mtu}"]
    if plain:
        lines += ["Jc = 0", "Jmin = 0", "Jmax = 0", "S1 = 0", "S2 = 0", "H1 = 1", "H2 = 2", "H3 = 3", "H4 = 4"]
    else:
        lines += [f"Jc = {params['jc']}", f"Jmin = {params['jmin']}", f"Jmax = {params['jmax']}",
                  f"S1 = {params['s1']}", f"S2 = {params['s2']}",
                  f"H1 = {params['h1']}", f"H2 = {params['h2']}", f"H3 = {params['h3']}", f"H4 = {params['h4']}",
                  f"I1 = {params['i1']}"]
    lines += ["", "[Peer]",
              f"PublicKey = {server_pub}",
              f"PresharedKey = {dsec['psk']}",
              "AllowedIPs = 0.0.0.0/0",
              f"Endpoint = {server_ip}:{port}",
              "PersistentKeepalive = 25", ""]
    return "\n".join(lines)


def happ_profile(name, direct_sites, direct_ips):
    return {
        "Name": name,
        "GlobalProxy": "true",
        "UseChunkFiles": "false",
        "RemoteDns": "8.8.8.8",
        "DomesticDns": "77.88.8.8",
        "RemoteDNSType": "DoH",
        "RemoteDNSDomain": "https://8.8.8.8/dns-query",
        "RemoteDNSIP": "8.8.8.8",
        "DomesticDNSType": "DoH",
        "DomesticDNSDomain": "https://77.88.8.8/dns-query",
        "DomesticDNSIP": "77.88.8.8",
        "Geoipurl": GEOIP_URL,
        "Geositeurl": GEOSITE_URL,
        "LastUpdated": str(int(time.time())),
        "DnsHosts": {},
        "RouteOrder": "block-proxy-direct",
        "DirectSites": direct_sites,
        "DirectIp": direct_ips,
        "ProxySites": [],
        "ProxyIp": [],
        "BlockSites": [],
        "BlockIp": [],
        "DomainStrategy": "IPIfNonMatch",
        "FakeDNS": "false",
    }


def happ_deeplink(profile):
    b = base64.b64encode(json.dumps(profile, ensure_ascii=False, separators=(",", ":")).encode()).decode()
    return f"happ://routing/onadd/{b}"


def xray_client(ip, uuid, v, sec, transport, fp, socks_port):
    if transport == "reality":
        stream = {"network": "raw", "security": "reality",
                  "realitySettings": {"serverName": v["vpn_domain"], "fingerprint": fp,
                                      "publicKey": sec["reality_public_key"],
                                      "shortId": sec["device_secrets"]["mac"]["reality_short_id"], "spiderX": "/"}}
        user = {"id": uuid, "encryption": "none", "flow": "xtls-rprx-vision"}
    else:
        stream = {"network": "xhttp", "security": "tls",
                  "tlsSettings": {"serverName": v["vpn_domain"], "fingerprint": fp, "alpn": ["h2", "http/1.1"]},
                  "xhttpSettings": {"path": "/" + sec["xhttp_path"], "host": v["vpn_domain"], "mode": "auto"}}
        user = {"id": uuid, "encryption": "none"}
    return {
        "log": {"loglevel": "warning"},
        "inbounds": [{"tag": "socks", "listen": "127.0.0.1", "port": socks_port, "protocol": "socks",
                      "settings": {"udp": True}}],
        "outbounds": [{"tag": "proxy", "protocol": "vless",
                       "settings": {"vnext": [{"address": ip, "port": v["xray_reality_port"], "users": [user]}]},
                       "streamSettings": stream}],
    }


def xkeen_outbounds(ip, uuid, sid, v, sec):
    return {"outbounds": [
        {"tag": "vless-reality", "protocol": "vless",
         "settings": {"vnext": [{"address": ip, "port": v["xray_reality_port"],
                                 "users": [{"id": uuid, "encryption": "none", "flow": "xtls-rprx-vision"}]}]},
         "streamSettings": {"network": "raw", "security": "reality",
                            "realitySettings": {"serverName": v["vpn_domain"], "fingerprint": "firefox",
                                                "publicKey": sec["reality_public_key"], "shortId": sid,
                                                "spiderX": "/"}}},
        {"tag": "direct", "protocol": "freedom", "settings": {"domainStrategy": "UseIPv4"}},
        {"tag": "block", "protocol": "blackhole"},
    ]}


def xkeen_routing(split):
    rules = []
    if split:
        rules.append({"domain": RU_DOMAINS, "outboundTag": "direct"})
        rules.append({"ip": RU_IPS, "outboundTag": "direct"})
    else:
        rules.append({"domain": ["geosite:private"], "outboundTag": "direct"})
        rules.append({"ip": ["geoip:private"], "outboundTag": "direct"})
    rules.append({"protocol": ["bittorrent"], "outboundTag": "direct"})
    rules.append({"network": "tcp,udp", "outboundTag": "vless-reality"})
    return {"routing": {"domainStrategy": "IPIfNonMatch", "rules": rules}}


def main():
    v = load_yaml(ROOT / "ansible/group_vars/all/main.yml")
    sec = load_yaml(ROOT / "secrets/secrets.yml")
    inv_path = ROOT / "inventory/hosts.yml"
    if not inv_path.exists():
        print("inventory/hosts.yml missing: copy inventory/hosts.example.yml and fill in server IPs", file=sys.stderr)
        return 1
    exits, msk_ip = inventory_hosts(load_yaml(inv_path))
    if not exits:
        print("no exit nodes in inventory (eu / standby / eu_candidates)", file=sys.stderr)
        return 1
    if v["vpn_domain"].endswith("example.com"):
        print("set vpn_domain in ansible/group_vars/all/main.yml first", file=sys.stderr)
        return 1

    devices = {d["name"]: d for d in v["vpn_devices"]}
    port = v["xray_reality_port"]

    # Happ routing profiles (device independent)
    for mode, ds, di in (("split", RU_DOMAINS, RU_IPS), ("full", ["geosite:private"], ["geoip:private"])):
        prof = happ_profile(f"avmax {mode}", ds, di)
        link = happ_deeplink(prof)
        write(OUT / "happ" / f"routing-{mode}.json", json.dumps(prof, indent=2, ensure_ascii=False) + "\n")
        write(OUT / "happ" / f"routing-{mode}.deeplink.txt", link + "\n")
        qr(OUT / "happ" / f"routing-{mode}.png", link)

    for name, d in devices.items():
        ds = sec["device_secrets"][name]
        sub_lines = []
        for sname, ip in exits.items():
            r = reality_uri(ds["uuid_home"], ip, v, sec, ds["reality_short_id"], f"avmax {sname} reality")
            x = xhttp_uri(ds["uuid_home"], ip, v, sec, f"avmax {sname} xhttp")
            write(OUT / name / f"reality-{sname}.txt", r + "\n")
            qr(OUT / name / f"reality-{sname}.png", r)
            write(OUT / name / f"xhttp-{sname}.txt", x + "\n")
            qr(OUT / name / f"xhttp-{sname}.png", x)
            sub_lines += [r, x]
            if d.get("abroad"):
                a = reality_uri(ds["uuid_abroad"], ip, v, sec, ds["reality_short_id"], f"avmax {sname} ABROAD")
                write(OUT / name / f"reality-abroad-{sname}.txt", a + "\n")
                qr(OUT / name / f"reality-abroad-{sname}.png", a)
                sub_lines.append(a)
            conf = awg_conf(d["awg_ip"], ds["awg_eu"], sec["awg_eu"]["public_key"], ip, v["awg_port"],
                            sec["awg_eu"], v["awg_mtu"])
            write(OUT / name / f"awg-{sname}.conf", conf)
            qr(OUT / name / f"awg-{sname}.png", conf)
            if v.get("test_mode"):
                write(OUT / name / f"wg-control-{sname}.conf",
                      awg_conf(d["awg_ip"].replace("10.8.", "10.10."), ds["awg_eu"], sec["awg_control"]["public_key"],
                               ip, v["awg_control_port"], sec["awg_eu"], v["awg_mtu"], plain=True))
        if msk_ip and d.get("msk_awg_ip"):
            write(OUT / name / "awg-msk.conf",
                  awg_conf(d["msk_awg_ip"], ds["awg_msk"], sec["awg_msk"]["public_key"], msk_ip, v["awg_port"],
                           sec["awg_msk"], v["awg_mtu"]))
        write(OUT / "sub" / name, base64.b64encode("\n".join(sub_lines).encode()).decode() + "\n")

    # Keenetic / XKeen files use the primary exit (group eu if present, else first candidate)
    primary_name, primary_ip = next(iter(exits.items()))
    kd = sec["device_secrets"]["keenetic"]
    write(OUT / "keenetic/xkeen/04_outbounds.json",
          json.dumps(xkeen_outbounds(primary_ip, kd["uuid_home"], kd["reality_short_id"], v, sec), indent=2) + "\n")
    write(OUT / "keenetic/xkeen/05_routing_split.json", json.dumps(xkeen_routing(True), indent=2) + "\n")
    write(OUT / "keenetic/xkeen/05_routing_full.json", json.dumps(xkeen_routing(False), indent=2) + "\n")

    # Local Xray client configs for the Phase 1 matrix (mac's home UUID)
    md = sec["device_secrets"]["mac"]
    for sname, ip in exits.items():
        write(OUT / "test" / sname / "reality.json",
              json.dumps(xray_client(ip, md["uuid_home"], v, sec, "reality", "firefox", 1080), indent=2) + "\n")
        write(OUT / "test" / sname / "reality-chrome.json",
              json.dumps(xray_client(ip, md["uuid_home"], v, sec, "reality", "chrome", 1082), indent=2) + "\n")
        write(OUT / "test" / sname / "xhttp.json",
              json.dumps(xray_client(ip, md["uuid_home"], v, sec, "xhttp", "firefox", 1081), indent=2) + "\n")

    sub_url = f"https://{v['vpn_domain']}/s/{sec['sub_token']}/"
    write(OUT / "SUBSCRIPTION-URLS.txt", "".join(f"{n}: {sub_url}{n}\n" for n in devices))
    print(f"wrote {OUT} for exits {list(exits)} msk={msk_ip}; subscription base {sub_url}<device>")
    return 0


if __name__ == "__main__":
    sys.exit(main())
