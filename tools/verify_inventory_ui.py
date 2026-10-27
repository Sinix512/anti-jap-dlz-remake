"""Independent literal indexed-asset audit for 41F935/41F7F9/426A05."""
from pathlib import Path
import json
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ORIGINAL = ROOT.parent / 'dlz' / 'ANTI-JAP'
ASSETS = ROOT / 'godot/assets/ui'
palette = [min(255, b * 4) for b in (ORIGINAL / 'KUANG04.IMG').read_bytes()[-768:]]
lut = json.loads((ROOT / 'extract/research_ui_controls_20261025.json').read_text())['menu13']['selected_background_lut']
checked = 0

def verify(name, width, height, raw):
    global checked
    assert len(raw) == width * height
    expected = bytes(channel for index in raw for channel in (*palette[3*index:3*index+3], 255))
    actual = Image.open(ASSETS / name).convert('RGBA')
    assert actual.size == (width, height), (name, actual.size)
    assert actual.tobytes() == expected, name
    checked += width * height

verify('item_picker_original.png', 304, 227, (ORIGINAL / 'MENU08.IMG').read_bytes()[16:69024])
blob = (ORIGINAL / 'MENU.TGA').read_bytes()
rows = [list(blob[-88*(row+1):len(blob)-88*row]) for row in range(120)]
for count in range(1, 17):
    frame = rows[88:120] if count == 1 else rows[:32] + rows[32:56] * (count-2) + rows[56:88]
    verify(f'choice_{count}_original.png', 88, len(frame), [v for row in frame for v in row])
    if count > 1:
        for selected in range(count):
            raw = [lut[v] for row in frame[8+24*selected:32+24*selected] for v in row[4:84]]
            verify(f'choice_{count}_selected_{selected}.png', 80, 24, raw)
print(f'NATIVE_INVENTORY_UI PASS images=152 pixels={checked}')
