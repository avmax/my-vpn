# Test results

Numbers from avmax's real networks. Every provider/protocol decision points at a row here.

## Phase 0: recon (tests/recon.sh)

| date | network | ISP / ASN | plain DNS to 8.8.8.8 | UDP (STUN) | notes |
|---|---|---|---|---|---|
| 2026-09-19 20:46 | home (Wi-Fi Keenetic-0650) | MGTS, AS25513, 46.138.11.182 (+ native IPv6) | 8.8.8.8 and 1.1.1.1 answer, but return NO ANSWER for rutracker.org (blocked domains are filtered at the resolver path); DoH to Google/Cloudflare works | STUN: Google FAIL, Cloudflare OK, Nextcloud OK (UDP partly filtered) | first run polluted by a VPN app for 2-3 min; this is the clean re-run |
| | mobile (Tinkoff / T2) | | | | |

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

Mobile (Tinkoff / T2): pending.

## Phase 1: protocol matrix (tests/matrix.sh)

| server (AS) | network | protocol | handshake | TTFB | down / up Mbps | sustained 500 MB | 45-min stability | freeze probe | verdict |
|---|---|---|---|---|---|---|---|---|---|

## Decision

- EU node: 
- Standby: 
- Router Full policy: AWG native / XKeen full rules (pick from AWG stability at home)
