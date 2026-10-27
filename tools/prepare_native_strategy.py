"""Source-index strategic UI assets. Called by prepare_m3; originals read-only."""
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ORIGINAL = ROOT.parent / "dlz/ANTI-JAP"
UI = ROOT / "godot/assets/ui"


def prepare():
    palettes = json.loads((ROOT / "godot/data/native_ui_palettes.json").read_text())
    def image(raw, size, name, palette, key=None):
        im = Image.frombytes("P", size, raw)
        im.putpalette(palette)
        im = im.convert("RGBA")
        if key is not None:
            im.putalpha(Image.frombytes("L", size, bytes(0 if v == key else 255 for v in raw)))
        im.save(UI / name)
    for name in ("BIGMAP", "K00", "BACK19"):
        image((ORIGINAL / (name+".IMG")).read_bytes()[16:16+640*480], (640,480), "strategy_"+name.lower()+".png", palettes[name])
    place = (ORIGINAL / "PLACE.DAT").read_bytes()
    for i in range(19):
        image(place[i*0x4B400:i*0x4B400+0x4B000], (640,480), f"strategy_place{i:02d}.png", palettes[f"PLACE{i:02d}"])
    for i in range(2):
        image((ORIGINAL / f"BIGMINE{i}.IMG").read_bytes()[16:16+70*81], (70,81), f"strategy_mine{i}.png", palettes["BIGMAP"], 0x83)
        image((ORIGINAL / f"BUTTON{i}.IMG").read_bytes()[16:16+50*25], (50,25), f"strategy_button{i}.png", palettes["K00"])
    # Service screens share source indices with their caller's live palette.
    for name in ("K01", "K03", "K04"):
        (UI / f"service_{name.lower()}_indices.bin").write_bytes((ORIGINAL / (name+".IMG")).read_bytes()[16:16+640*480])
    for i in range(14):
        size = (50,25) if i < 2 else ((48,44) if i < 10 else (35,19))
        (UI / f"service_button{i}_indices.bin").write_bytes((ORIGINAL / f"BUTTON{i}.IMG").read_bytes()[16:16+size[0]*size[1]])
    for name in ("MINE", "MATERIAL", "GOODS"):
        (UI / f"service_{name.lower()}_indices.bin").write_bytes((ORIGINAL / (name+".DAT")).read_bytes())
    army = (ORIGINAL / "ARMY.DAT").read_bytes()
    (UI / "service_army_indices.bin").write_bytes(b"".join(army[i*19*2304:i*19*2304+2304] for i in range(91)))
    for name in ("ASC16", "HZK16"):
        (UI / f"service_{name.lower()}.bin").write_bytes((ORIGINAL / name).read_bytes())
    # 424B31 -> 424D4F -> 421F68/421D10; fixed KUANG04, not the caller palette.
    colors = [palettes["KUANG04"][i*3:i*3+3] for i in range(256)]
    lut = []
    for rgb in colors:
        target = [v//2 for v in rgb]
        scores = [sum(w*(a-b)**2 for w,a,b in zip((30,59,11),target,c))//100 for c in colors]
        lut.append(min(range(256), key=lambda i: scores[i]))
    (UI / "service_quantity_lut.bin").write_bytes(bytes(lut))
    (UI / "menu10_indices.bin").write_bytes((ORIGINAL / "MENU10.IMG").read_bytes()[16:16+640*480])
    (UI / "bg02_indices.bin").write_bytes((ORIGINAL / "BG02.IMG").read_bytes()[16:16+640*480])
    (UI / "menu03_indices.bin").write_bytes((ORIGINAL / "MENU03.IMG").read_bytes()[16:16+128*88])
    blob = (ORIGINAL / "MENU.TGA").read_bytes()
    raw = b"".join(blob[len(blob)-(r+1)*88:len(blob)-r*88] for r in range(120))
    for count in range(1,17):
        raster = raw[88*88:] if count==1 else raw[:32*88]+raw[32*88:56*88]*(count-2)+raw[56*88:88*88]
        (UI / f"choice_{count}_indices.bin").write_bytes(raster)
    controls = json.loads((ROOT / "extract/research_ui_controls_20261025.json").read_text())
    (UI / "native_menu_lut.bin").write_bytes(bytes(controls["menu13"]["selected_background_lut"]))
    faces = (ORIGINAL / "FACE.DAT").read_bytes()
    (UI / "face_indices.bin").write_bytes(faces)
    blob = (ORIGINAL / "FRAME00.TGA").read_bytes()
    (UI / "frame00_indices.bin").write_bytes(b"".join(blob[len(blob)-(r+1)*404:len(blob)-r*404] for r in range(127)))
    armies = (ORIGINAL / "ARMY.DAT").read_bytes()
    m2 = json.loads((ROOT / "godot/data/m2.json").read_text())
    for i in sorted({int(v["img_index"]) for v in m2["units"].values()}):
        start = i*19*48*48
        image(armies[start:start+48*48], (48,48), f"strategy_army_{i:03d}.png", palettes["K00"], 0)
    evidence = json.loads((ROOT / "extract/research_strategic_ui_contract_20261025.evidence.json").read_text())
    def unescape(value):
        if isinstance(value, str): return value.replace("\\u3000", "　")
        if isinstance(value, list): return [unescape(v) for v in value]
        if isinstance(value, dict): return {k: unescape(v) for k,v in value.items()}
        return value
    evidence = unescape(evidence)
    (ROOT / "godot/data/strategic_ui.json").write_text(json.dumps({
        "source":"research_strategic_ui_contract_20261025; 4310B9/4304E0/43B680",
        "world":evidence["world"],"towns":evidence["towns"],
    }, ensure_ascii=False, indent=1).replace("\\\\u3000", "　")+"\n")


if __name__ == "__main__":
    prepare()
