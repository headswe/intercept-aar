#!/usr/bin/env python3
"""Builds the standalone viewer page (aar-viewer.html) from viewer.body.html.

Usage: build.py [recording.jsonl [label]] [--body-only out.html]
With a recording, it is embedded as the example that loads on open.
"""
import html
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def build(sample: Path | None, label: str, body_only: bool) -> str:
    body = (HERE / "viewer.body.html").read_text(encoding="utf-8")
    block = ""
    if sample:
        data = sample.read_text(encoding="utf-8")
        if "</script" in data.lower():
            sys.exit("recording contains </script, refusing to embed")
        block = f'<script type="application/x-ndjson" id="sample" data-label="{html.escape(label)}">\n{data}</script>'
    body = body.replace("<!--SAMPLE-->", block)
    if body_only:
        return body
    return ('<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
            '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n'
            '<style>body{margin:0}[hidden]{display:none!important}</style>\n</head>\n<body>\n'
            + body + "\n</body>\n</html>\n")


if __name__ == "__main__":
    args = sys.argv[1:]
    body_only = "--body-only" in args
    out = None
    if body_only:
        i = args.index("--body-only"); out = Path(args[i + 1]); del args[i:i + 2]
    sample = Path(args[0]) if args else None
    label = args[1] if len(args) > 1 else "Example recording"
    page = build(sample, label, body_only)
    (out or HERE / "aar-viewer.html").write_text(page, encoding="utf-8")
