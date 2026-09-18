# One-tap mode switching with Apple Shortcuts

## iPhone and Mac: Happ routing profiles
`clients/gen.py` writes `clients/out/happ/routing-{split,full}.deeplink.txt`. Create one Shortcut per mode:
1. Shortcuts → + → add action **Open URLs** → paste the `happ://routing/onadd/...` link.
2. Name it "VPN Split" / "VPN Full"; add to Home Screen / menu bar; optionally an Action Button binding.
Opening the link makes Happ import the profile (if new) and activate it. "Abroad" = select the `... ABROAD` server entry in Happ and keep the Full profile.

## Router (per device) from the phone or Mac
Shortcut with action **Run Script Over SSH** → host: the Mac (or any always-on box) → script:
```
/Users/avmax/Code/avmax-personal-vpn/router/keenetic-policy.sh tv full
```
Credentials come from `~/.config/keenetic.env` on that host:
```
KEENETIC_USER=admin
KEENETIC_PASS=...
POLICY_SPLIT=Policy0   # id of policy "xkeen" (router/keenetic-policy.sh --list)
POLICY_FULL=Policy1    # id of policy "Full"
```
Alternative without SSH: the Keenetic mobile app → device → Internet access policy (drag between policies).

## Router (whole XKeen ruleset)
Run Script Over SSH → host `192.168.1.1`, port 222, user root → `vpn-mode full` or `vpn-mode split`.
