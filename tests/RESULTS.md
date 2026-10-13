# Test results

Numbers from avmax's real networks. Every provider/protocol decision points at a row here.

## Phase 0: recon (tests/recon.sh)

| date | network | ISP / ASN | plain DNS to 8.8.8.8 | UDP (STUN) | notes |
|---|---|---|---|---|---|
| 2026-09-19 20:46 | home (Wi-Fi Keenetic-0650) | MGTS, AS25513, 46.138.11.182 (+ native IPv6) | 8.8.8.8 and 1.1.1.1 answer, but return NO ANSWER for rutracker.org (blocked domains are filtered at the resolver path); DoH to Google/Cloudflare works | STUN: Google FAIL, Cloudflare OK, Nextcloud OK (UDP partly filtered) | first run polluted by a VPN app for 2-3 min; this is the clean re-run |
| 2026-09-25 19:58 | mobile (iPhone hotspot, Tinkoff) | T-Bank AS205638, 212.233.85.157 | no interception: rutracker.org resolves via 8.8.8.8 and 1.1.1.1; DoH to Google/Cloudflare works | STUN: Google FAIL, Cloudflare OK, Nextcloud OK | high latency (130-1000 ms); no domestic baseline in this run |

Hoster reachability from home (MGTS), 30 MB samples, 2026-09-19 20:46:

| provider | location | role | ping ms | tcp443 | Mbps (30 MB) | note |
|---|---|---|---|---|---|---|
| hetzner | helsinki | control | 115.126 | ok | 0.0 | got 0.0 MB, http 000 |
| hetzner | nuremberg | control | 49.330 | ok | 0.0 | got 0.0 MB, http 000 |
| vultr | amsterdam | control | 51.098 | ok | 0.0 | got 0.0 MB, http 206 |
| vultr | frankfurt | control | 58.668 | ok | 0.0 | got 0.0 MB, http 000 |
| vultr | stockholm | control | 57.455 | ok | 0.0 | got 0.0 MB, http 000 |
| linode | frankfurt | control | 52.215 | ok | 0.0 | STALLED at <32 KB (freeze signature) |
| ovh | gravelines | control | 60.145 | ok | 118.6 | got 30.0 MB, http 206 |
| scaleway | paris | control | 61.510 | no | 0.0 | got 0.0 MB, http 206 |
| hostkey | helsinki | candidate | timeout | ok | 92.7 | got 30.0 MB, http 206 |
| hostkey | amsterdam | candidate | timeout | ok | 124.6 | got 30.0 MB, http 206 |
| hostkey | germany | candidate | timeout | ok | 139.4 | got 30.0 MB, http 206 |
| vdsina | amsterdam | candidate | 47.118 | ok | - | ping only |
| upcloud | helsinki | candidate | 180.661 | ok | - | ping only |
| melbicom | riga | candidate | timeout | ok | - | ping only |

Reading: Hetzner (HEL/NBG), Vultr (AMS/FRA/STO), Linode FRA and Scaleway PAR are dead or frozen from MGTS, exactly the TSPU AS-list signature. OVH Gravelines and HostKey FI/NL/DE download at full speed. VDSina/UpCloud/Melbicom: TCP 443 reachable, no public test file yet.

Hoster reachability over Tinkoff Mobile, 30 MB samples, 2026-09-25 19:58:

| provider | location | role | ping ms | tcp443 | Mbps (30 MB) | note |
|---|---|---|---|---|---|---|
| hetzner | helsinki | control | 188.000 | ok | 0.0 | got 0.0 MB, http 000 |
| hetzner | nuremberg | control | 88.270 | ok | 0.0 | got 0.0 MB, http 000 |
| vultr | amsterdam | control | 1023.813 | ok | 0.0 | got 0.0 MB, http 000 |
| vultr | frankfurt | control | 262.551 | ok | 0.0 | got 0.0 MB, http 000 |
| vultr | stockholm | control | 343.813 | ok | 0.0 | got 0.0 MB, http 000 |
| linode | frankfurt | control | 130.144 | ok | 0.0 | got 0.0 MB, http 000 |
| ovh | gravelines | control | 264.178 | ok | 0.8 | got 3.7 MB, http 206 |
| scaleway | paris | control | 158.617 | no | 0.0 | STALLED at <32 KB (freeze signature) |
| hostkey | helsinki | candidate | timeout | ok | 0.6 | got 2.9 MB, http 206 |
| hostkey | amsterdam | candidate | timeout | ok | 0.1 | got 0.6 MB, http 206 |
| hostkey | germany | candidate | timeout | ok | 0.9 | got 4.4 MB, http 206 |
| vdsina | amsterdam | candidate | 141.978 | ok | - | ping only |
| upcloud | helsinki | candidate | 128.870 | ok | - | ping only |
| melbicom | riga | candidate | 331.893 | ok | - | ping only |

Reading: the TSPU-listed controls are dead here too. HostKey and OVH trickle at 0.1-0.9 Mbps instead of freezing, but latency to every host was 130-1000 ms, so this run cannot tell a weak hotspot link from foreign-traffic throttling. A domestic baseline (Yandex mirror) was added to endpoints.txt after this run; the Phase 1 mobile matrix will include it.

## Phase 1: service availability from candidates (tests/availability.sh)

**kz-test** — Timeweb Almaty, AS9123, 92.118.115.34 (shared production box, test only), 2026-09-25, over IPv4:

| check | result | meaning |
|---|---|---|
| geolocation | ipinfo KZ, ip-api KZ (flags proxy + hosting), Cloudflare loc=KZ | not seen as Russia |
| chatgpt.com / claude.ai | 403 `cf-mitigated: challenge` for curl | Cloudflare challenge, not a geo block; verify in a browser through the tunnel |
| api.anthropic.com | 401 | reachable |
| Netflix licensed title 70143836 | 200 at /kz/title/… | full KZ catalog, not originals-only |
| YouTube Premium region | KZ over IPv4, **RU over IPv6** | exit must stay IPv4-only (it is: freedom UseIPv4) |
| Gemini, Google search, Drive | 200 / 200 / 302 | fine, no captcha |
| **browser through the tunnel** (Shadowrocket, Proxy mode, second Mac, 2026-09-26) | chatgpt.com and claude.ai work, log in and chat; Cloudflare sees KZ | the curl 403 was only the bot challenge |
| **Instagram** | fails intermittently: www/i.instagram.com time out from the server itself; with a pinned reachable Meta IP it returns 200 in 0.9 s | some Meta prefixes (e.g. 157.240.205.0/24, 31.13.72.0/24) are unreachable |

**Why, and the verdict:** the server's path to Europe runs Almaty → Timeweb **Moscow** (94.228.119.193, +48 ms) → Timeweb Amsterdam → Cogent.
Foreign traffic from this "Kazakh" server transits Russia, so it inherits Russian filtering of blocked services. Fine for the MVP test, unsuitable
as the permanent exit. Every EU candidate gets the same route check (no Russian hop) before it is kept.

## Phase 1: protocol matrix (tests/matrix.sh)

| server (AS) | network | protocol | handshake | TTFB | down / up Mbps | sustained 500 MB | 45-min stability | freeze probe | verdict |
|---|---|---|---|---|---|---|---|---|---|
| kz-test Timeweb Almaty AS9123 | mobile Tinkoff, run 2, direct baseline 2.9 Mbps | Reality+Vision, 8443, fp firefox | OK | 1.93 s | 100 MB: 0 (failed) / 10 MB up: stalled | 50 MB at 2.8 Mbps, complete | 15 probes, 2 failed, 1 slow | worst 13 s, below freeze threshold | tunnel ≈ link speed; **open issue:** the 100 MB download and the upload fail in both mobile runs while the sustained download succeeds — cause unknown (carrier vs endpoints) |
| kz-test Timeweb Almaty AS9123 | mobile Tinkoff (T-Bank AS205638), direct baseline 5.4 Mbps | Reality+Vision, 8443, fp firefox | OK | 1.12 s | 100 MB: 0 (failed) / 10 MB up: stalled | 50 MB at 3.4 Mbps, complete | 15 probes, 2 failed | no freeze | works; throughput bounded by the weak mobile link at test time; rerun on better signal |
| kz-test Timeweb Almaty AS9123 | home MGTS | Reality+Vision, 8443, fp firefox | OK | 0.68 s | 72 / 22 | 50 MB at 68 Mbps (quick mode) | 17 probes, 0 failed | no freeze | works; XHTTP n/a on this host (no Caddy); AWG not deployed |

## Step 2: Mac on our VPN (2026-09-27)

Personal Mac switched from the commercial Amnezia service to Shadowrocket 2.2.92 → `avmax-timeweb-almaty`, rules `avmax-split.conf`:
foreign sites see 92.118.115.34 (KZ), Russian sites see the home MGTS address, ChatGPT/Claude see KZ, api.anthropic.com reachable (0.9 s).
Import notes: Shadowrocket for Mac adds a server when a `vless://` link is opened (`open "vless://…"`, silently, window must exist);
its Import button only takes its own formats; the reliable route is Type **Subscribe** + an http(s) URL serving a base64 link list.
Shadowrocket 2.2.92 fails against Xray ≥ 26.9.8 (ML-KEM key share), so the server pin to 26.7.28 stays until it is fixed.

## Step 3: iPhone on our VPN (2026-09-27)

iPhone (iOS 26.6.1), Shadowrocket → `avmax-timeweb-almaty` imported by scanning the QR code shown on the Mac, rules
`avmax-split.conf` by AirDrop. On home Wi-Fi: ifconfig.co sees 92.118.115.34 (KZ), ip.beget.ru sees the home address;
server latency 77 ms in Shadowrocket's test.

## Subscriptions on vpn.avmax.me (2026-09-27)

A record `vpn.avmax.me → 92.118.115.34` at GoDaddy (published within ~5 minutes of saving). `sub-shared.yml` on timeweb-almaty:
Let's Encrypt certificate issued, bare domain / wrong token / folder listing all 404, production sites still 200.
Mac and iPhone re-enrolled: subscription group "avmax" + `avmax-split.conf` from URL (with `update-url`); split re-verified on the Mac.

## Router prep (2026-09-27, before the flash drive)

Components OPKG + DoT/DoH proxies installed; DoH servers dns.google and cloudflare-dns.com added; web admin HTTPS moved to 5443
(443 closed, verified). Router DNS resolves rutracker.org (blocked by MGTS DNS), Google sees the query from Cloudflare → encrypted.
IPv6 "off" on the ISP connection did not stop LAN devices getting 2a00:… addresses; to be handled by XKeen's IPv6 switch.
During the router reboot the personal Mac fell back from Shadowrocket to Amnezia (Shadowrocket On Demand was not enabled yet).

## Step 4: router, stage 1 (2026-09-28)

Keenetic Giga KN-1012, Entware on a 32 GB USB drive (dropbear on port 22, keys in /opt/etc/dropbear/authorized_keys),
component "Kernel modules for Netfilter", XKeen 2.0 with Xray 26.7.28 in Hybrid mode (TCP redirect + UDP TProxy on 1181),
runetfreedom geo files, XKeen GeoIPSET for Russian subnets. Policy `xkeen` (Policy0) with Провайдер 1, only the test Mac bound.
Test Mac with no VPN app: foreign sites see 92.118.115.34 (KZ), Russian sites see the home address, YouTube 200 in 1.1 s,
claude.ai sees KZ, ya.ru 0.06 s; 50 MB via VPN 103 Mbps, 20 MB direct 142 Mbps (measured before the binding fix, direct path).
IPv6: after the router reboot LAN devices no longer get global IPv6; IPv6 attempts are captured by XKeen. Personal Mac unaffected.

## VDSina Amsterdam (2026-09-28): blocked from home

146.103.101.8 (AS216071, geolocated Amsterdam NL). SSH port open from Finland (27 ms), Israel, Moldova, Turkey, Iran and one
Russian check-host node; timed out from two other Russian nodes, from the router's direct MGTS path (no ping, no banner) and via
Almaty (which transits Moscow). Not installed. `tests/reach.sh` added so every candidate is checked from the home line first.

## VDSina Amsterdam, second address (2026-09-28): blocked from home, deployed but unusable

5.35.33.93 (AS216071, geolocated NL everywhere, Cloudflare NL, geofeed published). From abroad: full stack deployed via SSH over
the Amnezia tunnel (Frankfurt exit); cover site vpnvdsina.avmax.me 200 with a valid certificate. Service checks from the server:
ChatGPT/Gemini/Spotify/Google Play NL; Claude "Banned" by UnlockTests (same Cloudflare challenge that passes in a browser);
Netflix inconclusive (UnlockTests NO, title pages 200 at /nl-en/); route clean (one hop registered in Pskov but 11 ms from AMS).
**From MGTS (router, direct):** TCP 443 does not connect, port 80 connects then freezes, SSH freezes once the client banner is
sent (silent TCP to 22 gets the server banner); a temporary Xray client on the router stalls at "dialing TCP to 5.35.33.93:443"
while the identical test to Almaty works (exit in 0.65 s). Verdict: VDSina's network is filtered on MGTS; a new IP did not help.
Lesson: the decisive pre-rent check is TLS/443 from the home line, not SSH or ping.

## hostung.net S-1 "Germany" (2026-09-29): passes from home

213.209.135.6 (Cherry Servers AS214159; ipinfo, Cloudflare and Google say DE/Augsburg, ip-api says Stockholm, and the route
leaves via Telia Stockholm). $3.19/month, 1 vCPU, 1 GB. **From MGTS (router, direct) before install:** ping 25 ms, SSH banner
answered even after the client banner (VDSina froze here), TCP 443 refused instantly (reachable). After `site.yml` (first run
failed on the dpkg lock held by first-boot unattended-upgrades; the rerun passed): TLS to vpnhostung.avmax.me:443 from the
router 3/3 in 0.15 s; a temporary Xray Reality client on the router exits in Augsburg DE, generate_204 0.14 s, 100 MB CacheFly
in 3.0 s (~280 Mbit/s). Service checks from the server: ChatGPT/Gemini/Copilot/Perplexity/Prime Video/TikTok DE, YouTube GL=DE,
Google search 200 (no captcha), Drive 302, api.anthropic.com 401; claude.ai and chatgpt.com give curl the Cloudflare challenge
(same as Almaty, where both work in a browser); Netflix title pages land on /de-en/ (UnlockTests says NO, as for VDSina).
Added to subscriptions next to Almaty. **Router switched to it the same day** (group `eu`, 04_outbounds.json; Almaty kept as
`/opt/etc/xray/04_outbounds.prev.json`); avmax confirmed on the iPhone over home Wi-Fi: working. `tests/router-tunnel.sh`
added for this home-line tunnel check (109 Mbit/s in the evening run).

## Zoom stability via router → hostung-de (2026-09-29)

Complaint: in Zoom calls, every ~5 min others stop hearing avmax for ~1 min (downlink fine). Measured on this Mac at home
(Shadowrocket off, XKeen → hostung-de): a real Zoom call recorded on the server 15:48–16:07, per second, to/from Zoom media
(UDP 8801): upload never stopped (worst second 11 packets, normal 30–110), no stall logged. A synthetic call (one UDP flow of
STUN requests to Google, 20/s) for 16 min: 0.3% loss, no gap over 1 s, flow never re-created. The same flow plus a steady
2 Mbit/s upload for 10 min: 0.2% loss, no gaps, 11 × 15 MB uploads all at full rate, none stalled. Verdict: the tunnel is
not dropping upload. **Corrected the same day:** avmax did hear the freezes during that call, and in other apps too. A heavier
call-like stream (one UDP flow, 37 packets/s of ~150 B) through the router froze after 50–150 s: from then on only one packet
per ~16 s reached XKeen. The tunnel's TCP connection to the server stayed healthy (router send queue 0, nothing unacked on the
server), while the router's conntrack kept counting the Mac's packets. Cause: Keenetic PPE (software + hardware acceleration)
takes over established UDP flows and skips the TPROXY rule. TCP goes through REDIRECT (NAT), which survives acceleration, so
only UDP broke. After `no ppe software` + `no ppe hardware`: the same stream ran 6 min with 0.3% loss and no gaps. Speed barely
changed (direct 99–150 vs 117–135 Mbit/s, VPN 82 vs 92, evening noise), and router CPU stayed 86% idle during a download.

## Almaty from home degraded (2026-10-13)

`tests/router-tunnel.sh timeweb-almaty`: exit KZ, small requests fine (generate_204 0.6 s, YouTube, claude.ai), but Instagram
times out and the 100 MB CacheFly file stalls at 0. On the Almaty server itself the same file runs at 90 Mbit/s and Instagram
answers 200, so the server's own route is fine. Large transfers on the MGTS → Almaty tunnel are being throttled; in September
the same test passed. hostung-de in the same run: 103 Mbit/s. Almaty is a backup for small traffic only.

## Decision (2026-10-13)

- EU node: `hostung-de` 213.209.135.6 (hostung.net S-1, Cherry Servers, geolocated DE). Passes TLS/Reality from MGTS,
  100–280 Mbit/s; default for the router and all devices.
- Standby: `timeweb-almaty` (shared production host, Xray on 8443; Moscow transit; since 2026-10-13 large transfers stall). Router:
  `vpn-mode server timeweb-almaty`; devices: pick it in Shadowrocket.
- Router: split only (XKeen, policy `xkeen`, PPE off). The AmneziaWG fallback (manual 5.8) is prepared but not configured.
