#!/usr/bin/env python3
"""Fetches MissionDB tile configs so the Pages build can embed them in the viewer.

The tile host sends no CORS headers, so the viewer cannot read the configs itself
from another site. Usage: fetch_terrains.py out.json [base_url]
Writes {"aliases": {...}, "terrains": {slug: config}} for the worlds in terrains.txt
plus every alias and alias target. Worlds MissionDB has not tiled are skipped.
MissionDB sometimes answers 502, so requests are retried, and with
--previous <url> any config it still cannot fetch is taken from the copy
embedded in that page (the currently published viewer).
"""
import json
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
KEEP = ("name", "width", "height", "bgColor", "maxZoom", "minZoom", "doubleSize", "version", "dynamicMaxZoom")


def get(url, tries=4):
    """JSON at url, None on 404. Retries server errors and network failures, then raises."""
    req = urllib.request.Request(url, headers={"User-Agent": "arma-aar-viewer-build"})
    for attempt in range(tries):
        try:
            with urllib.request.urlopen(req, timeout=30) as res:
                return json.load(res)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            if e.code < 500 or attempt == tries - 1:
                raise
        except (urllib.error.URLError, TimeoutError):
            if attempt == tries - 1:
                raise
        time.sleep(2 ** attempt)


def previous_terrains(url):
    """The terrains embedded in an already published viewer page, or an empty copy."""
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "arma-aar-viewer-build"})
        with urllib.request.urlopen(req, timeout=30) as res:
            page = res.read().decode("utf-8")
        m = re.search(r'<script type="application/json" id="terrains">(.*?)</script>', page, re.S)
        if m:
            return json.loads(m.group(1))
    except Exception as e:
        print(f"previous terrains unavailable: {e}")
    return {"aliases": {}, "terrains": {}}


def main():
    args = sys.argv[1:]
    prev = {"aliases": {}, "terrains": {}}
    if "--previous" in args:
        i = args.index("--previous")
        prev = previous_terrains(args[i + 1])
        del args[i:i + 2]
    out = Path(args[0])
    base = args[1] if len(args) > 1 else "https://mission-db.1tac.eu/tiles/"
    if not base.endswith("/"):
        base += "/"
    try:
        aliases = get(base + "config.json") or {}
    except Exception as e:
        print(f"alias map failed ({e}), using the previous copy")
        aliases = prev.get("aliases", {})
    worlds = [l.strip().lower() for l in (HERE / "terrains.txt").read_text().splitlines()]
    slugs = sorted({w for w in worlds if w and not w.startswith("#")} - set(aliases) | set(aliases.values()))
    terrains = {}
    for slug in slugs:
        try:
            cfg = get(base + slug + "/config.json")
        except Exception as e:
            print(f"{slug} failed ({e}), using the previous copy")
            cfg = prev.get("terrains", {}).get(slug)
        if isinstance(cfg, dict) and cfg.get("width"):
            terrains[slug] = {k: cfg[k] for k in KEEP if k in cfg}
    out.write_text(json.dumps({"aliases": aliases, "terrains": terrains}, separators=(",", ":")), encoding="utf-8")
    print(f"{len(terrains)} of {len(slugs)} terrains, {len(aliases)} aliases")
    if not terrains:
        sys.exit("no terrain configs fetched")


if __name__ == "__main__":
    main()
