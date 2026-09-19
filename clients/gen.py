#!/usr/bin/env python3
"""Generate every client artefact from inventory + group_vars + secrets into clients/out/ (gitignored).

Per device (mac, iphone, keenetic):
  <dev>/reality-<server>.txt/.png      VLESS Reality URI + QR (home UUID)
  <dev>/xhttp-<server>.txt/.png        VLESS over XHTTP+TLS URI + QR (home UUID, secondary transport)
  <dev>/reality-abroad-<server>.txt    same with the abroad UUID (only for abroad: true devices)
  <dev>/awg-<server>.conf/.png         AmneziaWG config for the EU node (Full mode only)
  <dev>/awg-msk.conf                   direct AmneziaWG profile to the Moscow node (if msk exists)
  <dev>/wg-control-<server>.conf       plain WireGuard control profile (Phase 1 only, test_mode)
happ/routing-split.json + .deeplink.txt + .png            Happ routing profile (custom overrides + geo)\nsub/shadowrocket.conf, sub/ru-direct.list, shadowrocket-import-url.txt   Shadowrocket rules (served by Caddy)
sub/<dev>                              subscription body served by Caddy at https://<domain>/s/<token>/<dev>
keenetic/xkeen/04_outbounds.json, 05_routing.json (+ _via_reality/_via_awg), ip_exclude.lst
test/<server>/{reality,reality-chrome,xhttp}.json        local Xray client configs for tests/matrix.sh
"""
import base64
import json
import re
import sys
import time
from pathlib import Path
from urllib.parse import quote

import qrcode
import yaml

import urllib.request

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "clients" / "out"
GEOIP_URL = "https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geoip.dat"
GEOSITE_URL = "https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geosite.dat"

RU_DOMAINS = ["geosite:private", "geosite:category-ru", "geosite:ru-available-only-inside",
              "domain:ru", "domain:su", "domain:xn--p1ai"]
RU_IPS = ["geoip:private", "geoip:ru"]
RULES = ROOT / "rules" / "custom.json"
V2FLY_RAW = "https://raw.githubusercontent.com/v2fly/domain-list-community/master/data/"
CACHE = ROOT / "rules" / ".cache"


def load_rules():
    r = json.loads(RULES.read_text()) if RULES.exists() else {}
    return {k: [x for x in r.get(k, []) if not x.startswith("_")] for k in ("direct", "proxy", "block")}


def is_cidr(x):
    return bool(re.match(r"^\d+\.\d+\.\d+\.\d+(/\d+)?$", x))


def xray_domain(x):
    """custom.json entry -> xray domain rule ('example.com' means domain+subdomains)."""
    return x if x.startswith(("geosite:", "full:", "domain:", "regexp:", "keyword:")) else f"domain:{x}"


def split_rules(entries):
    ips = [e for e in entries if is_cidr(e)]
    doms = [xray_domain(e) for e in entries if not is_cidr(e)]
    return doms, ips


def v2fly_list(name, seen=None):
    """Resolve a v2fly data file (with include:) into plain domain suffixes; cached in rules/.cache."""
    seen = seen if seen is not None else set()
    if name in seen:
        return []
    seen.add(name)
    CACHE.mkdir(parents=True, exist_ok=True)
    f = CACHE / name
    if not f.exists():
        with urllib.request.urlopen(V2FLY_RAW + name, timeout=30) as r:
            f.write_bytes(r.read())
    out = []
    for line in f.read_text().splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        if line.startswith("include:"):
            out += v2fly_list(line.split(":", 1)[1].strip(), seen)
        elif line.startswith("full:"):
            out.append(line.split(":", 1)[1].split("@")[0].strip())
        elif line.startswith(("regexp:", "keyword:")):
            continue
        else:
            out.append(line.split("@")[0].strip())
    return out


def shadowrocket_conf(list_url):
    rules = load_rules()
    lines = ["[General]",
             "bypass-system = true",
             "skip-proxy = 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12, 100.64.0.0/10, localhost, *.local, captive.apple.com",
             "tun-excluded-routes = 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.0.0.0/24, 192.0.2.0/24, 192.88.99.0/24, 192.168.0.0/16, 198.18.0.0/15, 198.51.100.0/24, 203.0.113.0/24, 224.0.0.0/4, 255.255.255.255/32",
             "dns-server = system",
             "ipv6 = false",
             "",
             "[Rule]"]
    def sr(entry, action):
        if is_cidr(entry):
            return f"IP-CIDR,{entry if '/' in entry else entry + '/32'},{action},no-resolve"
        if entry.startswith("full:"):
            return f"DOMAIN,{entry[5:]},{action}"
        if entry.startswith("domain:"):
            return f"DOMAIN-SUFFIX,{entry[7:]},{action}"
        if entry.startswith("keyword:"):
            return f"DOMAIN-KEYWORD,{entry[8:]},{action}"
        if entry.startswith("geosite:"):
            return f"# geosite:{entry[8:]} is expanded into ru-direct.list when it is a v2fly category"
        return f"DOMAIN-SUFFIX,{entry},{action}"
    lines += [sr(e, "REJECT") for e in rules["block"]]
    lines += [sr(e, "DIRECT") for e in rules["direct"]]
    lines += [sr(e, "PROXY") for e in rules["proxy"]]
    lines += [f"RULE-SET,{list_url},DIRECT",
              "DOMAIN-SUFFIX,ru,DIRECT", "DOMAIN-SUFFIX,su,DIRECT", "DOMAIN-SUFFIX,xn--p1ai,DIRECT",
              "GEOIP,RU,DIRECT,no-resolve",
              "FINAL,PROXY",
              "", "[Host]", "localhost = 127.0.0.1", ""]
    return "\n".join(lines)


def ru_direct_list():
    """Surge/Shadowrocket rule-set: Russian services from v2fly category-ru + custom geosite:* direct entries."""
    rules = load_rules()
    names = ["category-ru"] + [e[8:] for e in rules["direct"] if e.startswith("geosite:")]
    doms = []
    for n in names:
        try:
            doms += v2fly_list(n)
        except Exception as ex:  # offline: keep going with what we have
            print(f"warning: could not fetch v2fly list {n}: {ex}", file=sys.stderr)
    doms = sorted(set(d for d in doms if d and "/" not in d))
    return "\n".join(f"DOMAIN-SUFFIX,{d}" for d in doms) + "\n"


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
    awg = []
    if v.get("xkeen_awg_mark"):
        awg = [{"tag": "awg-out", "protocol": "freedom", "settings": {"domainStrategy": "UseIPv4"},
                "streamSettings": {"sockopt": {"mark": int(v["xkeen_awg_mark"])}}}]
    return {"outbounds": awg + [
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


def xkeen_routing(proxy_tag="vless-reality"):
    """custom overrides -> automatic geo -> everything else via proxy_tag."""
    r = load_rules()
    b_dom, b_ip = split_rules(r["block"]); d_dom, d_ip = split_rules(r["direct"]); p_dom, p_ip = split_rules(r["proxy"])
    rules = []
    if b_dom: rules.append({"domain": b_dom, "outboundTag": "block"})
    if b_ip: rules.append({"ip": b_ip, "outboundTag": "block"})
    if d_dom: rules.append({"domain": d_dom, "outboundTag": "direct"})
    if d_ip: rules.append({"ip": d_ip, "outboundTag": "direct"})
    if p_dom: rules.append({"domain": p_dom, "outboundTag": proxy_tag})
    if p_ip: rules.append({"ip": p_ip, "outboundTag": proxy_tag})
    rules.append({"domain": RU_DOMAINS, "outboundTag": "direct"})
    rules.append({"ip": RU_IPS, "outboundTag": "direct"})
    rules.append({"protocol": ["bittorrent"], "outboundTag": "direct"})
    rules.append({"network": "tcp,udp", "outboundTag": proxy_tag})
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

    # Happ routing profile (split only; custom overrides first, then geo)
    rules = load_rules()
    d_dom, d_ip = split_rules(rules["direct"]); p_dom, p_ip = split_rules(rules["proxy"]); b_dom, b_ip = split_rules(rules["block"])
    prof = happ_profile("avmax split", d_dom + RU_DOMAINS, d_ip + RU_IPS)
    prof.update({"ProxySites": p_dom, "ProxyIp": p_ip, "BlockSites": b_dom, "BlockIp": b_ip})
    link = happ_deeplink(prof)
    write(OUT / "happ" / "routing-split.json", json.dumps(prof, indent=2, ensure_ascii=False) + "\n")
    write(OUT / "happ" / "routing-split.deeplink.txt", link + "\n")
    qr(OUT / "happ" / "routing-split.png", link)

    # Shadowrocket: rules file + RU rule-set, both served by Caddy next to the subscriptions
    sub_base = f"https://{v['vpn_domain']}/s/{sec['sub_token']}/"
    write(OUT / "sub" / "ru-direct.list", ru_direct_list())
    write(OUT / "sub" / "shadowrocket.conf", shadowrocket_conf(sub_base + "ru-direct.list"))
    write(OUT / "shadowrocket-import-url.txt",
          f"shadowrocket://config/add/{sub_base}shadowrocket.conf\n")

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
    write(OUT / "keenetic/xkeen/05_routing.json", json.dumps(xkeen_routing(), indent=2) + "\n")
    write(OUT / "keenetic/xkeen/05_routing_via_reality.json", json.dumps(xkeen_routing(), indent=2) + "\n")
    write(OUT / "keenetic/xkeen/05_routing_via_awg.json", json.dumps(xkeen_routing("awg-out"), indent=2) + "\n")
    write(OUT / "keenetic/xkeen/ip_exclude.lst", "\n".join(split_rules(load_rules()["direct"])[1]) + "\n")

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
