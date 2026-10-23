#!/usr/bin/env python3
"""Dump the 47 per-level trigger functions in DLZ.exe (table 0x446510).

Analysis-only tool: requires capstone + pefile (not needed to run the game).

    python3 tools/trigger_dump.py --check
    python3 tools/trigger_dump.py --out out/triggers

Outputs:
* out/triggers/trigger_dump.json  machine-readable facts for every level
* out/triggers/asm/LXX.asm        annotated disassembly
* stdout                         one line per level + call/helper summary

The function body is found by recursive-descent disassembly from the table
entry, not by "next table entry": the init-function table (0x4465D0) lives
between trigger entries L39 and L40, so address gaps overstate body sizes.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_EXE = ROOT.parent / "dlz" / "ANTI-JAP" / "DLZ.exe"
TABLE_VA = 0x446510
ENTRY_COUNT = 47

# Fighter struct base: dest_x at +0, stage at +0x1C.
FIGHTER_BASE = 0x96AB90
FIGHTER_STRIDE = 64
FIGHTER_FIELDS = {
    0x00: "pad0",
    0x04: "tili",
    0x08: "unknown_08",
    0x0C: "unknown_0c",
    0x10: "unknown_10",
    0x14: "x",
    0x18: "y",
    0x1C: "stage",
    0x1D: "behavior",
    0x20: "dest_x",
    0x24: "dest_y",
    0x28: "dest_direction",
    0x2C: "target_slot",
    0x30: "target_x",
    0x34: "target_y",
    0x3C: "stage",
    0x3D: "behavior",
    0x3E: "pad3e",
}

HELPERS = {
    0x43DD47: "sound",
    0x429CC8: "spawn",
    0x429BED: "remove",
    0x4299B2: "adjacent",
    0x426810: "area",
    0x406C30: "all_units_dead",
    0x406C8C: "any_unit_dead",
    0x40B40E: "count_slots_40_127_nonzero",
    0x42AFD2: "helper_42afd2",
    0x426E7D: "helper_426e7d",
}

# Globals that carry useful meaning to a reader/translator.
GLOBALS = {
    0x7D50F8: "battle_result",
    0x475AA4: "turn",
    0x7D0484: "score",
    0x7D19E4: "dialog_result?",
    0x7D1A68: "flag_7d1a68",
    0x7D06B8: "mode_7d06b8",
    0x57BA20: "map_w",
    0x57BA22: "map_h",
    0x583F10: "flag_583f10",
    0x98F248: "timeGetTime?",
}


def _require_deps():
    try:
        import capstone  # noqa: F401
        import pefile  # noqa: F401
    except ImportError:
        sys.exit("需要 capstone 与 pefile：python3 -m pip install --user capstone pefile")


def _fmt_addr(value: int) -> str:
    return f"0x{value:08X}"


class Image:
    def __init__(self, path: Path):
        import pefile

        self.pe = pefile.PE(str(path), fast_load=True)
        self.base = self.pe.OPTIONAL_HEADER.ImageBase
        self.text = self.pe.sections[0]
        self.lo = self.base + self.text.VirtualAddress
        self.hi = self.lo + self.text.Misc_VirtualSize
        self.raw_lo = self.lo
        self.raw_hi = self.lo + self.text.SizeOfRawData

    def read_va(self, va: int, size: int) -> bytes:
        rva = va - self.base
        return self.pe.get_data(rva, size)

    def dword(self, va: int) -> int:
        raw = self.read_va(va, 4)
        return struct.unpack("<I", raw)[0] if len(raw) == 4 else 0


class Disassembler:
    def __init__(self, image: Image):
        from capstone import CS_ARCH_X86, CS_MODE_32, Cs

        self.image = image
        self.md = Cs(CS_ARCH_X86, CS_MODE_32)
        self.md.detail = True

    def _at(self, va: int):
        raw = self.image.read_va(va, 16)
        if not raw:
            return None
        return next(self.md.disasm(raw, va), None)

    def function(self, entry: int) -> dict[int, object]:
        """Recursive descent from entry; stops each path at ret/jmp-out."""
        seen: dict[int, object] = {}
        work = [entry]
        while work:
            va = work.pop()
            while self.image.lo <= va < self.image.hi and va not in seen:
                ins = self._at(va)
                if ins is None:
                    break
                seen[va] = ins
                last = va + ins.size
                if ins.mnemonic.startswith("ret"):
                    break
                if ins.mnemonic == "jmp":
                    if ins.op_str.startswith("0x"):
                        va = int(ins.op_str, 16)
                        continue
                    target = self._switch_targets(ins)
                    work.extend(target)
                    break
                if ins.mnemonic.startswith("j"):
                    if ins.op_str.startswith("0x"):
                        target = int(ins.op_str, 16)
                        if self.image.lo <= target < self.image.hi:
                            work.append(target)
                    va = last
                    continue
                if ins.mnemonic in ("int3", "hlt", "ud2"):
                    break
                va = last
        return seen

    def _switch_targets(self, ins) -> list[int]:
        """Follow `jmp dword ptr [reg*4 + table]` tables inside .text."""
        if not ins.operands:
            return []
        mem = ins.operands[0].mem
        if mem.index == 0 or mem.scale != 4 or mem.disp == 0:
            return []
        out = []
        for i in range(256):
            target = self.image.dword(mem.disp + i * 4)
            if not (self.image.lo <= target < self.image.hi):
                break
            out.append(target)
        return out


def _signed32(value: int) -> int:
    return value - 0x100000000 if value & 0x80000000 else value


def annotate_operand(ins) -> str:
    """Instruction text with a few domain annotations appended."""
    notes = []
    try:
        for op in ins.operands:
            if op.type == 3:  # X86_OP_MEM
                mem = op.mem
                addr = mem.disp
                if mem.base == 0 and mem.index == 0:
                    notes.extend(_annotate_abs(addr))
                elif mem.base == 0 and mem.index != 0:
                    notes.append(f"table@{_fmt_addr(addr)}")
    except Exception:
        pass
    text = f"{ins.mnemonic:<7}{ins.op_str}"
    if notes:
        text += "    ; " + " ".join(dict.fromkeys(notes))
    return text


def _annotate_abs(addr: int) -> list[str]:
    notes = []
    if addr in HELPERS:
        notes.append(f"helper:{HELPERS[addr]}")
    if addr in GLOBALS:
        notes.append(GLOBALS[addr])
    off = addr - FIGHTER_BASE
    if 0 <= off < 128 * FIGHTER_STRIDE:
        slot, field = divmod(off, FIGHTER_STRIDE)
        name = FIGHTER_FIELDS.get(field)
        if name:
            notes.append(f"Fighter[{slot}].{name}")
        else:
            notes.append(f"Fighter[{slot}]+0x{field:X}")
    if 0x583F00 <= addr < 0x584000:
        notes.append(f"flag_{addr:06x}")
    if 0x472000 <= addr < 0x476000:
        notes.append(f"sndvar_{addr:06x}")
    if 0x57BF00 <= addr < 0x57C000:
        notes.append(f"mapcell_{addr:06x}")
    return notes


def _imm_args(insns: list, call_index: int) -> list:
    """Recover simple immediate args pushed right before a call."""
    args = []
    i = call_index - 1
    while i >= 0:
        ins = insns[i]
        if ins.mnemonic == "push":
            op = ins.op_str
            if op.startswith("0x") or op.lstrip("-").isdigit():
                args.append(int(op, 16) if op.startswith("0x") else int(op))
            elif "[" in op:
                args.append(op)
            else:
                args.append(f"<{op}>")
        elif ins.mnemonic == "add" and ins.op_str.replace(" ", "") == "esp,4":
            break
        elif ins.mnemonic in ("call", "ret"):
            break
        i -= 1
    return list(reversed(args))


def summarize(level: int, entry: int, seen: dict[int, object]) -> dict:
    insns = [seen[a] for a in sorted(seen)]
    max_end = max(addr + seen[addr].size for addr in seen)
    calls = []
    for i, ins in enumerate(insns):
        if ins.mnemonic == "call" and ins.op_str.startswith("0x"):
            target = int(ins.op_str, 16)
            calls.append({
                "addr": _fmt_addr(ins.address),
                "target": _fmt_addr(target),
                "name": HELPERS.get(target, ""),
                "args": _imm_args(insns, i),
            })
    by_name = defaultdict(list)
    for c in calls:
        if c["name"]:
            by_name[c["name"]].append(c["args"])
    return {
        "level": level,
        "entry": _fmt_addr(entry),
        "end": _fmt_addr(max_end),
        "size": max_end - entry,
        "instruction_count": len(insns),
        "calls": calls,
        "helpers": dict(by_name),
        "text": [f"{ins.address:08x}  {annotate_operand(ins)}" for ins in insns],
    }


def _load_table(image: Image) -> list[int]:
    raw = image.read_va(TABLE_VA, ENTRY_COUNT * 4)
    entries = list(struct.unpack(f"<{ENTRY_COUNT}I", raw))
    if not all(entries):
        raise SystemExit("0x446510 表有空项")
    if entries != sorted(entries):
        raise SystemExit("0x446510 表不是按地址升序")
    return entries


KNOWN_FIVE = {
    0: 0x408D28,
    3: 0x409107,
    12: 0x40995B,
    18: 0x40A0BA,
    36: 0x40B2CF,
}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--exe", type=Path, default=DEFAULT_EXE)
    ap.add_argument("--out", type=Path, default=ROOT / "out" / "triggers")
    ap.add_argument("--level", type=int, default=None)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    _require_deps()
    if not args.exe.exists():
        sys.exit(f"找不到 {args.exe}")

    image = Image(args.exe)
    dis = Disassembler(image)
    entries = _load_table(image)
    levels = [args.level] if args.level is not None else list(range(ENTRY_COUNT))

    if args.check:
        for level, expected in KNOWN_FIVE.items():
            if entries[level] != expected:
                raise SystemExit(f"L{level:02d} 入口 {entries[level]:08x} != {expected:08x}")
        # trigger_data.py 的 47 个 entry 必须逐项对上表，防止抄错地址。
        from trigger_data import TRIGGERS
        if sorted(TRIGGERS) != list(range(ENTRY_COUNT)):
            raise SystemExit("trigger_data.py 不是 47 关")
        for level, data in TRIGGERS.items():
            got = int(str(data["entry"]), 16)
            if got != entries[level]:
                raise SystemExit(
                    f"L{level:02d} trigger_data {got:08x} != 表 {entries[level]:08x}")
        print("TABLE_OK 47 entries, 5 known entries, trigger_data 47/47 match")

    asm_dir = args.out / "asm"
    asm_dir.mkdir(parents=True, exist_ok=True)
    all_facts = []
    for level in levels:
        entry = entries[level]
        seen = dis.function(entry)
        facts = summarize(level, entry, seen)
        all_facts.append(facts)
        (asm_dir / f"L{level:02d}.asm").write_text("\n".join(facts["text"]) + "\n")
        print(f"L{level:02d} {facts['entry']} size={facts['size']:#06x} "
              f"ins={facts['instruction_count']:<4} "
              f"spawn={len(facts['helpers'].get('spawn', []))} "
              f"remove={len(facts['helpers'].get('remove', []))} "
              f"area={len(facts['helpers'].get('area', []))} "
              f"adj={len(facts['helpers'].get('adjacent', []))} "
              f"dead={len(facts['helpers'].get('all_units_dead', []))}/"
              f"{len(facts['helpers'].get('any_unit_dead', []))}")

    payload = {
        "meta": {
            "source": args.exe.name,
            "table": _fmt_addr(TABLE_VA),
            "image_base": _fmt_addr(image.base),
            "entry_count": len(entries),
            "note": "function body via recursive descent; NOT next-table-entry span",
        },
        "entries": entries,
        "levels": all_facts,
    }
    out_json = args.out / "trigger_dump.json"
    out_json.write_text(json.dumps(payload, ensure_ascii=False, indent=1))
    total = sum(f["size"] for f in all_facts)
    print(f"wrote {out_json} ({out_json.stat().st_size} B), total size {total:#x}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
