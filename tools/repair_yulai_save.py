#!/usr/bin/env python3
"""Explicit, backed-up repair of a live L17 Yulai faction incident save.

No default user path, save scanning, automatic migration, healing, or turn rewind.
Embedded checkpoint is read as the pre-incident party membership witness.
"""
from __future__ import annotations

import argparse
import copy
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile

from trigger_data import TRIGGERS

LEGACY_ACTION = {"if": {"when": {"not": {"unit_stage": {"slot": 14, "eq": 0}}},
                         "then": [{"global_set": {"addr": "0x7D1648", "value": 1}}]}}
CRATE_RULES = {r["id"]: r for r in TRIGGERS[17]["rules"] if r["id"].startswith("occupy_")}


def repair_level(level: dict) -> None:
    """Preserve saved dynamic rule state, removing only the recognized bad action."""
    if level.get("index") != 17:
        raise ValueError("Only index17 / 夺取武器 may be repaired")
    found = set()
    for rule in level["triggers"]["rules"]:
        if rule["id"] not in CRATE_RULES:
            continue
        fixed = CRATE_RULES[rule["id"]]
        actions = [a for a in rule["then"] if a != LEGACY_ACTION]
        if actions != fixed["then"]:
            raise ValueError("Unrecognized crate actions: " + rule["id"])
        rule["then"] = actions
        rule["note"] = fixed["note"]
        found.add(rule["id"])
    if found != set(CRATE_RULES):
        raise ValueError("Incomplete five-crate rules")
    for pool in ("units", "slot_pool", "spawn_pool", "reserves"):
        for record in level.get(pool, []):
            if record.get("slot") != 14:
                continue
            record["faction"] = 0
            record["side"] = "player"
            if "auto" in record:
                record["auto"] = not record.get("control", True)


def repair_save(original: dict) -> dict:
    result = copy.deepcopy(original)
    resume = result.get("battle_resume", {})
    snap = resume.get("snapshot", {})
    if (result.get("campaign_index") != 17 or resume.get("standalone", True)
            or snap.get("level", {}).get("index") != 17
            or snap.get("scenario", {}).get("finished", True)
            or snap.get("scenario", {}).get("native_result", 1) != 0
            or snap.get("phase") != "player"):
        raise ValueError("Expected an unfinished campaign L17 player-phase battle save")
    rain = [u for u in snap["level"]["units"] if u.get("slot") == 14]
    if len(rain) != 1 or not rain[0].get("alive") or rain[0].get("hp", 0) <= 0:
        raise ValueError("Yulai must be alive; this repair does not revive units")
    witness = next((m for m in resume.get("checkpoint", {}).get("party", [])
                    if m.get("pid") == 14 and m.get("faction") == 0), None)
    if witness is None:
        raise ValueError("Missing pre-battle friendly-party witness for Yulai")
    for key in ("snapshot", "baseline"):
        state = resume.get(key)
        if not state:
            continue
        repair_level(state["level"])
        flags = state.get("scenario", {}).get("trigger_flags", {})
        for addr in list(flags):
            if addr.lower() == "0x7d1648":
                flags[addr] = 0
    for member in result.get("reserve_members", {}).values():
        if member.get("pid") == 14:
            member["faction"] = 0
    for addr in list(result.get("script_globals", {})):
        if addr.lower() == "0x7d1648":
            result["script_globals"][addr] = 0
    party = result["party"]
    existing = [m for m in party if m.get("pid") == 14]
    if len(existing) > 1:
        raise ValueError("Duplicate Yulai party records")
    if existing:
        existing[0]["faction"] = 0
    else:
        # Reinsert at his prior relative roster position; restore no battle stats.
        prior = resume["checkpoint"]["party"]
        later = [m["pid"] for m in prior[next(i for i, m in enumerate(prior)
                                                   if m["pid"] == 14) + 1:]]
        position = next((i for i, m in enumerate(party) if m["pid"] in later), len(party))
        party.insert(position, copy.deepcopy(witness))
    return result


def repair_file(path: Path) -> dict:
    path = path.resolve(strict=True)
    before = path.read_bytes()
    original = json.loads(before)
    fixed = repair_save(original)
    if fixed == original:
        return {"path": str(path), "changed": False}
    digest = hashlib.sha256(before).hexdigest()
    stamp = datetime.now().strftime("%Y%m%dT%H%M%S%f")
    backup = path.with_name(path.name + ".before-yulai-" + stamp + ".bak")
    # Never alter the source until the complete repair and backup are validated.
    shutil.copy2(path, backup)
    if backup.read_bytes() != before or path.read_bytes() != before:
        raise RuntimeError("Save changed during backup; original not overwritten")
    fd, temporary = tempfile.mkstemp(prefix=path.name + ".repair-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(fixed, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        shutil.copymode(path, temporary)
        if json.loads(Path(temporary).read_text()) != fixed or path.read_bytes() != before:
            raise RuntimeError("Save changed or repaired JSON invalid; original not overwritten")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return {"path": str(path), "changed": True, "backup": str(backup),
            "before_sha256": digest, "after_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "level_index": 17, "turn": fixed["battle_resume"]["snapshot"]["turn"]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("save", type=Path)
    parser.add_argument("--write", action="store_true", help="Back up and atomically replace this explicit save")
    args = parser.parse_args()
    if args.write:
        report = repair_file(args.save)
    else:
        raw = json.loads(args.save.read_text())
        report = {"path": str(args.save.resolve()), "changed": repair_save(raw) != raw,
                  "dry_run": True}
    print(json.dumps(report, ensure_ascii=False, indent=2))
