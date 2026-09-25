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

## Phase 1: protocol matrix (tests/matrix.sh)

| server (AS) | network | protocol | handshake | TTFB | down / up Mbps | sustained 500 MB | 45-min stability | freeze probe | verdict |
|---|---|---|---|---|---|---|---|---|---|

## Decision

- EU node: 
- Standby: 
- Router Full policy: AWG native / XKeen full rules (pick from AWG stability at home)
