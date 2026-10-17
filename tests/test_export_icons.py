"""Tests for tools/export_icons.py: PBO reading, LZO/LZSS, PAA decoding and the icon pack."""
import base64
import json
import struct
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import export_icons as E  # noqa: E402

# python-lzo's lzo.compress(data, 1, False) of LZO_DATA.
LZO_DATA = (b"\x11\x22\x33\x44" * 40) + bytes(range(64)) + b"abc" * 30
LZO_PACKED = bytes.fromhex(
    "05112233441122334420771c000031000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
    "202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f61626320230800000163616263616263"
    "616263616263616263616263110000")


def dxt1_block(c0, c1, indices):
    return struct.pack("<HHI", c0, c1, sum(i << (2 * n) for n, i in enumerate(indices)))


def paa(kind, mips, taggs=b""):
    out = struct.pack("<H", kind) + taggs + struct.pack("<H", 0)
    for w, h, data in mips:
        out += struct.pack("<HH", w, h) + len(data).to_bytes(3, "little") + data
    return out + b"\0" * 6


def pbo(prefix, files):
    head = b"\0" + struct.pack("<5I", 0x56657273, 0, 0, 0, 0) + b"prefix\0" + prefix.encode() + b"\0\0"
    for name, data in files:
        head += name.encode() + b"\0" + struct.pack("<5I", 0, len(data), 0, 0, len(data))
    head += b"\0" + b"\0" * 20
    return head + b"".join(d for _, d in files) + b"\0" * 21


def decode_png(data):
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    w, h = struct.unpack(">II", data[16:24])
    idat = data.index(b"IDAT")
    size = struct.unpack(">I", data[idat - 4:idat])[0]
    raw = zlib.decompress(data[idat + 4:idat + 4 + size])
    return w, h, b"".join(raw[y * (w * 4 + 1) + 1:(y + 1) * (w * 4 + 1)] for y in range(h))


class Decompression(unittest.TestCase):
    def test_lzo(self):
        self.assertEqual(E.lzo1x(LZO_PACKED, len(LZO_DATA)), LZO_DATA)

    def test_lzss(self):
        # Literals "abcd", then a back reference 4 bytes back for 6 bytes.
        packed = bytes([0x0F]) + b"abcd" + bytes([4, 3])
        self.assertEqual(E.lzss(packed, 10), b"abcdabcdab")
        # A reference before the start gives spaces.
        self.assertEqual(E.lzss(bytes([0x00, 2, 0]), 3), b"   ")


class Paa(unittest.TestCase):
    def test_dxt1(self):
        red, blue = 0xF800, 0x001F
        block = dxt1_block(red, blue, [0] * 8 + [1] * 8)
        w, h, rgba = E.paa_to_rgba(paa(0xFF01, [(4, 4, block)]), 64)
        self.assertEqual((w, h), (4, 4))
        self.assertEqual(rgba[0:4], bytes((255, 0, 0, 255)))
        self.assertEqual(rgba[-4:], bytes((0, 0, 255, 255)))

    def test_dxt1_transparent(self):
        # c0 <= c1: index 3 is transparent.
        _, _, rgba = E.paa_to_rgba(paa(0xFF01, [(4, 4, dxt1_block(0, 0xFFFF, [3] * 16))]), 64)
        self.assertEqual(rgba[3], 0)

    def test_dxt5_lzo_and_taggs_and_mip_choice(self):
        alpha = bytes([255, 0]) + (0).to_bytes(6, "little")  # every pixel alpha index 0 = 255
        block = alpha + dxt1_block(0x07E0, 0x07E0, [0] * 16)  # green
        big = block * 4  # 8x8
        taggs = b"GGATCXAM" + struct.pack("<I", 4) + b"\0\0\0\0"
        # The 8x8 mip is LZO compressed (width flag 0x8000), using the LZO stream of its bytes.
        packed = bytes([17 + len(big)]) + big + bytes([0x11, 0, 0])
        data = paa(0xFF05, [(8 | 0x8000, 8, packed), (4, 4, block)], taggs)
        w, h, rgba = E.paa_to_rgba(data, 8)
        self.assertEqual((w, h), (8, 8))
        self.assertEqual(rgba[0:4], bytes((0, 255, 0, 255)))
        w, h, _ = E.paa_to_rgba(data, 4)
        self.assertEqual((w, h), (4, 4))

    def test_argb4444_lzss(self):
        pixel = struct.pack("<H", 0xF00F)  # opaque blue
        raw = pixel * 4  # 2x2
        w, h, rgba = E.paa_to_rgba(paa(0x4444, [(2, 2, raw)]), 2)
        self.assertEqual(rgba[0:4], bytes((0, 0, 255, 255)))
        # Shorter than 2x2x2 bytes means LZSS: two literals then a 6-byte back reference.
        lz = bytes([0x03]) + pixel + bytes([2, 3])
        w, h, rgba = E.paa_to_rgba(paa(0x4444, [(2, 2, lz)]), 2)
        self.assertEqual(rgba, bytes((0, 0, 255, 255)) * 4)


class Export(unittest.TestCase):
    def test_pack_from_pbo(self):
        icon = paa(0xFF01, [(4, 4, dxt1_block(0xFFFF, 0xFFFF, [0] * 16))])
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            (d / "game" / "Addons").mkdir(parents=True)
            (d / "game" / "Addons" / "ui.pbo").write_bytes(pbo("a3\\ui_f", [
                ("data\\map\\vehicleicons\\iconMan_ca.paa", icon),
                ("data\\other.paa", icon),
                ("config.bin", b"x" * 10)]))
            rec = d / "rec.jsonl"
            rec.write_text(json.dumps({"type": "entity", "class": "B_Soldier_F", "icon_path": "\\A3\\ui_f\\data\\other.paa"}) + "\n")
            cfg = d / "aar-cfg.json"
            cfg.write_text(json.dumps({"format": "aar-cfg", "vehicles": {"B_Soldier_F": ["Rifleman", "", "iconMan", "BLU_F"]},
                                       "vehicle_icons": {"iconMan": "\\A3\\ui_f\\data\\map\\VehicleIcons\\iconMan_ca"}}))
            out = d / "aar-icons.json"
            E.main([str(d / "game"), "-c", str(cfg), "-r", str(rec), "-o", str(out)])
            pack = json.loads(out.read_text())
            self.assertEqual(pack["format"], "aar-icons")
            self.assertEqual(set(pack["icons"]), {"a3\\ui_f\\data\\map\\vehicleicons\\iconman_ca.paa", "a3\\ui_f\\data\\other.paa"})
            w, h, rgba = decode_png(base64.b64decode(pack["icons"]["a3\\ui_f\\data\\other.paa"].split(",", 1)[1]))
            self.assertEqual((w, h, rgba[:4]), (4, 4, bytes((255, 255, 255, 255))))


if __name__ == "__main__":
    unittest.main()
