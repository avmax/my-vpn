#!/usr/bin/env python3
"""Expand one domain into the set of related domains a service needs, for rules/custom.json.

  rules/expand.py yandex.ru                 # v2fly company list + crt.sh subdomains + homepage crawl
  rules/expand.py yandex.ru --ai            # + ask Claude for CDN/API/auth/push hosts (ANTHROPIC_API_KEY or `ant auth login`)
  rules/expand.py yandex.ru --apply direct  # append the reviewed result to custom.json ("direct" | "proxy" | "block")

Nothing touches custom.json without --apply; review the printed candidates first.
"""
import argparse
import json
import re
import sys
import urllib.parse
import urllib.request
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RULES = ROOT / "rules" / "custom.json"
V2FLY_INDEX = "https://data.jsdelivr.com/v1/package/gh/v2fly/domain-list-community@master/flat"
V2FLY_INDEX_FALLBACK = "https://api.github.com/repos/v2fly/domain-list-community/git/trees/master?recursive=1"
V2FLY_RAW = "https://raw.githubusercontent.com/v2fly/domain-list-community/master/data/"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) Firefox/128.0"


def fetch(url, timeout=30):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def registrable(host):
    """yandex.ru -> yandex.ru; a.b.yandex.ru -> yandex.ru; sub.yandex.com.tr -> yandex.com.tr (naive 2-3 label rule)."""
    parts = host.lower().strip(".").split(".")
    if len(parts) >= 3 and parts[-2] in ("com", "co", "org", "net", "gov", "edu") and len(parts[-1]) == 2:
        return ".".join(parts[-3:])
    return ".".join(parts[-2:])


def v2fly_candidates(domain):
    """Return (tag, members) if the v2fly community keeps a list for this brand."""
    brand = registrable(domain).split(".")[0]
    names = None
    try:   # jsDelivr lists every file of the repo (GitHub's contents API stops at 1000 entries)
        names = [f["name"].split("/data/", 1)[1] for f in json.loads(fetch(V2FLY_INDEX))["files"] if "/data/" in f["name"]]
    except Exception:
        try:
            names = [t["path"][5:] for t in json.loads(fetch(V2FLY_INDEX_FALLBACK))["tree"] if t["path"].startswith("data/")]
        except Exception as ex:
            print(f"warning: v2fly index unavailable ({ex}); trying data/{brand} directly", file=sys.stderr)
            names = [brand]
    hits = [n for n in names if n == brand or n.startswith(brand + "-") or n.endswith("-" + brand)]
    out = {}
    for n in hits:
        try:
            text = fetch(V2FLY_RAW + n).decode()
        except Exception:
            continue
        members = []
        for line in text.splitlines():
            line = line.split("#", 1)[0].strip()
            if not line or line.startswith(("regexp:", "keyword:")):
                continue
            if line.startswith("include:"):
                members.append("geosite:" + line.split(":", 1)[1].strip())
            elif line.startswith("full:"):
                members.append("full:" + line.split(":", 1)[1].split("@")[0].strip())
            else:
                members.append(line.split("@")[0].strip())
        out[n] = members
    return out


def crtsh_subdomains(domain, limit=200):
    q = urllib.parse.quote(f"%.{domain}")
    try:
        rows = json.loads(fetch(f"https://crt.sh/?q={q}&output=json", timeout=60))
    except Exception as ex:
        print(f"warning: crt.sh unavailable ({ex})", file=sys.stderr)
        return []
    names = set()
    for r in rows:
        for n in r.get("name_value", "").split("\n"):
            n = n.strip().lower().lstrip("*.")
            if n.endswith(domain) and " " not in n:
                names.add(n)
    return sorted(names)[:limit]


class _Hosts(HTMLParser):
    def __init__(self):
        super().__init__(); self.hosts = set()
    def handle_starttag(self, tag, attrs):
        for k, val in attrs:
            if k in ("href", "src", "content", "data-src") and val and "//" in val:
                h = urllib.parse.urlparse(val if "://" in val else "https:" + val).hostname
                if h and "." in h:
                    self.hosts.add(h.lower())


def crawl_hosts(domain):
    p = _Hosts()
    for url in (f"https://{domain}/", f"https://www.{domain}/"):
        try:
            p.feed(fetch(url, timeout=20).decode("utf-8", "ignore"))
            break
        except Exception:
            continue
    return sorted(p.hosts)


def ai_candidates(domain, known):
    """Ask Claude which hostnames the service depends on. Structured JSON output; refusal fallbacks enabled."""
    import anthropic  # official SDK; credentials from ANTHROPIC_API_KEY / ANTHROPIC_AUTH_TOKEN / `ant auth login`
    client = anthropic.Anthropic()
    schema = {
        "type": "object",
        "properties": {
            "domains": {"type": "array", "items": {"type": "string"}},
            "notes": {"type": "string"},
        },
        "required": ["domains", "notes"],
        "additionalProperties": False,
    }
    prompt = (
        f"I am building a split-tunnel routing rule for the online service whose main domain is {domain}. "
        "List every registrable domain (not subdomains) that its web site, mobile apps and desktop apps contact so that "
        "the service works fully when all of them are routed the same way: main domains in all TLDs, static/CDN hosts, "
        "API and auth hosts, payment/ID hosts owned by the same company, push/analytics hosts they operate, and sister "
        "products of the same company that share login. Exclude third-party CDNs and trackers not owned by the company. "
        f"Already known (do not repeat): {', '.join(sorted(known)[:150])}. "
        "Return JSON only: {\"domains\": [...], \"notes\": \"one sentence on anything uncertain\"}."
    )
    resp = client.beta.messages.create(
        model="claude-opus-5",
        max_tokens=16000,
        betas=["server-side-fallback-2026-07-01"],
        fallbacks="default",
        output_config={"format": {"type": "json_schema", "schema": schema}},
        messages=[{"role": "user", "content": prompt}],
    )
    if resp.stop_reason == "refusal":
        print("warning: the model declined this request", file=sys.stderr)
        return [], ""
    text = next(b.text for b in resp.content if b.type == "text")
    data = json.loads(text)
    doms = sorted({d.strip().lower().lstrip("*.") for d in data.get("domains", []) if "." in d})
    return doms, data.get("notes", "")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("domain")
    ap.add_argument("--ai", action="store_true")
    ap.add_argument("--apply", choices=["direct", "proxy", "block"])
    a = ap.parse_args()
    domain = registrable(a.domain)

    result = {}  # entry -> source
    for tag, members in v2fly_candidates(domain).items():
        result[f"geosite:{tag}"] = "v2fly category (covers everything below it)"
        for m in members:
            result.setdefault(m, f"v2fly data/{tag}")
    for h in crawl_hosts(domain):
        result.setdefault(registrable(h), f"homepage crawl of {domain}")
    subs = crtsh_subdomains(domain)
    if subs:
        result.setdefault(domain, "crt.sh (subdomains are covered by the registrable domain)")
    if a.ai:
        doms, notes = ai_candidates(domain, set(result))
        for d in doms:
            result.setdefault(d, "Claude")
        if notes:
            print(f"# Claude notes: {notes}")

    entries = sorted(result, key=lambda e: (not e.startswith("geosite:"), e))
    print(f"# {len(entries)} candidates for {domain} ({len(subs)} subdomains seen in certificate transparency)")
    for e in entries:
        print(f"{e:45s}  # {result[e]}")

    if a.apply:
        data = json.loads(RULES.read_text()) if RULES.exists() else {"direct": [], "proxy": [], "block": []}
        lst = data.setdefault(a.apply, [])
        added = [e for e in entries if e not in lst]
        lst.extend(added)
        RULES.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
        print(f"# appended {len(added)} entries to {RULES} [{a.apply}]; now run clients/gen.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
