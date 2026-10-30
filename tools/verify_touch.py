#!/usr/bin/env python3
"""Run isolated touch/desktop regressions, not a campaign or player-save test."""
from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import time
from zoneinfo import ZoneInfo

from build_android import detect_godot, public_path

ROOT = Path(__file__).resolve().parents[1]
TOUCH = {
    "TouchBattleTest": "TOUCH_BATTLE PASS",
    "TouchUiTest": "TOUCH_UI PASS",
}
DESKTOP = {
    "DesktopTouchOptInTest": "DESKTOP_TOUCH_OPT_IN PASS",
    "ScriptCheck": "SCRIPT_CHECK failures=0",
    "OriginalUIInputTest": "ORIGINAL_UI_INPUT checks=32 failures=0",
    "OriginalTitlePagesTest": "ORIGINAL_TITLE_PAGES checks=38 failures=0",
    "OriginalStoryReportTest": "ORIGINAL_STORY_REPORT PASS",
    "ModalEntryInputTest": "MODAL_ENTRY_INPUT PASS",
    "ShopQuantityTest": "SHOP_QUANTITY PASS",
    "ShopConvenienceTest": "SHOP_CONVENIENCE_OK",
    "OriginalToolbarTest": "ORIGINAL_TOOLBAR checks=44 failures=0",
    "OriginalCombatTest": "ORIGINAL_COMBAT checks=56 failures=0",
    "OriginalRangeMaskTest": "ORIGINAL_RANGE_MASK_OK",
    "AttackAreaPresentationTest": "ATTACK_AREA_PRESENTATION_OK",
    "SkillAreaPresentationTest": "SKILL_AREA_PRESENTATION_OK",
}


def fingerprint() -> str:
    paths = [ROOT / "godot/project.godot"]
    for folder in ("godot/scripts", "godot/tests", "godot/data"):
        paths.extend(p for p in (ROOT / folder).rglob("*") if p.suffix in {".gd", ".json"})
    digest = hashlib.sha256()
    for path in sorted(paths):
        digest.update(str(path.relative_to(ROOT)).encode() + b"\0" + path.read_bytes())
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", help="Godot executable (or GODOT_BIN/GODOT/PATH)")
    parser.add_argument("--suite", choices=("all", "touch", "desktop"), default="all")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        godot = detect_godot(args.godot)
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        parser.error(str(error))
    stamp = datetime.now(ZoneInfo("Asia/Bangkok")).strftime("%Y%m%d_%H%M%S")
    output = (args.output or ROOT / "out/evidence" / ("touch_" + stamp)).resolve()
    output.mkdir(parents=True, exist_ok=True)
    before = fingerprint()
    rows = []
    for mobile, tests in ((True, TOUCH), (False, DESKTOP)):
        if args.suite == ("desktop" if mobile else "touch"):
            continue
        for name, marker in tests.items():
            command = [str(godot), "--headless", "--path", str(ROOT / "godot"),
                       "--log-file", str(output / (name + ".godot.log")),
                       "--script", "res://tests/" + name + ".gd"]
            if mobile:
                command += ["--", "--touch-ui"]
            start = time.monotonic()
            try:
                result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=150)
                stdout, stderr, code = result.stdout, result.stderr, result.returncode
            except subprocess.TimeoutExpired as error:
                stdout = error.stdout or b""
                stderr = error.stderr or b""
                stdout = stdout.decode(errors="replace") if isinstance(stdout, bytes) else stdout
                stderr = stderr.decode(errors="replace") if isinstance(stderr, bytes) else stderr
                code = -1
            (output / (name + ".stdout.log")).write_text(stdout)
            (output / (name + ".stderr.log")).write_text(stderr)
            diagnostics = any(text in stdout + stderr for text in (
                "SCRIPT ERROR", "Parse Error", "Assertion failed", "Failed to load script"))
            row = {"test": name, "touch_mode": mobile, "exit": code,
                   "marker_found": marker in stdout, "runtime_error": diagnostics,
                   "seconds": round(time.monotonic() - start, 2)}
            row["passed"] = code == 0 and row["marker_found"] and not diagnostics
            rows.append(row)
            print(json.dumps(row), flush=True)
    after = fingerprint()
    passed = bool(rows) and all(row["passed"] for row in rows) and before == after
    report = {"scope": "isolated touch and desktop fixtures; no campaign completion claim",
              "before_sha256": before, "after_sha256": after,
              "source_unchanged_during_run": before == after, "passed": passed, "tests": rows}
    (output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"{'PASS' if passed else 'FAIL'}: {sum(row['passed'] for row in rows)}/{len(rows)}; {public_path(output)}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
