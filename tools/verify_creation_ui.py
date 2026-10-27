"""Source-byte/pixel audit of native MENU01 creation and the mouse name grid.

Expected pixels are composed from original IMG/DAT/HZK/ASC bytes and the
source-bound contract, not copied from production PNGs or live UI output.
"""
from pathlib import Path
import argparse
import json
import os
import re
import subprocess
import numpy as np
from PIL import Image
ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT.parent / 'dlz' / 'ANTI-JAP'
UI = ROOT / 'godot/assets/ui'
OUT = ROOT / 'out/ui_creation'
PAL = np.frombuffer(bytes(v*4 for v in (GAME/'MENU01.IMG').read_bytes()[-768:]), dtype=np.uint8).reshape(256,3)
NAME_PAL = np.frombuffer(bytes(v*4 for v in (GAME/'KUANG04.IMG').read_bytes()[-768:]),dtype=np.uint8).reshape(256,3)
HZK = (GAME/'HZK16').read_bytes()
ASC = (GAME/'ASC16').read_bytes()

def raster(raw, size, palette=PAL, key=None):
    indices = np.frombuffer(raw, dtype=np.uint8).reshape(size[1],size[0])
    out = np.concatenate((palette[indices],np.full((*indices.shape,1),255,dtype=np.uint8)),axis=2)
    if key is not None: out[:,:,3] = np.where(indices == key,0,255)
    return Image.fromarray(out)

def source_assets():
    faces = (GAME/'FACE.DAT').read_bytes(); armies = (GAME/'ARMY.DAT').read_bytes()
    for i in range(103,109): yield f'creation_face_{i}.png',raster(faces[i*8000:(i+1)*8000],(80,100))
    for i in (30,40,32,54):
        at=i*19*2304
        yield f'creation_army_{i}.png',raster(armies[at:at+2304],(48,48),key=0)
    buttons=(GAME/'BUTTON22.IMG').read_bytes()[16:16+5632]
    for i,label in enumerate(('normal','pressed')):yield f'creation_button_{label}.png',raster(buttons[i*2816:(i+1)*2816],(88,32))
    yield 'creation_slider.png',raster((GAME/'MENU30.IMG').read_bytes()[16:441],(17,25),key=0xF0)

def text(image,value,x,y,palette=PAL):
    for char in value:
        if ord(char)<127:
            width=8; raw=ASC[ord(char)*16:(ord(char)+1)*16]
        else:
            encoded=bytes.fromhex('d7fa') if char=='\ue000' else char.encode('gb2312')
            at=((encoded[0]-0xA1)*94+encoded[1]-0xA1)*32
            width=16; raw=HZK[at:at+32]
        bits=np.unpackbits(np.frombuffer(raw,dtype=np.uint8)).reshape(16,width)
        glyph=np.zeros((16,width,4),dtype=np.uint8);glyph[:,:,:3]=palette[0x7F];glyph[:,:,3]=bits*255
        image.alpha_composite(Image.fromarray(glyph),(x,y)); x+=width

def fill(image,box,index,palette=PAL):
    image.paste(tuple(int(v) for v in palette[index])+(255,),box)

def border(image,x,y,w,h,index):
    fill(image,(x,y,x+w,y+1),index);fill(image,(x,y+h-1,x+w,y+h),index)
    fill(image,(x,y,x+1,y+h),index);fill(image,(x+w-1,y,x+w,y+h),index)

def expected(name,assets):
    if name.startswith('name_'):
        image=Image.new('RGBA',(640,480),tuple(NAME_PAL[0xFF])+(255,))
        for y in (42,66):fill(image,(0,y,640,y+1),0x7F,NAME_PAL)
        for i,s in enumerate(('确  定','返  回','上一页','下一页','退  格')):text(image,s,160+i*80,16,NAME_PAL)
        for i,char in enumerate('ＡＢＣＤＥＦＧＨＪＫＬＭＮＯＰＱＲＳＴＷＸＹＺ'):text(image,char,i*27,48,NAME_PAL)
        offsets=[0,36,220,453,637,659,784,939,1120,1415,1515,1763,1914,1995,2003,2125,2282,2341,2627,2783,2903,3126,3432,3756]
        section=0 if name=='name_empty' else 22
        chars=['\ue000' if n==3755 else bytes((0xB0+n//94,0xA1+n%94)).decode('gbk') for n in range(offsets[section],offsets[section+1])]
        for i,char in enumerate(chars):text(image,char,(i%20)*32,72+(i//20)*24,NAME_PAL)
        count=1 if name=='name_one' else 0
        if count:text(image,chars[0],0,16,NAME_PAL)
        fill(image,(16*count,33,16*count+17,34),0x7F,NAME_PAL)
        return image
    image=raster((GAME/'MENU01.IMG').read_bytes()[16:16+640*480],(640,480))
    selected=name!='default'; wuli=80 if not selected else (60 if name=='selected' else 100)
    difficulty=1 if not selected else (0 if name=='selected' else 2)
    for i in range(6):image.alpha_composite(assets[f'creation_face_{103+i}.png'],(40+96*i,86))
    border(image,40+96*(5 if selected else 0),86,80,100,0xB7)
    for i,(army,label) in enumerate(zip((30,40,32,54),('手枪队','大刀队','步枪队','骑兵队'))):
        image.alpha_composite(assets[f'creation_army_{army}.png'],(163+88*i,203))
        if selected and i==0:border(image,163,203,48,48,0)
        text(image,label,163+88*i,255)
    border(image,163+88*(3 if selected else 0),203,48,48,0xB7)
    left=(wuli-60)*128//40
    fill(image,(255,287,255+left,303),0xED);fill(image,(255+left,287,383,303),0xB7)
    image.alpha_composite(assets['creation_slider.png'],(261+(wuli-60)*100//40,283))
    text(image,str(160-wuli),217,287);text(image,str(wuli),392,287);text(image,'主　角',108,374)
    fill(image,(249,371,593,393),0xF0)
    if difficulty:fill(image,(249,371,249+172*difficulty,393),0xB7)
    text(image,('容  易','普  通','困  难')[difficulty],499,331)
    for i,((x,y),label) in enumerate(zip(((138,425),(275,426),(412,427)),('更  改','确  定','取  消'))):
        image.alpha_composite(assets['creation_button_pressed.png' if name=='pressed' and i==1 else 'creation_button_normal.png'],(x,y))
        text(image,label,x+20,y+8)
    return image

def compare(actual, expected):
    a=np.array(actual.convert('RGBA')); b=np.array(expected.convert('RGBA'))
    if a.shape!=b.shape:return b.shape[0]*b.shape[1]
    # Transparent RGB carries no screen meaning; alpha itself must match.
    return int(np.sum(np.any(a[:,:,:3]!=b[:,:,:3],axis=2)&(b[:,:,3]>0) | (a[:,:,3]!=b[:,:,3])))

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--render',action='store_true');args=parser.parse_args()
    assets=dict(source_assets());rows=[]
    for name,im in assets.items():rows.append(dict(name=name,pixels=im.width*im.height,wrong=compare(Image.open(UI/name),im)))
    if args.render:
        proc=subprocess.run([os.environ.get('GODOT_BIN','/Applications/Godot.app/Contents/MacOS/Godot'),'--path',str(ROOT/'godot'),'--script','res://tests/OriginalCreationQA.gd'],capture_output=True,text=True,timeout=180)
        output=proc.stdout+proc.stderr
        (ROOT/'out/creation_ui_capture.log').write_text(output)
        if proc.returncode or 'ORIGINAL_CREATION_QA_COMPLETE' not in output or re.search(r'SCRIPT ERROR:|ERROR:|ObjectDB instances were leaked',output):
            print(output);return 1
        for name in ('default','selected','maximum','pressed','name_empty','name_z','name_one'):
            image=expected(name,assets);image.save(OUT/f'{name}_expected.png')
            rows.append(dict(name=name,pixels=640*480,wrong=compare(Image.open(OUT/f'{name}.png'),image)))
    report=ROOT/'out/creation_ui_audit.json';report.write_text(json.dumps(rows,indent=2)+'\n')
    ok=all(row['wrong']==0 for row in rows)
    print('ORIGINAL_CREATION_UI' if args.render else 'NATIVE_CREATION_UI','PASS' if ok else 'FAIL',json.dumps(rows))
    return 0 if ok else 1
if __name__=='__main__':raise SystemExit(main())
