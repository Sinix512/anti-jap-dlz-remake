"""Title and destination pixel audit, independently composed from original bytes.

No original EXE execution. The expected images never read production PNGs.
"""
from pathlib import Path
import argparse,json,os,re,subprocess
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
GAME=ROOT.parent/'dlz/ANTI-JAP'
UI=ROOT/'godot/assets/ui'; OUT=ROOT/'out/ui_title'
def palette(name,offset=None):
    raw=(GAME/name).read_bytes();raw=raw[-768:] if offset is None else raw[offset:offset+768]
    return np.frombuffer(bytes(v*4 for v in raw),dtype=np.uint8).reshape(256,3)
TITLE=palette('BG03.IMG'); TRANSITION=palette('BG01.IMG'); BATTLE=palette('KUANG04.IMG'); ZYB=palette('ZYB.IMG',0x49D910)
def raster(raw,size,pal,key=None):
    indices=np.frombuffer(raw,dtype=np.uint8).reshape(size[1],size[0]);alpha=np.full((*indices.shape,1),255,dtype=np.uint8)
    if key is not None:alpha[:,:,0]=np.where(indices==key,0,255)
    return Image.fromarray(np.concatenate((pal[indices],alpha),axis=2))
def img(name,size,pal):return raster((GAME/name).read_bytes()[16:16+size[0]*size[1]],size,pal)
def assets():
    yield 'title_bg.png',img('BG03.IMG',(640,480),TITLE)
    for i in range(5):yield f'title_selected_{i}.png',img(f'MENU{50+i}.IMG',(232,56),TITLE)
    yield 'title_mine02.png',raster((GAME/'MINE02.IMG').read_bytes()[16:16+80640],(56,1440),TITLE,4)
    yield 'title_transition.png',img('BG01.IMG',(640,480),TRANSITION)
    yield 'title_supporters.png',img('ZYB.IMG',(640,7562),ZYB)
def text(image,value,x,y,color):
    hzk=(GAME/'HZK16').read_bytes();asc=(GAME/'ASC16').read_bytes()
    for char in value:
        if ord(char)<128:width=8;raw=asc[ord(char)*16:(ord(char)+1)*16]
        else:
            encoded=char.encode('gb2312');at=((encoded[0]-0xA1)*94+encoded[1]-0xA1)*32;width=16;raw=hzk[at:at+32]
        bits=np.unpackbits(np.frombuffer(raw,dtype=np.uint8)).reshape(16,width)
        glyph=np.zeros((16,width,4),dtype=np.uint8);glyph[:,:,:3]=color;glyph[:,:,3]=bits*255
        image.alpha_composite(Image.fromarray(glyph),(x,y));x+=width
NAMES=['default','row1','row2','row3','row4','phase29','retained','wrapped','scores','support0','support1','support_last','exit10','exit11','load10']
def expected(name,a):
    if name in NAMES[:8]:
        row=0 if name=='default' else (int(name[-1]) if name.startswith('row') else 4)
        frame=29 if name in ('phase29','retained') else 0;y=[60,132,204,270,336][row]
        image=a['title_bg.png'].copy();image.alpha_composite(a[f'title_selected_{row}.png'],(315,y));image.alpha_composite(a['title_mine02.png'].crop((0,frame*48,56,(frame+1)*48)),(250,y));return image
    if name=='scores':
        image=a['title_transition.png'].copy();text(image,'排行榜',320,20,TRANSITION[0x7F])
        for i in range(10):
            for value,x in ((str(i+1),20),('英  雄',80),(str(3600-i*50),500)):text(image,value,x,60+40*i,TRANSITION[0x7F])
        return image
    if name.startswith('support'):
        y={'support0':0,'support1':2,'support_last':7082}[name]
        return a['title_supporters.png'].crop((0,y,640,y+480))
    if name=='load10':return a['title_transition.png'].copy()
    image=Image.new('RGBA',(640,480),tuple(BATTLE[255])+(255,))
    if name=='exit10':return image
    panel=(GAME/'MENU03.IMG').read_bytes()[16:16+128*88];image.alpha_composite(raster(panel,(128,88),BATTLE),(320,200))
    lut=bytes(json.loads((ROOT/'extract/research_ui_controls_20261025.json').read_text())['menu13']['selected_background_lut'])
    strip=b''.join(panel[y*128+4:y*128+124] for y in range(32,56)).translate(lut)
    image.alpha_composite(raster(strip,(120,24),BATTLE),(324,232))
    text(image,'退出吗?',356,204,BATTLE[0x7F]);text(image,'是',376,236,(252,140,0));text(image,'否',376,260,BATTLE[0x7F]);return image

def wrong(a,b):
    a=np.array(a.convert('RGBA'));b=np.array(b.convert('RGBA'))
    if a.shape!=b.shape:return b.shape[0]*b.shape[1]
    return int(np.sum(np.any(a[:,:,:3]!=b[:,:,:3],axis=2)&(b[:,:,3]>0)|(a[:,:,3]!=b[:,:,3])))
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--render',action='store_true');args=parser.parse_args();a=dict(assets());rows=[]
    for name,im in a.items():rows.append(dict(name=name,pixels=im.width*im.height,wrong=wrong(Image.open(UI/name),im)))
    if args.render:
        proc=subprocess.run([os.environ.get('GODOT_BIN','/Applications/Godot.app/Contents/MacOS/Godot'),'--path',str(ROOT/'godot'),'--script','res://tests/OriginalTitleQA.gd'],capture_output=True,text=True,timeout=180)
        output=proc.stdout+proc.stderr;(ROOT/'out/title_ui_capture.log').write_text(output)
        if proc.returncode or 'ORIGINAL_TITLE_QA_COMPLETE' not in output or re.search(r'SCRIPT ERROR:|ERROR:|ObjectDB instances were leaked',output):print(output);return 1
        for name in NAMES:
            im=expected(name,a);im.save(OUT/f'{name}_expected.png');rows.append(dict(name=name,pixels=640*480,wrong=wrong(Image.open(OUT/f'{name}.png'),im)))
    (ROOT/'out/title_ui_audit.json').write_text(json.dumps(rows,indent=2)+'\n');ok=all(r['wrong']==0 for r in rows)
    print('ORIGINAL_TITLE_UI' if args.render else 'NATIVE_TITLE_UI','PASS' if ok else 'FAIL',json.dumps(rows));return 0 if ok else 1
if __name__=='__main__':raise SystemExit(main())
