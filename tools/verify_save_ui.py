"""Independent MENU09 caller-palette and actual desktop render audit."""
from pathlib import Path
import argparse,json,os,re,subprocess
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]; GAME=ROOT.parent/'dlz/ANTI-JAP'; OUT=ROOT/'out/ui_save'
from verify_title_ui import raster,text,wrong
KEYS=('BG01','KUANG04','PLACE04','PLACE05','K00')
def palette(key):
    if key.startswith('PLACE'):
        i=int(key[5:]);raw=(GAME/'PLACE.DAT').read_bytes()[i*0x4B400+0x4B000:(i+1)*0x4B400]
        return np.frombuffer(bytes(v for n in range(256) for v in raw[n*4:n*4+3]),dtype=np.uint8).reshape(256,3)
    return np.frombuffer(bytes(v*4 for v in (GAME/(key+'.IMG')).read_bytes()[-768:]),dtype=np.uint8).reshape(256,3)
def row_entries(row):
    entries=[(36,'进度'),(68,('一','二','三','四','五')[row])]
    if row==1:entries += [(100,'任务'),(286,'第  回合'),(132,'10'),(368,'普通'),(302,' 3'),(180,'虎口救亲人')]
    if row==3:entries += [(100,'任务'),(286,'休息关'),(132,' 5'),(368,'困难'),(180,'高家庄')]
    return entries
def expected(key,state):
    pal=palette(key);image=Image.new('RGBA',(640,480),tuple(pal[0x7F])+(255,));panel=raster((GAME/'MENU09.IMG').read_bytes()[16:16+456*227],(456,227),pal)
    for row in range(5):
        for x,value in row_entries(row):text(panel,value,x,32+row*36,pal[0x48])
    if state!='normal':
        row=1 if state=='row1' else 4
        selected=raster((GAME/'MENU09.IMG').read_bytes()[16:16+456*227],(456,227),pal)
        for x,value in row_entries(row):text(selected,value,x,32+row*36,pal[0xB7])
        panel.paste(selected.crop((0,32+row*36,400,50+row*36)),(0,32+row*36))
    image.alpha_composite(panel,(92,126));return image

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--render',action='store_true');args=parser.parse_args();rows=[]
    palettes=json.loads((ROOT/'godot/data/native_ui_palettes.json').read_text())
    for key,actual in palettes.items():
        source=palette(key).flatten().tolist();rows.append(dict(name=key,pixels=256,wrong=sum(a!=b for a,b in zip(actual,source)) + abs(len(actual)-len(source))))
    raw=(GAME/'MENU09.IMG').read_bytes()[16:16+456*227];actual=(ROOT/'godot/assets/ui/menu09_indices.bin').read_bytes()
    rows.append(dict(name='MENU09 indices',pixels=456*227,wrong=sum(a!=b for a,b in zip(raw,actual))+abs(len(raw)-len(actual))))
    if args.render:
        proc=subprocess.run([os.environ.get('GODOT_BIN','/Applications/Godot.app/Contents/MacOS/Godot'),'--path',str(ROOT/'godot'),'--script','res://tests/OriginalSaveQA.gd'],capture_output=True,text=True,timeout=180)
        output=proc.stdout+proc.stderr;(ROOT/'out/save_ui_capture.log').write_text(output)
        if proc.returncode or 'ORIGINAL_SAVE_QA_COMPLETE' not in output or re.search(r'SCRIPT ERROR:|ERROR:|ObjectDB instances were leaked',output):print(output);return 1
        for key in KEYS:
            for state in ('normal','row1','row4','retained'):
                name=key+'_'+state;im=expected(key,state);im.save(OUT/(name+'_expected.png'));rows.append(dict(name=name,pixels=640*480,wrong=wrong(Image.open(OUT/(name+'.png')),im)))
    (ROOT/'out/save_ui_audit.json').write_text(json.dumps(rows,indent=2)+'\n');ok=all(r['wrong']==0 for r in rows)
    print('ORIGINAL_SAVE_UI' if args.render else 'NATIVE_SAVE_UI','PASS' if ok else 'FAIL',json.dumps(rows));return 0 if ok else 1
if __name__=='__main__':raise SystemExit(main())
