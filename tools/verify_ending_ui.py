"""Independent END/KUANG04, native hidden MENU and JZ image audit.

Expected images use only original IMG/TGA/HZK/ASC bytes and native contracts.
Fixtures are previews, not legal campaign or human-play evidence.
"""
from pathlib import Path
import argparse, json, os, re, subprocess
from PIL import Image
from verify_title_ui import raster, text, wrong
from verify_save_ui import palette
from verify_story_report_ui import layout

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT.parent / 'dlz/ANTI-JAP'
UI = ROOT / 'godot/assets/ui'
OUT = ROOT / 'out/ui_ending'
PAL = palette('KUANG04')


def native_img(name, size, pal):
    return raster((GAME / (name + '.IMG')).read_bytes()[16:16 + size[0] * size[1]], size, pal)


def end_image(index):
    size = (640, 480) if index == 0 else (320, 200)
    part = native_img(f'END{index:02d}', size, PAL)
    if index == 0:
        return part
    image = Image.new('RGBA', (640, 480), (0, 0, 0, 255))
    image.alpha_composite(part, (160, 80))
    return image


def tga_indices(name, width, height):
    raw = (GAME / (name + '.TGA')).read_bytes()
    return b''.join(raw[len(raw) - (row + 1) * width:len(raw) - row * width] for row in range(height))


def expected(entry):
    kind = entry['kind']
    if kind == 'end':
        return end_image(entry['index'])
    if kind == 'fade':
        image = end_image(entry['index'])
        amount = entry['step'] * entry['increment']
        transform = (lambda x: min(x, amount)) if entry['entering'] else (lambda x: max(0, x - amount))
        return Image.merge('RGBA', (*[channel.point(transform) for channel in image.split()[:3]], image.getchannel('A')))
    if kind == 'finale':
        name = f"JZ-{entry['index']}"
        return native_img(name, (640, 480), palette(name))
    image = end_image(0) if entry.get('end_background') else Image.new('RGBA', (640, 480), (0, 0, 0, 255))
    if kind == 'notice':
        image.alpha_composite(raster(tga_indices('FRAME00', 404, 127), (404, 127), PAL, 0), (118, 296))
        value = '由于AA李AA勇的优良表现，可以进入隐藏关，请选择隐藏关的模式。'
        image.alpha_composite(layout(value, '', 46).crop((0, 0, 368, 99)), (142, 312))
        return image
    raw = tga_indices('MENU', 88, 120)
    panel = bytearray(raw[:88 * 32] + raw[88 * 56:88 * 88])
    lut = bytes(json.loads((ROOT / 'extract/research_ui_controls_20261025.json').read_text())['menu13']['selected_background_lut'])
    row = entry['row']
    for y in range(8 + row * 24, 32 + row * 24):
        for x in range(4, 84):
            panel[y * 88 + x] = lut[panel[y * 88 + x]]
    image.alpha_composite(raster(bytes(panel), (88, 64), PAL).crop((0,0,88,62)), (320, 200))
    for i, value in enumerate(('模  拟', '虚  构')):
        text(image, value, 332, 212 + 24 * i, PAL[0xBF if i == row else 0x48])
    return image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--render', action='store_true')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    rows = []
    for i in range(6):
        rows.append(dict(name=f'end_{i:02d}.png', pixels=307200, wrong=wrong(Image.open(UI / f'end_{i:02d}.png'), end_image(i))))
    for i in (1, 2):
        im = expected(dict(kind='finale', index=i))
        rows.append(dict(name=f'jz{i}.png', pixels=307200, wrong=wrong(Image.open(UI / f'jz{i}.png'), im)))
    if args.render:
        proc = subprocess.run([os.environ.get('GODOT_BIN', '/Applications/Godot.app/Contents/MacOS/Godot'), '--path', str(ROOT / 'godot'), '--script', 'res://tests/OriginalEndingQA.gd'], capture_output=True, text=True, timeout=180)
        output = proc.stdout + proc.stderr
        (ROOT / 'out/ending_ui_capture.log').write_text(output)
        if proc.returncode or 'ORIGINAL_ENDING_QA_COMPLETE' not in output or re.search(r'SCRIPT ERROR:|ERROR:|ObjectDB instances were leaked', output):
            print(output)
            return 1
        for name, entry in json.loads((OUT / 'manifest.json').read_text()).items():
            im = expected(entry)
            im.save(OUT / (name + '_expected.png'))
            rows.append(dict(name=name, pixels=307200, wrong=wrong(Image.open(OUT / (name + '.png')), im)))
    (ROOT / 'out/ending_ui_audit.json').write_text(json.dumps(rows, indent=2) + '\n')
    ok = all(row['wrong'] == 0 for row in rows)
    print('ORIGINAL_ENDING_UI' if args.render else 'NATIVE_ENDING_UI', 'PASS' if ok else 'FAIL', json.dumps(rows))
    return 0 if ok else 1


if __name__ == '__main__':
    raise SystemExit(main())
