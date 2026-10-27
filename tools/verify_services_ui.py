"""K01/K03/K04 source-index/desktop audit; no production image used as expected.

Compose an INDEX surface from read-only originals (including ASC16/HZK16), then
apply the caller palette. Quantity captures its real local index backdrop before
the fixed KUANG04 startup LUT. Fixtures provide state only, never expected pixels.
"""
from pathlib import Path
import argparse,json,os,re,subprocess,sys
import numpy as np
from PIL import Image,ImageDraw
from verify_title_ui import raster,text,wrong
from verify_save_ui import palette
from verify_strategy_ui import confirm
ROOT=Path(__file__).resolve().parents[1];GAME=ROOT.parent/'dlz/ANTI-JAP';UI=ROOT/'godot/assets/ui';OUT=ROOT/'out/ui_services'
sys.path.insert(0,str(ROOT))
from extract import game
DATA=game.load(GAME/'GAME.DAT').as_dict()
GRAY=np.tile(np.arange(256,dtype=np.uint8).reshape(256,1),(1,3))
def normalize(s):return str(s).replace('\\u3000','　')
def img(name,size,key=None):return raster((GAME/(name+'.IMG')).read_bytes()[16:16+size[0]*size[1]],size,GRAY,key)
def label(im,value,x,y,ink=0x48):text(im,normalize(value),x,y,GRAY[ink])
def sprite(im,bank,index,x,y,key=None):
    stride=19 if bank=='ARMY' else 1;b=(GAME/(bank+'.DAT')).read_bytes();at=index*stride*2304
    im.alpha_composite(raster(b[at:at+2304],(48,48),GRAY,key),(x,y))
def button(im,x,y,label_,down=False,arrow=None):
    n=(0 if arrow is None else arrow)+int(down);size=(50,25) if arrow is None else (35,19)
    im.alpha_composite(img('BUTTON'+str(n),size),(x,y))
    if label_:label(im,label_,x+8,y+4)
def frame(im,x,y,w=48,h=48):ImageDraw.Draw(im).rectangle((x,y,x+w-1,y+h-1),outline=tuple(GRAY[0xB7])+(255,))
def dots(im,m,x,y,items=False):
    slots=[int(v) for v in m['item_slots' if items else 'mine_slots'] if v]
    for n,v in enumerate(slots):
        ink=0xBF if items else [0xBF,0xB7,0xCF,0xEE][(v-1)//10]
        ImageDraw.Draw(im).rectangle((x,y-6*n,x+3,y-6*n+3),fill=tuple(GRAY[ink])+(255,))
def person(im,m,x,y,items=False,selected=False,outer=False):
    index=DATA['units'][int(m['bingzhong'])]['img_index'];sprite(im,'ARMY',index,x,y,0)
    label(im,'LV  '+str(m['level']),x,y+32);label(im,m['name'],x,y+48);dots(im,m,x+52,y+44,items)
    if selected:frame(im,x-1 if outer else x,y-1 if outer else y,50 if outer else 48,50 if outer else 48)
def stock_count(e,bank,index):return int(e[bank].get(str(index),0))
def draw_shop(e):
    im=img('K01',(640,480));mode=e['mode'];military=e['shop_kind']=='junxie';pressed=e['pressed']
    modes=[0,1,2] if military else [0,3,1,2];names=['买入','交换','分配'] if military else ['物品','材料','交换','分配']
    for i,(m,name) in enumerate(zip(modes,names)):button(im,440,58+50*i if military else 42+42*i,name,m==mode or pressed=='mode'+str(m))
    button(im,440,208 if military else 210,'返回',pressed=='back')
    if mode==2:
        button(im,367,202,'',pressed=='stock_up',10);button(im,367,221,'',pressed=='stock_down',12)
    button(im,574,372,'',pressed=='people_up',10);button(im,574,391,'',pressed=='people_down',12)
    for value,x,y in [('资金：',520,48),(e['money'],572,48),('上',520,134),('交',520,172),('库',520,204),('房',520,242)]:label(im,value,x,y)
    columns=5 if mode==3 else (4 if mode==1 else 6);start=e['item_page']*12 if mode==2 else 0
    people={int(m['pid']):m for m in e['members']}
    for i,entry in enumerate(e['stock'][start:start+columns*2]):
        iid=int(entry['id'])
        if iid<0:continue
        rec=DATA['materials' if mode==3 else 'items'][iid];x=24+(64 if mode==3 else 56)*(i%columns);y=(28 if mode==2 else 32)+120*(i//columns)
        raw=rec['name'].encode('gbk').ljust(12,b'\0');ink=0x48
        if mode==1 and not DATA['item_valid'][iid][int(people[e['shop_person']]['bingzhong'])]:ink=0xBF
        for n in range(2):label(im,raw[n*6:n*6+6].split(b'\0')[0].decode('gbk'),x,y+16*n,ink)
        sprite(im,'MATERIAL' if mode==3 else 'GOODS',iid if mode==3 else rec['goods'],x,y+32)
        if mode in (2,3):label(im,stock_count(e,'materials' if mode==3 else 'items',iid),x,y+80)
        label(im,rec['price'],x,y+(96 if mode in (2,3) else 80))
    for i,m in enumerate(e['members'][e['people_page']*8:e['people_page']*8+16]):person(im,m,24+64*(i%8),304+64*(i//8),True,mode==1 and m['pid']==e['shop_person'])
    return im
FORGE=[('equip',439,233,50,25,'装备',None),('back',522,233,50,25,'返回',None),('reset',542,132,50,25,'取消',None),('max',542,160,50,25,'最大',None),('make',542,188,50,25,'制造',None),('plus',496,151,35,19,'',10),('minus',496,170,35,19,'',12)]
def stripe(im,x,y,w,h):
    draw=ImageDraw.Draw(im)
    for xx in range(0,w,2):draw.line((x+xx,y,x+xx,y+h-1),fill=tuple(GRAY[255])+(255,))
def draw_forge(e):
    im=img('K03',(640,480));ImageDraw.Draw(im).rectangle((22,34,621,99),fill=(255,255,255,255));fuse=e['fuse']
    for i in range(10):
        label(im,DATA['mines'][i]['name'],22+60*i,16);sprite(im,'MINE',fuse*10+i,22+60*i,34)
        if not e['type_flags'][i]:stripe(im,22+60*i,34,48,48)
        label(im,stock_count(e,'mines',fuse*10+i),30+60*i,84)
    frame(im,22+60*e['type'],34)
    for i in range(4):
        x=34+78*(i%2);y=127+96*(i//2);im.alpha_composite(img('BUTTON'+str(2+i*2+(i==fuse)),(48,44),0),(x,y))
        if not e['fuse_flags'][i]:stripe(im,x,y,48,44)
        label(im,['普通','引爆','定时','遥控'][i],40+78*(i%2),175 if i<2 else 205)
    for id,x,y,w,h,name,arrow in FORGE:button(im,x,y,name,e['pressed']==id,arrow)
    for value,x,y in [(e['q'],438,161),('所需资金:',187,226),([0,0,80,300][fuse]*e['q'],267,226),('当前资金:',187,253),(e['money'],267,253),('现有数量',30,364),('配   方',30,384),('所需数量',30,404)]:label(im,value,x,y)
    c=0
    for i,need in enumerate(DATA['mine_recipes'][e['type']]):
        if not need:continue
        x=122+60*c;label(im,DATA['materials'][i]['name'],x,298);sprite(im,'MATERIAL',i,x,316)
        for value,y in [(stock_count(e,'materials',i),364),(need,384),(need*e['q'],404)]:label(im,value,x+8,y)
        c+=1
    return im

def draw_mines(e):
    im=img('K04',(640,480));ImageDraw.Draw(im).rectangle((22,16,581,99),fill=(255,255,255,255));source=next((m for m in e['members'] if m['pid']==e['mine_person']),None)
    for i in range(10 if source is None else 8):
        packed=e['mine_page']*10+i if source is None else int(source['mine_slots'][i])-1
        if packed<0:continue
        label(im,DATA['mines'][packed%10]['name'],22+56*i,16);sprite(im,'MINE',packed,22+56*i,34)
        if source is None:label(im,stock_count(e,'mines',packed),30+56*i,84)
    for i,m in enumerate(e['members']):person(im,m,22+64*(i%7),113+64*(i//7),False,source is not None and m['pid']==e['mine_person'],True)
    button(im,533,178,'分配' if source is not None or e['pressed']=='switch' else '交换',e['pressed']=='switch');button(im,533,220,'返回',e['pressed']=='back')
    if source is None:
        button(im,588,38,'',e['pressed']=='up',10);button(im,588,57,'',e['pressed']=='down',12)
    else:ImageDraw.Draw(im).rectangle((588,38,622,75),fill=(255,255,255,255))
    for value,x,y in [('资金：',508,154),(e['money'],556,154),('卖',502,312),('出',502,342),('库',502,376),('房',502,406)]:label(im,value,x,y)
    return im

def quantity_lut():
    pal=palette('KUANG04').astype(np.int64);out=[]
    for color in pal:
        target=color//2;distance=((pal-target)**2*np.array([30,59,11])).sum(axis=1)//100
        out.append(int(np.argmin(distance)))
    return bytes(out)
def expected(e):
    im={'shop':draw_shop,'forge':draw_forge,'mines':draw_mines}[e['kind']](e)
    if e['drag']:
        d=e['drag'];sprite(im,d['bank'].upper(),d['icon'],*map(int,e['drag_point']),0)
    if 'quantity' in e:
        q=e['quantity'];raw=bytes(np.array(im)[160:260,240:400,0].flatten()).translate(quantity_lut());im.alpha_composite(raster(raw,(160,100),GRAY),(240,160));rec=DATA['materials'][q['id']]
        for value,x,y in [('买多少',264,168),(rec['unit'],312,168),(rec['name'],328,168),('当前',272,216),(q['q'],320,216),(rec['unit'],352,216),('最大',272,236),(q['max'],320,236),(rec['unit'],352,236)]:label(im,value,x,y)
        draw=ImageDraw.Draw(im);draw.rectangle((255,191,384,204),outline=tuple(GRAY[0x8B])+(255,))
        width=q['q']*128//q['max'] if q['max'] else 0
        if width:draw.rectangle((256,192,255+width,203),fill=tuple(GRAY[0xAB])+(255,))
    pal=palette({'shop':'K01','forge':'K03','mines':'K04'}[e['kind']]);indices=np.array(im)[:,:,0]
    image=raster(indices.tobytes(),(640,480),pal)
    if 'confirm' in e:confirm(image,e['confirm'],(320,200),pal)
    if 'fade' in e:
        a=np.array(image).astype(np.int16);amount=e['fade']['step']*4
        a[:,:,:3]=np.minimum(a[:,:,:3],amount) if e['fade']['enter'] else np.maximum(a[:,:,:3]-amount,0)
        image=Image.fromarray(a.astype(np.uint8))
    return image

def source_assets():
    for name in ('K01','K03','K04'):yield 'service_'+name.lower()+'_indices.bin',(GAME/(name+'.IMG')).read_bytes()[16:16+307200]
    for i in range(14):
        size=1250 if i<2 else (2112 if i<10 else 665)
        yield f'service_button{i}_indices.bin',(GAME/f'BUTTON{i}.IMG').read_bytes()[16:16+size]
    for name in ('MINE','MATERIAL','GOODS'):yield f'service_{name.lower()}_indices.bin',(GAME/(name+'.DAT')).read_bytes()
    b=(GAME/'ARMY.DAT').read_bytes();yield 'service_army_indices.bin',b''.join(b[i*19*2304:i*19*2304+2304] for i in range(91))
    for name in ('ASC16','HZK16'):yield f'service_{name.lower()}.bin',(GAME/name).read_bytes()
    yield 'service_quantity_lut.bin',quantity_lut()
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--render',action='store_true');args=parser.parse_args();rows=[]
    for name,expected_bytes in source_assets():
        actual=(UI/name).read_bytes();diff=sum(a!=b for a,b in zip(actual,expected_bytes))+abs(len(actual)-len(expected_bytes))
        rows.append(dict(name=name,bytes=len(expected_bytes),wrong=diff))
    if args.render:
        p=subprocess.run([os.environ.get('GODOT_BIN','/Applications/Godot.app/Contents/MacOS/Godot'),'--path',str(ROOT/'godot'),'--script','res://tests/OriginalServicesQA.gd'],capture_output=True,text=True,timeout=180)
        output=p.stdout+p.stderr;(ROOT/'out/services_ui_capture.log').write_text(output)
        if p.returncode or 'ORIGINAL_SERVICES_QA_COMPLETE' not in output or re.search(r'SCRIPT ERROR:|ERROR:|ObjectDB instances were leaked',output):print(output);return 1
        for name,e in json.loads((OUT/'manifest.json').read_text()).items():
            im=expected(e);im.save(OUT/(name+'_expected.png'));rows.append(dict(name=name,pixels=307200,wrong=wrong(Image.open(OUT/(name+'.png')),im)))
    (ROOT/'out/services_ui_audit.json').write_text(json.dumps(rows,indent=2)+'\n');ok=all(r['wrong']==0 for r in rows)
    print('ORIGINAL_SERVICES_UI' if args.render else 'NATIVE_SERVICES_UI','PASS' if ok else 'FAIL',json.dumps(rows));return 0 if ok else 1
if __name__=='__main__':raise SystemExit(main())
