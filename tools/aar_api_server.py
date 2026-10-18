#!/usr/bin/env python3
"""Reference server for the viewer's recordings API (see "Recordings from an API" in the README).

Serves the .jsonl recordings in a folder:
  GET /api/recordings?limit=50&offset=0   list, newest first: {"recordings": [...], "next": url|null, "total": n}
  GET /api/recordings/<id>                one recording (the .jsonl text); <id> is the file name
and, with --viewer, the viewer page at / (with a viewer-config.json pointing it at the API),
so the two share an origin.

Usage: aar_api_server.py <aar folder> [--port 8080] [--bind 127.0.0.1] [--token SECRET]
                         [--cors https://viewer.example.com] [--viewer viewer/aar-viewer.html]
With --token, requests need "Authorization: Bearer SECRET". Python 3, no packages.
It is a reference for the contract, not a hardened server: put it behind a proper web server
(TLS, rate limits) before exposing it to the internet.
"""
import argparse
import json
import os
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlsplit

NAME = re.compile(r"^(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})_(.+)_([^_]+)\.jsonl$", re.I)
_meta_cache: dict[tuple[str, float, int], dict] = {}


def meta(path: Path) -> dict:
    """List entry for one recording: header fields from the first line, duration from the last records."""
    st = path.stat()
    key = (path.name, st.st_mtime, st.st_size)
    if key in _meta_cache:
        return _meta_cache[key]
    entry = {"id": path.name, "name": path.name, "size": st.st_size}
    m = NAME.match(path.name)
    if m:
        entry["date"] = f"{m[1]}-{m[2]}-{m[3]}T{m[4]}:{m[5]}:{m[6]}Z"
        entry["title"], entry["world"] = m[7], m[8]
    with path.open("rb") as f:
        try:
            head = json.loads(f.readline())
            if head.get("type") == "header":
                entry["title"] = head.get("briefing_name") or head.get("on_load_name") or head.get("mission") or entry.get("title")
                entry["world"] = head.get("world") or entry.get("world")
                entry["date"] = head.get("started_utc") or entry.get("date")
        except ValueError:
            pass
        # The highest record time near the end of the file; a recording still being written may end mid-line.
        f.seek(max(0, st.st_size - 65536))
        duration = 0.0
        for line in f.read().splitlines():
            try:
                t = json.loads(line).get("t")
                if isinstance(t, (int, float)):
                    duration = max(duration, float(t))
            except (ValueError, AttributeError):
                pass
        entry["duration"] = round(duration, 1)
    entry = {k: v for k, v in entry.items() if v not in (None, "")}
    _meta_cache[key] = entry
    return entry


def make_handler(folder: Path, token: str, cors: str, viewer: Path | None):
    class Handler(BaseHTTPRequestHandler):
        def headers_out(self, code: int, ctype: str, length: int):
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(length))
            self.send_header("Cache-Control", "no-cache")
            if cors:
                self.send_header("Access-Control-Allow-Origin", cors)
                self.send_header("Access-Control-Allow-Headers", "Authorization")
                self.send_header("Access-Control-Allow-Credentials", "true")
                self.send_header("Vary", "Origin")
            self.end_headers()

        def send(self, code: int, body: bytes, ctype: str = "application/json"):
            self.headers_out(code, ctype, len(body))
            if self.command != "HEAD":
                self.wfile.write(body)

        def error(self, code: int, msg: str):
            self.send(code, json.dumps({"error": msg}).encode())

        def do_OPTIONS(self):
            self.headers_out(204, "text/plain", 0)

        def do_HEAD(self):
            self.do_GET()

        def do_GET(self):
            url = urlsplit(self.path)
            if viewer and url.path in ("/", "/index.html"):
                return self.send(200, viewer.read_bytes(), "text/html; charset=utf-8")
            if viewer and url.path == "/viewer-config.json":
                return self.send(200, json.dumps({"recordingsApi": "/api/recordings"}).encode())
            if not url.path.startswith("/api/recordings"):
                return self.error(404, "not found")
            if token and self.headers.get("Authorization") != "Bearer " + token:
                return self.error(401, "missing or wrong token")
            rest = url.path[len("/api/recordings"):].strip("/")
            if rest:
                name = unquote(rest)
                path = folder / name
                if "/" in name or "\\" in name or not name.endswith(".jsonl") or not path.is_file():
                    return self.error(404, "no such recording")
                size = path.stat().st_size
                self.headers_out(200, "application/x-ndjson; charset=utf-8", size)
                if self.command != "HEAD":
                    with path.open("rb") as f:
                        while chunk := f.read(1 << 20):
                            self.wfile.write(chunk)
                return
            q = parse_qs(url.query)
            try:
                limit = max(1, min(500, int(q.get("limit", ["50"])[0])))
                offset = max(0, int(q.get("offset", ["0"])[0]))
            except ValueError:
                return self.error(400, "limit and offset must be numbers")
            # Recorder file names start with the UTC start time, so reverse name order is newest first.
            files = sorted((p for p in folder.glob("*.jsonl") if p.is_file()), key=lambda p: p.name, reverse=True)
            page = [meta(p) for p in files[offset:offset + limit]]
            nxt = f"/api/recordings?limit={limit}&offset={offset + limit}" if offset + limit < len(files) else None
            self.send(200, json.dumps({"recordings": page, "next": nxt, "total": len(files)}).encode())

        def log_message(self, fmt, *args):
            print("%s %s" % (self.address_string(), fmt % args))

    return Handler


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("folder", type=Path, help="the server's aar folder")
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--bind", default="127.0.0.1", help="address to listen on (0.0.0.0 for every interface)")
    ap.add_argument("--token", default=os.environ.get("AAR_API_TOKEN", ""), help="require this bearer token (or set AAR_API_TOKEN)")
    ap.add_argument("--cors", default="", help="origin allowed to call the API from another site, e.g. https://headswe.github.io")
    ap.add_argument("--viewer", type=Path, help="serve this viewer page at /")
    a = ap.parse_args()
    if not a.folder.is_dir():
        ap.error(f"{a.folder} is not a folder")
    srv = ThreadingHTTPServer((a.bind, a.port), make_handler(a.folder.resolve(), a.token, a.cors, a.viewer))
    print(f"Serving {a.folder} on http://{a.bind}:{a.port}/api/recordings" + (f" and the viewer at http://{a.bind}:{a.port}/" if a.viewer else ""))
    srv.serve_forever()


if __name__ == "__main__":
    main()
