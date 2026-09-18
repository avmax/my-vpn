# Test results

Numbers from avmax's real networks. Every provider/protocol decision points at a row here.

## Phase 0: recon (tests/recon.sh)

| date | network | ISP / ASN | plain DNS to 8.8.8.8 | UDP (STUN) | notes |
|---|---|---|---|---|---|
| | home | | | | |
| | mobile (Tinkoff / T2) | | | | |

Hoster reachability (copy the table from tests/out/recon-*.md):

| provider | location | role | home Mbps | mobile Mbps | verdict |
|---|---|---|---|---|---|

## Phase 1: protocol matrix (tests/matrix.sh)

| server (AS) | network | protocol | handshake | TTFB | down / up Mbps | sustained 500 MB | 45-min stability | freeze probe | verdict |
|---|---|---|---|---|---|---|---|---|---|

## Decision

- EU node: 
- Standby: 
- Router Full policy: AWG native / XKeen full rules (pick from AWG stability at home)
