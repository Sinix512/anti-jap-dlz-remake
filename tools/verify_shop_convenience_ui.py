"""Isolated modern shop UI audit; not an original-pixel equivalence claim.

--render uses a hidden, unfocusable window and offscreen viewport, never the
player's running game. No saves, pointer warps, or original Confirm are used.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = Path(os.environ.get("DLZ_SHOP_EVIDENCE_DIR", ROOT / "out/evidence/shop_convenience295_20261029"))
FIXTURES = {"shop_ready", "shop_selected", "warehouse_selected",
            "warehouse_after_sale", "warehouse_sold_out", "warehouse_page2",
            "material_ready", "material_quantity", "material_no_funds"}


def audit():
    visual = OUT / "visual"
    manifest = json.loads((visual / "manifest.json").read_text())
    assert set(manifest) == FIXTURES, "fixture set"
    frames = {}
    for name, row in manifest.items():
        pixels = np.asarray(Image.open(visual / f"{name}.png").convert("RGB"))
        assert pixels.shape == (480, 640, 3), name
        assert row["modern"], f"{name}: legacy path is not modern UI evidence"
        frames[name] = pixels
        if not row["modal"]:
            footer = pixels[434:]
            assert np.count_nonzero(np.all(footer == (25, 38, 50), axis=2)) > 20000, name
            for y, color in [(438, (242, 215, 138)), (460, (229, 237, 244))]:
                glyphs = np.all(np.abs(pixels[y:y+18].astype(int) - color) <= 1, axis=2)
                assert np.count_nonzero(glyphs) > 100, f"{name}: footer row {y}"
    selected = manifest["shop_selected"]
    assert selected["pending"] and not manifest["shop_ready"]["pending"], "persistent click selection"
    assert manifest["warehouse_selected"]["pending"] and not manifest["warehouse_page2"]["pending"], "paging clears source"
    selected, after_sale, sold_out = (manifest[n] for n in
                                    ("warehouse_selected", "warehouse_after_sale", "warehouse_sold_out"))
    assert selected["warehouse_iid0"] == 3 and after_sale["warehouse_iid0"] == 2 and sold_out["warehouse_iid0"] == 0
    assert int(after_sale["pending"]["id"]) == 0 and not sold_out["pending"], "continuous sell source retention/exhaustion"
    assert after_sale["money"] > selected["money"] and sold_out["money"] - selected["money"] == 3 * (after_sale["money"] - selected["money"])
    changed = np.any(frames["shop_selected"] != frames["shop_ready"], axis=2)
    allowed = np.zeros((480, 640), dtype=bool)
    allowed[30:128, 22:74] = True  # first goods outline, independently fixed layout
    allowed[434:] = True
    outside = int(np.count_nonzero(changed & ~allowed))
    assert outside == 0, f"selection touched unrelated UI: {outside}"
    border = np.zeros((480, 640), dtype=bool)
    border[30, 22:74] = border[127, 22:74] = True
    border[30:128, 22] = border[30:128, 73] = True
    assert np.count_nonzero(changed & border) >= 290, "selection outline missing"
    for name in ("material_quantity", "material_no_funds"):
        q = manifest[name]["quantity"]
        assert q["contents_fit"] and q["size"] == q["dimmer_size"] == [640, 480], name
        assert "总价" in q["total"] and ("余额" in q["balance"] or "资金不足" in q["balance"]), name
    q = manifest["material_quantity"]["quantity"]
    assert q["value"] == 1 and q["maximum"] == 1000 // q["price"] and not q["buy_disabled"]
    q = manifest["material_no_funds"]["quantity"]
    assert q["value"] == q["maximum"] == 0 and q["buy_disabled"] and "资金不足" in q["balance"]
    base, modal = frames["material_ready"], frames["material_quantity"]
    background = np.ones((480, 640), dtype=bool)
    background[112:368, 140:500] = False
    dimmed = np.any(base != modal, axis=2) & background
    assert np.count_nonzero(dimmed) > 100000, "modal dimmer does not cover campaign host"
    assert np.all(modal[background].astype(int) <= base[background].astype(int) + 1), "modal brightened background"
    report = {"ok": True, "fixtures": len(frames), "selection_outside_changes": outside,
              "dimmed_background_pixels": int(np.count_nonzero(dimmed)),
              "screenshots": {n: hashlib.sha256((visual / f"{n}.png").read_bytes()).hexdigest()
                              for n in sorted(frames)}}
    (OUT / "visual_audit.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--render", action="store_true")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    if args.render:
        command = [os.environ.get("GODOT_BIN", "/Applications/Godot.app/Contents/MacOS/Godot"),
                   "--path", str(ROOT / "godot"), "--audio-driver", "Dummy", "--resolution", "640x480",
                   "--log-file", str(OUT / "visual_engine.log"),
                   "--script", "res://tests/ShopConvenienceQA.gd"]
        proc = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=180)
        output = proc.stdout + proc.stderr
        (OUT / "visual_run.log").write_text(output)
        if proc.returncode or "SHOP_CONVENIENCE_QA_OK fixtures=9" not in output or re.search(
                r"SCRIPT ERROR:|ERROR:|ObjectDB instances were leaked", output):
            print(output)
            return 1
    report = audit()
    print("SHOP_CONVENIENCE_UI PASS", json.dumps(report))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
