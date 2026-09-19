# Routing rules

Three layers, first match wins, identical on every device:

1. `rules/custom.json` — your explicit overrides (`direct`, `proxy`, `block`).
2. Automatic geo detection — `geosite:category-ru`, `geosite:ru-available-only-inside`, `.ru/.su/.рф`, `geoip:ru`, private ranges → direct.
3. Everything else → VPN.

Entry syntax in `custom.json`: `yandex.ru` (domain + all subdomains), `full:api.example.com` (exact host),
`geosite:yandex` (a v2fly category), `203.0.113.0/24` (CIDR, goes to the router's `ip_exclude.lst` when in `direct`).

Growing a list from one domain:

```bash
.venv/bin/python rules/expand.py yandex.ru            # v2fly company list + certificate-transparency subdomains + homepage crawl
.venv/bin/python rules/expand.py yandex.ru --ai       # also asks Claude for CDN/API/auth hosts (needs ANTHROPIC_API_KEY)
.venv/bin/python rules/expand.py yandex.ru --apply direct   # review the printed list, then append it to custom.json
```

After editing: `.venv/bin/python clients/gen.py`, redeploy the subscription files (`ansible-playbook site.yml -l eu --tags caddy`),
copy the new `05_routing.json`/`ip_exclude.lst` to the router (`router/xkeen-install.md`). Shadowrocket and Happ pick the change up on refresh.
