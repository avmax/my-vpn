# One-tap switches with Apple Shortcuts

## Whole-home VPN on/off (router)
Shortcut → action **Run Script Over SSH**: host `192.168.1.1`, port `222`, user `root`, script `vpn-mode on` (second Shortcut: `vpn-mode off`,
third: `vpn-mode status`). Add to Home Screen / menu bar / Action Button. Works from any device on the home Wi-Fi.

## Mac / iPhone away from home: nothing to tap
Shadowrocket's On Demand rules do it: Settings → On Demand → add rules
1. **Cellular → Connect**
2. **Wi-Fi, SSID = <home SSID> → Disconnect** (the router handles home)
3. **Wi-Fi, SSID keyword `*` (any other) → Connect**
With On Demand enabled the system VPN switch will not stay off; to pause the VPN temporarily, toggle On Demand in the app.
Abroad: open Shadowrocket and pick the `avmax-<server>-abroad` server entry (Russian sites will exit from the Moscow node).

## Optional per-device exception on the router
`router/keenetic-policy.sh <device> default` moves a device out of XKeen's reach by assigning a Keenetic policy without the proxy
(needs a policy created in the UI and `POLICY_SPLIT`/`POLICY_FULL` in `~/.config/keenetic.env`); simpler: add its LAN IP to `ip_exclude.lst`.
