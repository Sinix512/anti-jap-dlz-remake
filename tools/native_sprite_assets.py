"""Decode shared-palette DAT sprites from source, never stale out/ previews."""
from pathlib import Path
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from extract import sprites, palette

GAME = ROOT.parent / "dlz" / "ANTI-JAP"
ASSETS = ROOT / "godot" / "assets"
NAMES = ("face", "army", "goods", "material", "mine", "flm")


def generate(names=NAMES):
    pal = palette.global_palette(GAME)
    for name in names:
        bank = sprites.BANK_BY_NAME[name]
        blob = sprites.load_bank(GAME, bank)
        directory = ASSETS / name
        directory.mkdir(parents=True, exist_ok=True)
        for index in range(bank.groups):
            path = directory / f"{name}_{index:0{2 if name == 'material' else 3}d}.png"
            image = (sprites.group_sheet(blob, bank, index, pal)
                     if bank.group_size > 1 else
                     sprites.frame_rgba(sprites.frame_bytes(blob, bank, index), bank, pal))
            image.save(path)


def audit():
    """All visible pixels and transparent alpha, not a few palette samples."""
    import numpy as np
    from PIL import Image
    pal = np.frombuffer(palette.global_palette(GAME), dtype=np.uint8).reshape(256, 3)
    report = []
    for name in NAMES:
        bank = sprites.BANK_BY_NAME[name]
        raw = np.frombuffer(sprites.load_bank(GAME, bank), dtype=np.uint8)
        failures = 0
        pixels = 0
        for group in range(bank.groups):
            path = ASSETS / name / f"{name}_{group:0{2 if name == 'material' else 3}d}.png"
            actual = np.array(Image.open(path).convert("RGBA"))
            indices = raw[group * bank.group_size * bank.frame_bytes:
                          (group + 1) * bank.group_size * bank.frame_bytes]
            indices = indices.reshape(bank.group_size, bank.frame_h, bank.frame_w).transpose(1, 0, 2)
            indices = indices.reshape(bank.frame_h, bank.group_size * bank.frame_w)
            if actual.shape[:2] != indices.shape:
                failures += indices.size
                continue
            opaque = (indices != 0) if bank.transparent else np.ones(indices.shape, dtype=bool)
            wrong = np.any(actual[:, :, :3] != pal[indices], axis=2) & opaque
            wrong |= actual[:, :, 3] != np.where(opaque, 255, 0)
            failures += int(np.sum(wrong))
            pixels += indices.size
        report.append(dict(bank=name, groups=bank.groups, frames=bank.count,
                           pixels=pixels, wrong_pixels=failures))
    output = ROOT / "out" / "native_sprite_palette_audit.json"
    output.write_text(json.dumps(report, indent=2) + "\n")
    ok = all(row["wrong_pixels"] == 0 for row in report)
    print("NATIVE_SPRITE_PALETTE", "PASS" if ok else "FAIL", json.dumps(report))
    return 0 if ok else 1


if __name__ == "__main__":
    if "--audit" in sys.argv:
        raise SystemExit(audit())
    generate()
