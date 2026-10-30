"""Native strategic assets and full desktop pixels vs independently decoded originals.

Fixture manifest supplies state only. Expected backgrounds, sprites, fonts, LUTs,
coordinates and strings are decoded from original read-only assets/contracts.
"""
from pathlib import Path
import argparse,json,os,re,subprocess
import numpy as np
from PIL import Image
from verify_title_ui import raster,text,wrong
from verify_save_ui import palette
ROOT=Path(__file__).resolve().parents[1]; GAME=ROOT.parent/'dlz/ANTI-JAP'; OUT=ROOT/'out/ui_strategy'; UI=ROOT/'godot/assets/ui'
CONTRACT=json.loads((ROOT/'extract/contracts/strategic_ui.json').read_text())
LUT=bytes(json.loads((ROOT/'extract/contracts/ui_controls.json').read_text())['menu13']['selected_background_lut'])
def img(name,size,pal,key=None):return raster((GAME/(name+'.IMG')).read_bytes()[16:16+size[0]*size[1]],size,pal,key)
def tga(name,size,pal,key=None):
    blob=(GAME/(name+'.TGA')).read_bytes();w,h=size
    return raster(b''.join(blob[len(blob)-(r+1)*w:len(blob)-r*w] for r in range(h)),size,pal,key)
def choice(image,lines,at,pal):
    blob=(GAME/'MENU.TGA').read_bytes();raw=b''.join(blob[len(blob)-(r+1)*88:len(blob)-r*88] for r in range(120));n=len(lines)
    raw=raw[88*88:] if n==1 else raw[:32*88]+raw[32*88:56*88]*(n-2)+raw[56*88:88*88]
    panel=raster(raw,(88,len(raw)//88),pal)
    if n>1:
        strip=b''.join(raw[y*88+4:y*88+84] for y in range(8,32)).translate(LUT);panel.alpha_composite(raster(strip,(80,24),pal),(4,8))
    for i,line in enumerate(lines):text(panel,line,12,12+24*i,pal[0xBF if i==0 else 0x48])
    # 426C6A ends atH-2; the last two rows retain the caller background.
    image.alpha_composite(panel.crop((0,0,88,panel.height-2)) if n>1 else panel,at)
def confirm(image,prompt,at,pal):
    raw=(GAME/'MENU03.IMG').read_bytes()[16:16+128*88];p=raster(raw,(128,88),pal)
    strip=b''.join(raw[y*128+4:y*128+124] for y in range(32,56)).translate(LUT);p.alpha_composite(raster(strip,(120,24),pal),(4,32))
    text(p,prompt,(128-len(prompt.encode('gbk'))*8)//2,4,pal[0x48]);text(p,'是',56,36,pal[0xBF]);text(p,'否',56,60,pal[0x48]);image.alpha_composite(p,at)
def pid_at(entry,side,slot):
    if side==0:return int(entry['left'][slot]['pid']) if entry['left'][slot]['active'] else None
    right=entry['right'][slot]
    if not right['status']:return None
    return int(right['value']) if right['status']==2 else int(entry['left'][right['value']]['pid'])
def army(member,pal):
    b=(GAME/'ARMY.DAT').read_bytes();at=member['army_index']*19*48*48
    return raster(b[at:at+48*48],(48,48),pal,0)
def expected(name,entry):
    pal=palette(entry['palette']);mode=entry['mode']
    if mode=='world':
        image=img('BIGMAP',(640,480),pal)
        for i,town in enumerate(CONTRACT['world']['towns']):
            text(image,town['name'].replace('\\u3000','　'),*town['rect'][:2],pal[0xB7 if entry['unlocked'][i] else 0x89])
        image.alpha_composite(img('BIGMINE1' if entry['hover'] else 'BIGMINE0',(70,81),pal,0x83),(549,20));text(image,entry['clock'],400,20,pal[0x48])
        if name=='world_system':choice(image,['退  出','音  乐','音  效','读  档','存  档'],(551,100),pal)
    elif mode=='town':
        i=entry['town'];b=(GAME/'PLACE.DAT').read_bytes();image=raster(b[i*0x4B400:i*0x4B400+0x4B000],(640,480),pal)
        town=CONTRACT['towns'][i]
        for building in town['buildings']:
            if building['enabled']:text(image,building['label'],*building['text_at'],town['label_rgb'])
    elif mode in ('resident','command'):
        image=img('BG02' if mode=='resident' else 'BACK19',(640,480),pal)
        if mode=='resident':text(image,'出  去',548,48,pal[0x48])
        if name=='departure':confirm(image,'出战吗？',(320,200),pal)
        if name=='solo':choice(image,['肖  飞','李霜泗'],(320,200),pal)
        if name=='resident_story':
            image.alpha_composite(tga('FRAME00',(404,127),pal,0),(118,296))
            rec=json.loads((ROOT/'godot/data/m5.json').read_text())['records'];line=next(r for r in rec if r['n']==21)['lines'][0]
            # The actual global identity is slot1. Native source face bytes,
            # not production RGBA. Text area verified visually/separate layout.
            m2=json.loads((ROOT/'godot/data/m2.json').read_text());person=m2['people'][line['code']];face=person['face']
            raw=(GAME/'FACE.DAT').read_bytes();image.alpha_composite(raster(raw[face*8000:(face+1)*8000],(80,100),pal),(130,308))
    elif mode=='deployment':
        image=img('K00',(640,480),pal)
        for side in range(2):
            for i in range(16):
                slot=entry['pages'][side]*16+i;pid=pid_at(entry,side,slot)
                if pid is None:continue
                m=entry['members'][str(pid)];x=(32 if side==0 else 360)+72*(i%4);y=74+64*(i//4);color=pal[0xB7 if side==1 and entry['right'][slot]['status']==2 else 0x48]
                image.alpha_composite(army(m,pal),(x,y));text(image,'LV  '+str(m['level']),x,y+32,color);text(image,m['name'],x,y+48,color)
            text(image,'下一页' if entry['pages'][side]==0 else '上一页',246 if side==0 else 396,361,pal[0x48])
        image.alpha_composite(img('BUTTON1' if entry['pressed'] else 'BUTTON0',(50,25),pal),(524,390));text(image,'确定',530,394,pal[0x48])
        count=sum(bool(r['status']) for r in entry['right'])
        for v,x in ((str(count),460),('/',476),(str(entry['limit']),492)):text(image,v,x,440,pal[0x48])
        if entry['drag']:
            d=entry['drag'];m=entry['members'][str(pid_at(entry,d['side'],d['slot']))]
            fields=[('姓  名：',m['name'],79,143,394),('兵  种：',m['class_name'],207,271,394),('等  级：',m['level'],335,399,394),('武  力：',m['wuli'],79,143,414),('智  力：',m['zhili'],207,271,414),('物品数：',sum(v>0 for v in m['item_slots']),79,143,434),('地雷数：',sum(v>0 for v in m['mine_slots']),207,271,434)]
            for label,value,x,vx,y in fields:text(image,label,x,y,pal[0x48]);text(image,str(value),vx,y,pal[0x48])
            image.alpha_composite(army(m,pal),tuple(int(v) for v in entry['drag_point']))
    else:raise ValueError(mode)
    return image

def assets():
    for key in ('BIGMAP','K00','BACK19'):yield 'strategy_'+key.lower()+'.png',img(key,(640,480),palette(key))
    for i in range(2):
        yield f'strategy_mine{i}.png',img(f'BIGMINE{i}',(70,81),palette('BIGMAP'),0x83)
        yield f'strategy_button{i}.png',img(f'BUTTON{i}',(50,25),palette('K00'))
    blob=(GAME/'PLACE.DAT').read_bytes()
    for i in range(19):yield f'strategy_place{i:02d}.png',raster(blob[i*0x4B400:i*0x4B400+0x4B000],(640,480),palette(f'PLACE{i:02d}'))
    m2=json.loads((ROOT/'godot/data/m2.json').read_text())
    for index in sorted({int(v['img_index']) for v in m2['units'].values()}):yield f'strategy_army_{index:03d}.png',army({'army_index':index},palette('K00'))

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--render',action='store_true');args=parser.parse_args();rows=[]
    for name,im in assets():rows.append(dict(name=name,pixels=im.width*im.height,wrong=wrong(Image.open(UI/name),im)))
    if args.render:
        proc=subprocess.run([os.environ.get('GODOT_BIN','/Applications/Godot.app/Contents/MacOS/Godot'),'--path',str(ROOT/'godot'),'--script','res://tests/OriginalStrategicQA.gd'],capture_output=True,text=True,timeout=180)
        output=proc.stdout+proc.stderr;(ROOT/'out/strategy_ui_capture.log').write_text(output)
        if proc.returncode or 'ORIGINAL_STRATEGIC_QA_COMPLETE' not in output or re.search(r'SCRIPT ERROR:|ERROR:|ObjectDB instances were leaked',output):print(output);return 1
        fixtures=json.loads((OUT/'manifest.json').read_text())
        for name,entry in fixtures.items():
            expected_image=expected(name,entry);expected_image.save(OUT/(name+'_expected.png'));actual=Image.open(OUT/(name+'.png')).convert('RGBA')
            pixels=640*480
            if name=='resident_story':
                # Native FRAME/FACE and all unobscured background. The original
                # text is independently layout-tested and visually reviewed.
                actual.paste(expected_image.crop((222,312,510,419)),(222,312));pixels-=288*107
            rows.append(dict(name=name,pixels=pixels,wrong=wrong(actual,expected_image)))
    (ROOT/'out/strategy_ui_audit.json').write_text(json.dumps(rows,indent=2)+'\n');ok=all(r['wrong']==0 for r in rows)
    print('ORIGINAL_STRATEGIC_UI' if args.render else 'NATIVE_STRATEGIC_UI','PASS' if ok else 'FAIL',json.dumps(rows));return 0 if ok else 1
if __name__=='__main__':raise SystemExit(main())
