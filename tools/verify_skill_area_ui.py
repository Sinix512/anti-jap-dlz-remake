"""Render isolated strategy aim fixtures without showing/focusing a game window."""
from pathlib import Path
import argparse
import json
import os
import re
import subprocess

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "out/evidence/strategy_preview_20261029"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--render", action="store_true")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    if args.render:
        command = [os.environ.get("GODOT_BIN", "/Applications/Godot.app/Contents/MacOS/Godot"),
                   "--path", str(ROOT / "godot"), "--audio-driver", "Dummy", "--resolution", "640x480",
                   "--log-file", str(OUT / "visual_engine.log"),
                   "--script", "res://tests/SkillAreaPresentationQA.gd"]
        proc = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=180)
        output = proc.stdout + proc.stderr
        (OUT / "visual_run.log").write_text(output)
        if proc.returncode or "SKILL_AREA_PRESENTATION_QA_OK fixtures=4" not in output or re.search(
                r"SCRIPT ERROR:|ERROR:|ObjectDB instances were leaked", output):
            print(output)
            return 1
    visual = OUT / "visual"
    manifest = json.loads((visual / "manifest.json").read_text())
    assert set(manifest) == {"fire_normal", "supply_normal", "fire_full", "fire_edge"}
    rows = []
    chances = set()
    for name, fixture in manifest.items():
        actual = np.asarray(Image.open(visual / (name + ".png")).convert("RGB"))
        base = np.asarray(Image.open(visual / (name + "_base.png")).convert("RGB"))
        assert actual.shape == base.shape == (480, 640, 3), name
        changed = np.any(actual != base, axis=2)
        x, y, width, height = map(int, fixture["map_rect"])
        permitted = np.zeros((480, 640), dtype=bool)
        permitted[y:y+height, x:x+width] = True
        outside = int(np.count_nonzero(changed & ~permitted))
        visible_cells = 0
        missing_cells = []
        for cell in fixture["cells"]:
            chances.add(int(cell["chance"]))
            cx, cy = map(int, cell["screen"])
            if cx < x or cy < y or cx+48 > x+width or cy+48 > y+height:
                continue
            visible_cells += 1
            patch = changed[cy+2:cy+46, cx+2:cx+46]
            # Both valid/invalid cells must visibly shade, with readable digits.
            text_color = (255, 235, 166) if cell["effective"] else (219, 224, 230)
            # Normalized float colors can quantize one byte differently by GPU.
            glyphs = np.all(np.abs(actual[cy+1:cy+21, cx+1:cx+43].astype(int) - text_color) <= 1, axis=2)
            glyphs &= changed[cy+1:cy+21, cx+1:cx+43]
            if np.count_nonzero(patch) < 500 or np.count_nonzero(glyphs) < 5:
                missing_cells.append(cell["tile"])
        rows.append({"fixture": name, "outside_map_changes": outside,
                     "visible_cells": visible_cells, "missing_cells": missing_cells})
    ok = chances >= {0, 30, 50, 100} and all(
        r["outside_map_changes"] == 0 and r["visible_cells"] and not r["missing_cells"] for r in rows)
    (OUT / "visual_audit.json").write_text(json.dumps(rows, indent=2) + "\n")
    print("SKILL_AREA_UI", "PASS" if ok else "FAIL", json.dumps(rows))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
