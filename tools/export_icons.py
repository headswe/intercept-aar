#!/usr/bin/env python3
"""Exports game textures (map icons, vehicle and weapon pictures, TMF group icons) as PNG, so the
viewer can draw them. Browsers cannot read .paa and the files sit inside the game's and mods' PBOs,
so this reads those directly. No packages needed.

Usage: export_icons.py ARMA_DIR [MOD_DIR ...] [-c aar-cfg.json] [-r RECORDING_OR_DIR ...]
                       [--all-pictures] [--include PATH_PREFIX ...] [-o aar-icons.json] [--size 64]

ARMA_DIR and every MOD_DIR are searched recursively for .pbo files (!Workshop included).
Textures come from:
  -c   the config export from tools/export_cfg.sqf: every map icon, plus the pictures of the
       vehicles and weapons the recordings use (all of them with --all-pictures)
  -r   recordings: any .paa path in any record (TMF group icons, the units' map icons)
  --include  every .paa under a path inside the PBOs, e.g. a3\\ui_f\\data\\map\\markers
The output is merged into an existing file, so it can be run again for new recordings or mods.
Put aar-icons.json next to the viewer page or in its aar/ folder, or open it in the viewer.
"""
import argparse
import base64
import json
import os
import struct
import sys
import zlib
from pathlib import Path


def norm(path: str) -> str:
    """The key the viewer looks textures up by: lower case, backslashes, no leading slash, .paa."""
    p = path.strip().replace("/", "\\").lstrip("\\").lower()
    if p and "." not in p.rsplit("\\", 1)[-1]:
        p += ".paa"
    return p


# ---------- PBO ----------

def read_pbo_index(path: Path):
    """Yields (file path inside the game, offset, stored size, original size, packed) for each entry."""
    with open(path, "rb") as f:
        data = f.read(1 << 20)
        pos = 0
        entries = []
        prefix = ""

        def zstr():
            nonlocal data, pos
            while True:
                end = data.find(b"\0", pos)
                if end >= 0:
                    s = data[pos:end].decode("utf-8", "replace")
                    pos = end + 1
                    return s
                more = f.read(1 << 20)
                if not more:
                    raise ValueError("truncated PBO header")
                data += more

        def need(n):
            nonlocal data
            while len(data) < pos + n:
                more = f.read(1 << 20)
                if not more:
                    raise ValueError("truncated PBO header")
                data += more

        first = True
        while True:
            name = zstr()
            need(20)
            method, original, _, _, size = struct.unpack_from("<5I", data, pos)
            pos += 20
            if first and name == "" and method == 0x56657273:  # "Vers": header extensions
                while True:
                    key = zstr()
                    if key == "":
                        break
                    value = zstr()
                    if key.lower() == "prefix":
                        prefix = value
                first = False
                continue
            first = False
            if name == "":
                break
            entries.append((name, size, original, method == 0x43707273))
    offset = pos
    prefix = prefix.replace("/", "\\").strip("\\").lower()
    for name, size, original, packed in entries:
        full = (prefix + "\\" if prefix else "") + name.replace("/", "\\").lower()
        yield full, offset, size, original, packed
        offset += size


def find_pbos(dirs):
    seen = set()
    for d in dirs:
        for root, _, files in os.walk(d, followlinks=True):
            for fn in files:
                if fn.lower().endswith(".pbo"):
                    p = Path(root, fn)
                    try:
                        key = p.resolve()
                    except OSError:
                        continue
                    if key not in seen:
                        seen.add(key)
                        yield p


# ---------- decompression ----------

def lzss(src: bytes, out_len: int) -> bytes:
    """Bohemia's LZSS: flag bytes, literals, and 12-bit back references relative to the output end."""
    out = bytearray()
    i = 0
    while len(out) < out_len and i < len(src):
        flags = src[i]
        i += 1
        for bit in range(8):
            if len(out) >= out_len or i >= len(src):
                break
            if flags & (1 << bit):
                out.append(src[i])
                i += 1
            else:
                b1, b2 = src[i], src[i + 1]
                i += 2
                rpos = len(out) - (b1 | ((b2 & 0xF0) << 4))
                for _ in range((b2 & 0x0F) + 3):
                    out.append(out[rpos] if rpos >= 0 else 0x20)
                    rpos += 1
    return bytes(out[:out_len])


def lzo1x(src: bytes, out_len: int) -> bytes:
    """LZO1X decompression (as in minilzo's lzo1x_decompress), used for DXT mipmaps."""
    out = bytearray()
    ip = 0

    def literals(n):
        nonlocal ip
        out.extend(src[ip:ip + n])
        ip += n

    def copy(back, n):
        p = len(out) - back
        if p < 0:
            raise ValueError("LZO lookbehind overrun")
        for _ in range(n):
            out.append(out[p])
            p += 1

    def run(t, extra):
        nonlocal ip
        if t == 0:
            while src[ip] == 0:
                t += 255
                ip += 1
            t += extra + src[ip]
            ip += 1
        return t

    state = "loop"
    t = 0
    if src[0] > 17:
        t = src[0] - 17
        ip = 1
        if t < 4:
            state = "match_next"
        else:
            literals(t)
            state = "first_literal_run"
    while True:
        if state == "loop":
            t = src[ip]
            ip += 1
            if t >= 16:
                state = "match"
                continue
            literals(run(t, 15) + 3)
            state = "first_literal_run"
        if state == "first_literal_run":
            t = src[ip]
            ip += 1
            if t >= 16:
                state = "match"
                continue
            copy(1 + 0x0800 + (t >> 2) + (src[ip] << 2), 3)
            ip += 1
            state = "match_done"
        if state == "match":
            if t >= 64:
                back = 1 + ((t >> 2) & 7) + (src[ip] << 3)
                ip += 1
                copy(back, (t >> 5) + 1)
            elif t >= 32:
                t = run(t & 31, 31)
                back = 1 + (src[ip] >> 2) + (src[ip + 1] << 6)
                ip += 2
                copy(back, t + 2)
            elif t >= 16:
                back = (t & 8) << 11
                t = run(t & 7, 7)
                back += (src[ip] >> 2) + (src[ip + 1] << 6)
                ip += 2
                if back == 0:
                    break  # end of stream
                copy(back + 0x4000, t + 2)
            else:
                copy(1 + (t >> 2) + (src[ip] << 2), 2)
                ip += 1
            state = "match_done"
        if state == "match_done":
            t = src[ip - 2] & 3
            if t == 0:
                state = "loop"
                continue
            state = "match_next"
        if state == "match_next":
            literals(t)
            t = src[ip]
            ip += 1
            state = "match"
    if len(out) != out_len:
        raise ValueError(f"LZO output {len(out)} bytes, expected {out_len}")
    return bytes(out)


# ---------- PAA ----------

def rgb565(c):
    return ((c >> 11) & 31) * 255 // 31, ((c >> 5) & 63) * 255 // 63, (c & 31) * 255 // 31


def dxt(data: bytes, w: int, h: int, dxt5: bool) -> bytearray:
    out = bytearray(w * h * 4)
    pos = 0
    for by in range(0, h, 4):
        for bx in range(0, w, 4):
            alpha = None
            if dxt5:
                a0, a1 = data[pos], data[pos + 1]
                bits = int.from_bytes(data[pos + 2:pos + 8], "little")
                pos += 8
                if a0 > a1:
                    pal = [a0, a1] + [((7 - i) * a0 + i * a1) // 7 for i in range(1, 7)]
                else:
                    pal = [a0, a1] + [((5 - i) * a0 + i * a1) // 5 for i in range(1, 5)] + [0, 255]
                alpha = [pal[(bits >> (3 * i)) & 7] for i in range(16)]
            c0, c1, idx = struct.unpack_from("<HHI", data, pos)
            pos += 8
            p0, p1 = rgb565(c0), rgb565(c1)
            if c0 > c1 or dxt5:
                cols = [p0 + (255,), p1 + (255,),
                        tuple((2 * a + b) // 3 for a, b in zip(p0, p1)) + (255,),
                        tuple((a + 2 * b) // 3 for a, b in zip(p0, p1)) + (255,)]
            else:
                cols = [p0 + (255,), p1 + (255,), tuple((a + b) // 2 for a, b in zip(p0, p1)) + (255,), (0, 0, 0, 0)]
            for i in range(16):
                x, y = bx + (i & 3), by + (i >> 2)
                if x >= w or y >= h:
                    continue
                r, g, b, a = cols[(idx >> (2 * i)) & 3]
                if alpha is not None:
                    a = alpha[i]
                o = (y * w + x) * 4
                out[o:o + 4] = bytes((r, g, b, a))
    return out


def paa_to_rgba(paa: bytes, want: int):
    """Decodes the smallest mipmap at least `want` pixels on its longer side (or the largest there is).
    Returns (width, height, RGBA bytes)."""
    kind = struct.unpack_from("<H", paa, 0)[0]
    pos = 2
    while paa[pos:pos + 4] == b"GGAT":
        pos += 8 + 4 + struct.unpack_from("<I", paa, pos + 8)[0]
    pos += 2 + 3 * struct.unpack_from("<H", paa, pos)[0]  # palette
    mips = []
    while pos + 7 <= len(paa):
        w, h = struct.unpack_from("<HH", paa, pos)
        if w == 0 or h == 0:
            break
        size = int.from_bytes(paa[pos + 4:pos + 7], "little")
        mips.append((w, h, paa[pos + 7:pos + 7 + size]))
        pos += 7 + size
    if not mips:
        raise ValueError("no mipmaps")
    pick = mips[0]
    for m in mips:
        if max(m[0] & 0x7FFF, m[1]) >= want:
            pick = m
    w, h, data = pick
    lzo = bool(w & 0x8000)
    w &= 0x7FFF
    if kind in (0xFF01, 0xFF05):  # DXT1, DXT5
        blocks = ((w + 3) // 4) * ((h + 3) // 4)
        raw_len = blocks * (8 if kind == 0xFF01 else 16)
        if lzo:
            data = lzo1x(data, raw_len)
        return w, h, dxt(data, w, h, kind != 0xFF01)
    bpp = 4 if kind == 0x8888 else 2
    if len(data) < w * h * bpp:
        data = lzss(data, w * h * bpp)
    out = bytearray(w * h * 4)
    for i in range(w * h):
        if kind == 0x8888:  # stored B, G, R, A
            b, g, r, a = data[i * 4:i * 4 + 4]
        elif kind == 0x8080:  # grey and alpha
            r = g = b = data[i * 2]
            a = data[i * 2 + 1]
        else:
            v = data[i * 2] | (data[i * 2 + 1] << 8)
            if kind == 0x4444:
                a, r, g, b = ((v >> 12) & 15) * 17, ((v >> 8) & 15) * 17, ((v >> 4) & 15) * 17, (v & 15) * 17
            elif kind == 0x1555:
                a, r, g, b = (255 if v & 0x8000 else 0), ((v >> 10) & 31) * 255 // 31, ((v >> 5) & 31) * 255 // 31, (v & 31) * 255 // 31
            else:
                raise ValueError(f"unknown PAA type {kind:#x}")
        out[i * 4:i * 4 + 4] = bytes((r, g, b, a))
    return w, h, out


def png(w: int, h: int, rgba: bytes) -> bytes:
    rows = b"".join(b"\0" + bytes(rgba[y * w * 4:(y + 1) * w * 4]) for y in range(h))

    def chunk(tag, body):
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b""))


# ---------- recordings ----------

def paths_in(value, out):
    if isinstance(value, str):
        if value.lower().endswith(".paa"):
            out.add(norm(value))
    elif isinstance(value, dict):
        for k, v in value.items():
            # Config pictures are often given without the .paa.
            if k in ("picture", "icon_path") and isinstance(v, str) and "\\" in v.replace("/", "\\"):
                out.add(norm(v))
            else:
                paths_in(v, out)
    elif isinstance(value, list):
        for v in value:
            paths_in(v, out)


def recording_paths(sources, classes):
    """Texture paths in the recordings; also collects the vehicle and weapon classes they use."""
    out = set()
    for src in sources:
        src = Path(src)
        files = sorted(src.rglob("*.jsonl")) if src.is_dir() else [src]
        for f in files:
            with open(f, encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    try:
                        o = json.loads(line)
                    except ValueError:
                        continue
                    paths_in(o, out)
                    if isinstance(o, dict):
                        for k in ("class", "weapon"):
                            if isinstance(o.get(k), str):
                                classes.add(o[k].lower())
    out.discard("")
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dirs", nargs="+", help="Arma 3 folder and any mod folders to search for PBOs")
    ap.add_argument("-c", "--cfg", help="aar-cfg.json from tools/export_cfg.sqf")
    ap.add_argument("--all-pictures", action="store_true", help="with -c, every vehicle and weapon picture")
    ap.add_argument("-r", "--recording", action="append", default=[], help="recording .jsonl or a folder of them")
    ap.add_argument("--include", action="append", default=[], help="also export every .paa under this path")
    ap.add_argument("-o", "--out", default="aar-icons.json")
    ap.add_argument("--size", type=int, default=64, help="smallest mipmap side to keep (default 64)")
    args = ap.parse_args(argv)

    classes = set()
    wanted = recording_paths(args.recording, classes)
    if args.cfg:
        cfg = json.loads(Path(args.cfg).read_text(encoding="utf-8"))
        if cfg.get("format") != "aar-cfg":
            sys.exit(f"{args.cfg} is not an export from export_cfg.sqf")
        wanted |= {norm(p) for p in cfg.get("vehicle_icons", {}).values() if p}
        for table in ("vehicles", "weapons"):
            for cls, row in cfg.get(table, {}).items():
                if len(row) > 1 and row[1] and (args.all_pictures or cls.lower() in classes):
                    wanted.add(norm(row[1]))
        wanted.discard("")
    prefixes = [norm(p).removesuffix(".paa").rstrip("\\") + "\\" for p in args.include]
    if not wanted and not prefixes:
        sys.exit("nothing to export: give -c, -r or --include")

    index = {}
    pbos = 0
    for pbo in find_pbos(args.dirs):
        pbos += 1
        try:
            for full, offset, size, original, packed in read_pbo_index(pbo):
                if full.endswith(".paa") and (full in wanted or any(full.startswith(p) for p in prefixes)):
                    index.setdefault(full, (pbo, offset, size, original, packed))
        except (OSError, ValueError, struct.error) as e:
            print(f"skipped {pbo}: {e}", file=sys.stderr)

    out_path = Path(args.out)
    pack = {"format": "aar-icons", "version": 1, "icons": {}}
    if out_path.exists():
        try:
            old = json.loads(out_path.read_text(encoding="utf-8"))
            if old.get("format") == "aar-icons":
                pack["icons"].update(old.get("icons", {}))
        except ValueError:
            pass

    done = failed = 0
    for full, (pbo, offset, size, original, packed) in sorted(index.items()):
        try:
            with open(pbo, "rb") as f:
                f.seek(offset)
                data = f.read(size)
            if packed:
                data = lzss(data, original)
            w, h, rgba = paa_to_rgba(data, args.size)
            pack["icons"][full] = "data:image/png;base64," + base64.b64encode(png(w, h, rgba)).decode()
            done += 1
        except (ValueError, IndexError, struct.error) as e:
            failed += 1
            print(f"could not decode {full}: {e}", file=sys.stderr)

    missing = sorted(p for p in wanted if p not in index)
    out_path.write_text(json.dumps(pack, separators=(",", ":")), encoding="utf-8")
    print(f"{pbos} PBOs searched, {done} textures exported, {failed} failed, {len(missing)} not found; "
          f"{len(pack['icons'])} in {out_path}")
    for p in missing[:20]:
        print("  not found:", p)
    if len(missing) > 20:
        print(f"  ... and {len(missing) - 20} more (missing mod folders?)")


if __name__ == "__main__":
    main()
