#!/usr/bin/env python3
"""Fetches MissionDB tile configs so the Pages build can embed them in the viewer.

The tile host sends no CORS headers, so the viewer cannot read the configs itself
from another site. Usage: fetch_terrains.py out.json [base_url]
Writes {"aliases": {...}, "terrains": {slug: config}} for the worlds in terrains.txt
plus every alias and alias target. Worlds MissionDB has not tiled are skipped.
"""
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
KEEP = ("name", "width", "height", "bgColor", "maxZoom", "minZoom", "doubleSize", "version", "dynamicMaxZoom")


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "arma-aar-viewer-build"})
    try:
        with urllib.request.urlopen(req, timeout=30) as res:
            return json.load(res)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


def main():
    out = Path(sys.argv[1])
    base = sys.argv[2] if len(sys.argv) > 2 else "https://mission-db.1tac.eu/tiles/"
    if not base.endswith("/"):
        base += "/"
    aliases = get(base + "config.json") or {}
    worlds = [l.strip().lower() for l in (HERE / "terrains.txt").read_text().splitlines()]
    slugs = sorted({w for w in worlds if w and not w.startswith("#")} - set(aliases) | set(aliases.values()))
    terrains = {}
    for slug in slugs:
        cfg = get(base + slug + "/config.json")
        if isinstance(cfg, dict) and cfg.get("width"):
            terrains[slug] = {k: cfg[k] for k in KEEP if k in cfg}
    out.write_text(json.dumps({"aliases": aliases, "terrains": terrains}, separators=(",", ":")), encoding="utf-8")
    print(f"{len(terrains)} of {len(slugs)} terrains, {len(aliases)} aliases")
    if not terrains:
        sys.exit("no terrain configs fetched")


if __name__ == "__main__":
    main()
