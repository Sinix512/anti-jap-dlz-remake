"""TOWN shop-width regression; original files are read-only, no EXE execution."""
import json
from pathlib import Path
import struct
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from extract import town
from tools.prepare_m2 import town_shops


class TownCatalogTest(unittest.TestCase):
    def test_stale_twelve_material_cache_is_bounded_without_deduplication(self):
        data = json.loads((ROOT / "godot/data/m2.json").read_text())
        for record in json.loads((ROOT / "data/town.json").read_text())["towns"]:
            with self.subTest(town=record["index"]):
                stale = dict(record, goods_material=record["goods_material"][:10] + [0, 0])
                before = json.dumps(stale, sort_keys=True)
                built = town_shops(stale, data["items"], data["materials"])
                self.assertEqual([r["index"] for r in built["material"]],
                                 [v for v in record["goods_material"][:10] if v >= 0])
                self.assertEqual([r["index"] for r in built["zahuo"]],
                                 [v for v in record["goods_zahuo"] if v >= 0])
                self.assertEqual(json.dumps(stale, sort_keys=True), before)

    def test_material_width_and_untouched_raw_record(self):
        blob = (ROOT.parent / "dlz/ANTI-JAP/TOWN.DAT").read_bytes()
        for i in range(19):
            with self.subTest(town=i):
                raw = blob[i * 346:(i + 1) * 346]
                parsed = town.parse_record(i, raw)
                expected = list(struct.unpack_from("<10i", raw, 69 * 4))
                self.assertEqual(parsed.goods_material, expected)
                self.assertEqual(parsed.raw_u32, list(struct.unpack_from("<81i", raw)))
                self.assertEqual(len(parsed.goods_junxie), 12)
                self.assertEqual(len(parsed.goods_zahuo), 12)

    def test_generated_catalogs_match_fixed_native_fields(self):
        blob = (ROOT.parent / "dlz/ANTI-JAP/TOWN.DAT").read_bytes()
        cache = json.loads((ROOT / "data/town.json").read_text())["towns"]
        generated = json.loads((ROOT / "godot/data/m2.json").read_text())["towns"]
        for i in range(19):
            raw = blob[i * 346:(i + 1) * 346]
            for name, start, count in [("junxie", 45, 12), ("zahuo", 57, 12), ("material", 69, 10)]:
                with self.subTest(town=i, shop=name):
                    ids = list(struct.unpack_from(f"<{count}i", raw, start * 4))
                    self.assertEqual(cache[i]["goods_" + name], ids)
                    self.assertEqual([r["index"] for r in generated[i]["shops"][name]],
                                     [v for v in ids if v >= 0])


if __name__ == "__main__":
    result = unittest.main(exit=False)
    ok = result.result.wasSuccessful()
    print("TOWN_CATALOG", "PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)
