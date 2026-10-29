import copy
import json
from pathlib import Path
import tempfile
import unittest

from repair_yulai_save import CRATE_RULES, LEGACY_ACTION, repair_file, repair_save


def fixture():
    rules = copy.deepcopy(list(CRATE_RULES.values()))
    for rule in rules:
        rule["then"].insert(1, copy.deepcopy(LEGACY_ACTION))
        rule["note"] = "legacy"
    rain = {"slot": 14, "pid": 14, "side": "enemy", "faction": 1, "alive": True,
            "auto": False, "control": True, "hp": 126, "max_hp": 337, "xp": 56,
            "acted": False, "x": 24, "y": 6, "morale": 88, "item_slots": [98, 51, 0]}
    friend = {"slot": 13, "faction": 0, "hp": 197}
    level = {"index": 17, "triggers": {"rules": rules}, "units": [friend, rain],
             "slot_pool": [copy.deepcopy(rain)], "spawn_pool": [copy.deepcopy(rain)]}
    snap = {"level": level, "turn": 6, "phase": "player", "rng_state": 12345,
            "scenario": {"finished": False, "native_result": 0, "collected": 1,
                         "trigger_flags": {"0x7d1648": 1, "0x583f18": 1}},
            "log_history": ["original history"], "stats": {"kills": 2}}
    witness = {"pid": 14, "faction": 0, "hp": 337, "xp": 40, "item_slots": [98, 51, 0]}
    return {"campaign_index": 17, "money": 1234, "saved_at": "unchanged",
            "party": [{"pid": 13, "faction": 0}, {"pid": 15, "faction": 0}],
            "reserve_members": {"14": {"pid": 14, "faction": 0, "hp": 0}},
            "battle_resume": {"snapshot": snap, "baseline": copy.deepcopy(snap),
                              "standalone": False, "deploy": [0, 13, 14],
                              "checkpoint": {"party": [{"pid": 13, "faction": 0}, witness,
                                                        {"pid": 15, "faction": 0}]}}}


class RepairYulaiSaveTest(unittest.TestCase):
    def test_minimal_recovery(self):
        before = fixture()
        preserved = copy.deepcopy(before)
        fixed = repair_save(before)
        self.assertEqual(before, preserved, "pure repair must not mutate input")
        self.assertEqual([m["pid"] for m in fixed["party"]], [13, 14, 15])
        self.assertEqual(fixed["party"][1], before["battle_resume"]["checkpoint"]["party"][1])
        for key in ("snapshot", "baseline"):
            old = before["battle_resume"][key]
            new = fixed["battle_resume"][key]
            self.assertEqual({k: v for k, v in old.items() if k not in ("level", "scenario")},
                             {k: v for k, v in new.items() if k not in ("level", "scenario")})
            for pool in ("units", "slot_pool", "spawn_pool"):
                for a, b in zip(old["level"][pool], new["level"][pool]):
                    if a["slot"] != 14:
                        self.assertEqual(a, b)
                        continue
                    self.assertEqual(b["side"], "player")
                    self.assertEqual(b["faction"], 0)
                    self.assertEqual({k: v for k, v in a.items() if k not in ("side", "faction")},
                                     {k: v for k, v in b.items() if k not in ("side", "faction")})
            self.assertEqual(new["scenario"]["trigger_flags"], {"0x7d1648": 0, "0x583f18": 1})
            self.assertEqual(new["level"]["triggers"]["rules"], list(CRATE_RULES.values()))
        for key in before.keys() - {"party", "battle_resume"}:
            self.assertEqual(before[key], fixed[key])
        self.assertEqual(before["battle_resume"]["checkpoint"], fixed["battle_resume"]["checkpoint"])
        self.assertEqual(repair_save(fixed), fixed, "second repair is a no-op")

    def test_reject_wrong_or_unsafe_save(self):
        cases = []
        d = fixture(); d["campaign_index"] = 16; cases.append(d)
        d = fixture(); d["battle_resume"]["snapshot"]["level"]["index"] = 16; cases.append(d)
        d = fixture(); d["battle_resume"]["standalone"] = True; cases.append(d)
        d = fixture(); d["battle_resume"]["snapshot"]["scenario"]["finished"] = True; cases.append(d)
        d = fixture(); d["battle_resume"]["snapshot"]["scenario"]["native_result"] = 1; cases.append(d)
        d = fixture(); d["battle_resume"]["snapshot"]["phase"] = "enemy"; cases.append(d)
        d = fixture(); d["battle_resume"]["snapshot"]["level"]["units"][1]["hp"] = 0; cases.append(d)
        d = fixture(); d["battle_resume"]["checkpoint"]["party"].pop(1); cases.append(d)
        d = fixture(); d["battle_resume"]["snapshot"]["level"]["triggers"]["rules"].pop(); cases.append(d)
        d = fixture(); d["battle_resume"]["snapshot"]["level"]["triggers"]["rules"][0]["then"].append({"money": 3}); cases.append(d)
        for d in cases:
            with self.subTest(save=d), self.assertRaises(ValueError):
                repair_save(d)

    def test_backup_exact_and_idempotent_file_write(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "explicit.json"
            raw = json.dumps(fixture()).encode()
            path.write_bytes(raw)
            report = repair_file(path)
            self.assertTrue(report["changed"])
            self.assertEqual(Path(report["backup"]).read_bytes(), raw)
            self.assertEqual(json.loads(path.read_bytes()), repair_save(json.loads(raw)))
            after = path.read_bytes()
            self.assertFalse(repair_file(path)["changed"])
            self.assertEqual(path.read_bytes(), after)
            self.assertEqual(len(list(Path(temporary).glob("*.bak"))), 1)


if __name__ == "__main__":
    unittest.main()
