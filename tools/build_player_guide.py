#!/usr/bin/env python3
"""Build read-only player documentation from the CURRENT remake data.
Never loads/writes user saves; never starts the game or the original executable.
"""
from __future__ import annotations
import argparse, base64, hashlib, html, io, json, re, subprocess
from collections import Counter, defaultdict
from PIL import Image
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/guide'
KEYS = ['buji','jili','yiliao','huogong','gunmu','leishi','weishe','saorao','pohuai','lueduo','fanjian','yibing','duzhan','ansha','shidu','kongxi']
THRESHOLDS = [1,10,25,45,70,100,135,175,225,300]
FU = ['普通','引爆','定时','遥控']

def clean(v):
    return str(v).replace('\\u3000','').replace('\u3000','').replace('|','／').replace('\n',' ')
def j(v): return json.dumps(v, ensure_ascii=False, separators=(',',':'))
def table(headers, rows):
    return '\n'.join(['|'+'|'.join(headers)+'|','|'+'|'.join(['---']*len(headers))+'|'] + ['|'+'|'.join(clean(c) for c in row)+'|' for row in rows])+'\n\n'
def load(n): return json.loads((ROOT / f'godot/data/{n}.json').read_text())
def rank(c): return sum(c >= t for t in THRESHOLDS)
def attack(u, lv=1, w=80, count=1):
    raw = u['gongji']*3*w//100 + (u['gongji_plus']-1)*(lv-1)
    return max(1,(rank(count)+59)*(raw*(w+500)//580)//60)
def defense(u,lv=1): return max(0,u['fangyu']+(lv-1)*u['fangyu_plus'])
def hp(u,lv=1): return max(1,u['tili']+(lv-1)*u['tili_plus'])
def item_name(i): return clean(M['items'].get(str(i),{}).get('name',f'物品{i}'))
def unit_name(i): return clean(M['unit_types'][i]['name']) if 0<=i<96 else f'兵种{i}'
def skill_names(u): return '、'.join(SN[k] for k,v in u.get('skills',{}).items() if v) or '—'
def compatible(i):
    return '、'.join(f'{z}:{unit_name(z)}' for z,v in enumerate(M['item_valid'][i]) if v and unit_name(z)) or '无'
def range_desc(i):
    return {0:'无选格',1:'正交1格',2:'正交1～2格',3:'正交1～3格',4:'周围八格',5:'曼哈顿半径2（不含自己）',6:'半径2削角20格',7:'远射环8格（近身盲区）',8:'远射环12格（近身盲区）',9:'远射环16格（近身盲区）',10:'远射环12格，伸至4格',11:'远射环20格，伸至4格',12:'远射环24格，伸至4格',13:'正交恰好2格',14:'半径2外环12格',15:'特殊不对称38格，见图'}[i]
def grid_md(mat, center):
    rows=[]
    for y,row in enumerate(mat):
        rows.append(' '.join((' @ ' if (x,y)==center and not v else f'{int(v):3}' if v else ' · ') for x,v in enumerate(row)))
    return '```text\n'+'\n'.join(rows)+'\n```\n\n'
def mask_stats(i):
    a=M['apply_ranges'][str(i)]; vals=[v for row in a for v in row if v>0]
    return f'A{i}：{len(vals)}格，倍率'+('/'.join(map(str,sorted(set(vals),reverse=True))) if vals else '无')+'%'
def effect(i):
    x=M['items'][str(i)];p1=x['para1'];p2=x['para2']
    if not clean(x.get('name','')): return '空白保留槽'
    if clean(x['name'])=='物品': return '占位槽，不作为正常推荐商品'
    if i<=20:return f'HP+{p1}，士气+{p2}；S{x["select_fw"]}（另允许自己），A{x["apply_fw"]}'
    if i<=30:return f'酒：当前无回复；仍消耗；表内参数HP{p1}/士气{p2}'
    if i==31:return '携带每新轮最大HP+25%、士气+10；每本叠加'
    if i==32:return '携带每新轮最大HP+15%；每本叠加'
    if i<=40:return f'本人武力+{p1}、智力+{p2}，各封顶100'
    if i<=56:return f'固定HP伤害{p1}、士气伤害{p2}；S{x["select_fw"]}（另允许自己），A{x["apply_fw"]}'
    if 61<=i<=80:return f'转职/晋升目标{p1}:{unit_name(p1)}；等级门槛依当前兵种常规晋升路线判定'
    if 81<=i<=155:return f'携带攻击+{x["para3"]}、防御+{x["para4"]}、移动+{p1}；三项各取兼容最大'
    return f'未分类：para1={p1}，para2={p2}'


# Descriptions identify appearance, not unverified official terrain names.
TERRAIN_LOOK = ['密植草木/作物','田圃/草灌边缘','草丛/绿地','保留未用','山石/设施','普通地面/道路','深灰路面','铁路','保留未用','房屋','城门/石墙','石墙/设施','牌楼/建筑','水边/桥面','水面','林木/墙体/障碍']
TERRAIN_COLORS=['#718b62','#829b7a','#8aa88a','#9c8971','#b1a18b','#dce3df','#a7c6cc','#7cacb8','#658c9b','#d7b85e','#e5c366','#bca05a','#d7b07c','#d2d2d2','#b6b6b6','#898989']
VISUALS={}

def png_uri(im):
    b=io.BytesIO();im.save(b,format='PNG',optimize=True)
    return 'data:image/png;base64,'+base64.b64encode(b.getvalue()).decode()

def prepare_visuals():
    maps=json.loads((ROOT/'data/map.json').read_text())['maps']
    counts=[Counter() for _ in range(16)];pos={};total=Counter()
    for m in maps:
        l=M['levels'][m['index']]['map']
        assert (m['width'],m['height'])==(l['width'],l['height'])
        assert [v>>12 for v in m['tiles']]==l['terrain'],('terrain mismatch',m['index'])
        for z,v in enumerate(m['tiles']):
            t=v>>12;key=(m['tileset'],v&4095)
            counts[t][key]+=1;total[t]+=1
            pos.setdefault((t,*key),(m['index'],z%m['width'],z//m['width']))
    samples=[];cache={}
    for t in range(16):
        examples=[]
        for (tileset,tile),n in counts[t].most_common(4):
            mi,x,y=pos[(t,tileset,tile)]
            if mi not in cache:cache[mi]=Image.open(ROOT/f'godot/assets/map/map_{mi:02}.png')
            im=cache[mi].crop((x*48,y*48,(x+1)*48,(y+1)*48))
            examples.append({'tileset':tileset,'tile':tile,'occurrences':n,'mission_index':mi,'x':x,'y':y,'png':png_uri(im)})
        samples.append({'type':t,'appearance':TERRAIN_LOOK[t],'map_cells':total[t],'samples':examples})
    VISUALS['terrains']=samples
    # Use the exact game artwork, nearest-scaled to the guide's 22px grid.
    VISUALS['maps']={}
    for m in maps:
        mi=m['index'];im=cache.get(mi) or Image.open(ROOT/f'godot/assets/map/map_{mi:02}.png')
        assert im.size==(m['width']*48,m['height']*48)
        VISUALS['maps'][mi]=png_uri(im.resize((m['width']*22,m['height']*22),Image.Resampling.NEAREST))

def terrain_icon(t,compact=False):
    q=VISUALS['terrains'][t]
    pic=(f'<img class="terrain-icon" src="{q["samples"][0]["png"]}" alt="T{t}实际图块">' if q['samples'] else '<span class="terrain-empty">未用</span>')
    return f'<a class="terrain-badge" href="terrain.md#terrain-{t}">{pic}<span>T{t}'+('' if compact else ' · '+TERRAIN_LOOK[t])+'</span></a>'

def terrain_guide():
    s=['# 地形实景图鉴\n','> 图标直接裁自游戏地图，不是新绘制的示意画。外观描述仅帮助识图，不充当官方名称。编号统一为T0～T15。\n',
       '**同一类地形可有不同外观，同一图块也可能被地图标为不同地形**（例如石墙、水边）。不能只凭长相断定修正；用本页图例对照，并在末尾逐关实景地图上悬停/点格查真实类型。T3、T8在本版47张地图均未使用，不伪造图标。\n',
       '修正表中的防御列作用于本体防御，装备另加；HP恢复按最大HP百分比、士气恢复按点，在新轮生效，双方都适用。移动代价和埋雷许可仍依兵种/雷code查询数值表。\n','<div class="terrain-cards">']
    for q in VISUALS['terrains']:
        t=q['type'];mods=M['terrain_modifiers'][t]
        s.append(f'<section class="terrain-card" id="terrain-{t}"><h2>T{t} · {q["appearance"]}</h2><div class="terrain-samples">')
        for a in q['samples']:
            source=f'第{a["mission_index"]+1}关 ({a["x"]},{a["y"]})'
            s.append(f'<figure><img width="72" height="72" src="{a["png"]}" alt="T{t}实例，{source}" title="{source}；图集{a["tileset"]}/图块{a["tile"]}"><figcaption>{source}</figcaption></figure>')
        if not q['samples']:s.append('<p class="muted">本版地图未使用，没有可核实的实景图块。</p>')
        s.append('</div><p>火攻修正：%+d%% · 滚木/擂石：%+d%%<br>本体防御：%+d%% · 每新轮HP：%+d%% · 士气：%+d</p><small>47图中共%d格；图块样本按出现频率选取。</small></section>'%(*mods,q['map_cells']))
    s.append('</div>')
    return '\n'.join(s)+'\n'

def range_symbol(kind,i,mat):
    n=len(mat);size=24;c=n//2;paths=defaultdict(list);texts=[]
    for y,row in enumerate(mat):
        for x,v in enumerate(row):
            if v<=0:continue
            paths[int(v)].append(f'M{x*size},{y*size}h24v24h-24z')
            if kind=='apply':texts.append(f'<text x="{x*24+12}" y="{y*24+16}" text-anchor="middle">{v}</text>')
    fills=[]
    for v,path in paths.items():
        color=('#8cc8ac' if kind=='select' else '#edac60' if v>=100 else '#f3d3a2')
        fills.append(f'<path d="{"".join(path)}" fill="{color}"/>')
    grid=''.join(f'M{z*24},0V{n*24}M0,{z*24}H{n*24}' for z in range(n+1))
    center=(f'<rect x="{c*24+2}" y="{c*24+2}" width="20" height="20" fill="#264e69"/><text class="actor" x="{c*24+12}" y="{c*24+17}" text-anchor="middle">我</text>' if kind=='select' else f'<rect x="{c*24+1}" y="{c*24+1}" width="22" height="22" fill="none" stroke="#713c10" stroke-width="3"/>' + (f'<circle cx="{c*24+12}" cy="{c*24+12}" r="4" fill="none" stroke="#713c10"/>' if mat[c][c]==0 else ''))
    return f'<symbol id="range-{kind}-{i}" viewBox="-2 -2 {n*24+4} {n*24+4}" data-kind="{kind}" data-matrix="{html.escape(j(mat),quote=True)}"><rect width="{n*24}" height="{n*24}" fill="#faf9f2"/>'+''.join(fills)+f'<path d="{grid}" fill="none" stroke="#c5c8bb" stroke-width=".7"/>'+''.join(texts)+center+'</symbol>'

def range_defs():
    return '<svg class="range-definitions" aria-hidden="true"><defs>'+''.join(range_symbol(k,i,M[table][str(i)]) for k,table,count in [('select','select_ranges',16),('apply','apply_ranges',48)] for i in range(count))+'</defs></svg>'

def range_figure(kind,i,label):
    n=9 if kind=='select' else 7
    return f'<figure class="range-figure"><figcaption>{label}</figcaption><svg class="range-chart" role="img" aria-label="{html.escape(label)}，详细数字见范围模板" width="{n*24+4}" height="{n*24+4}" viewBox="-2 -2 {n*24+4} {n*24+4}"><use href="#range-{kind}-{i}"/></svg></figure>'

def unit_groups():
    groups=defaultdict(list)
    for u in M['unit_types']:
        if clean(u['name']):groups[(clean(u['name']),u['select'],u['apply'])].append(u['index'])
    return groups

def unit_anchor(i):
    for ids in unit_groups().values():
        if i in ids:return 'unit-'+str(ids[0])
    return ''

def unit_ranges():
    groups=unit_groups()
    s=[range_defs()+'\n\n','# 兵种普攻射程与伤害图鉴\n','> 每个具名兵种都可查。同名且选格/作用相同的变体合并一张卡，仍列全ID；同名但范围不同的分开。90～95为空白保留槽，不是可用兵种。\n',
       '**绿色图：人物站在“我”处，可以点哪些落点。橙色图：以选中的落点为中心，哪些格会受伤。两者不是一回事！** 橙图的深框永远是落点，数字为伤害公式的倍率，不是固定伤害，也不保证最终伤害按比例（还受防御和当前HP/20保底影响）。普攻无友伤；空格照样可瞄，范围内只有敌对单位受伤。\n',
       '四张橙图依次为本次预计普攻熟练1～3、4～6、7～9、10级。对应**行动前普攻次数0～43、44～133、134～298、≥299**。次数按命中的敌人数增加，不是按按钮次数；一个动作的作用范围在开始时固定，不会因中途熟练升级变大。默认朝北，改变下方朝向可查看旋转；斜瞄按主轴，斜率相等取纵向，超出地图部分裁掉。绿色选格范围不随朝向旋转。\n',
       '游戏中点“攻击”后，明亮地图格表示能选的落点；鼠标停在合法落点时，**橙色格与百分比**表示本次伤害范围，浅黄框标出落点。普攻特效按同一份作用格播放；人物出招动作本身仍在原位。\n',
       '<div class="range-controls"><label>查兵种 <input id="unit-search" type="search" placeholder="兵种名或ID，例如 机枪 / 9"></label><label>伤害模板朝向 <select id="range-facing"><option value="0">北 ↑</option><option value="3">东 →</option><option value="1">南 ↓</option><option value="2">西 ←</option></select></label><span id="unit-count"></span></div>',
       '<p class="unit-index">'+' · '.join(f'<a href="#unit-{ids[0]}">{name}({"/".join(map(str,ids))})</a>' for (name,sel,g),ids in groups.items())+'</p>',
       '<div class="unit-cards">']
    for (name,sel,g),ids in groups.items():
        s.append(f'<section class="unit-card" id="unit-{ids[0]}" data-search="{name} {" ".join(map(str,ids))}"><h2>{name} <small>ID {" / ".join(map(str,ids))}</small></h2><p class="range-direction">伤害图朝北 ↑</p><p>可选落点：{range_desc(sel)}。'+('此模板无正常普攻可选落点；以下作用图不代表可以主动攻击。' if sel==0 else '')+'</p><div class="range-row">')
        s.append(range_figure('select',sel,f'可选落点 · S{sel}'))
        for k,title in enumerate(['熟练1～3','熟练4～6','熟练7～9','熟练10']):
            ai=g*4+k;s.append(range_figure('apply',ai,f'{title} · A{ai}'))
        s.append('</div></section>')
    s.append('</div>')
    return '\n'.join(s)+'\n'


def reference():
    s=['# 全数值资料表\n','> 自动生成，勿手改。范围S为选目标模板，A为作用模板；模板完整图在末尾。数字ID不是菜单排序。\n',
       '## 1. 全部兵种基础性能\n',
       '兵种槽0为特殊；1～22为常规我方兵种系；23～89主要为敌方、剧情及变体模板，实际阵营由人物/剧情决定；90～95空白。名称相同也保留独立ID。HP栏“基础+每级”用于`基础+(等级−1)×成长`；攻击成长进入公式时会减1，不可照搬成每级面板增加。示例攻击统一武力80、熟练1级、士气100、完整度100、无装备；示例防御不加地形。\n']
    rows=[]
    for u in M['unit_types']:
        z=u['index'];rows.append([z,clean(u['name']) or '空白保留',f'{u["tili"]}+{u["tili_plus"]}/级',f'{u["gongji"]}/{u["gongji_plus"]}',f'{u["fangyu"]}/{u["fangyu_plus"]}',u['yidong'],f'S{u["select"]} {range_desc(u["select"])}',(f'[查看图示](unit_ranges.md#{unit_anchor(z)}) · G{u["apply"]}' if unit_anchor(z) else '保留'),f'{attack(u)}/{attack(u,15)}/{attack(u,30)}',f'{defense(u)}/{defense(u,15)}/{defense(u,30)}',skill_names(u)])
    s.append(table(['ID','兵种','HP','攻基/成长字段','防基/成长','移','选目标','普攻作用组','示例攻击L1/15/30','示例防御L1/15/30','兵种默认策略'],rows))
    s+=['## 2. 常规晋升路线\n','是否能用其他兵书横转，另见物品适配。这里只列兵种的默认晋升，不宣称敌方变体可正常获得。\n']
    s.append(table(['起点','目标','所需道具','等级'],[[f'{u["index"]}:{unit_name(u["index"])}',f'{u["zhuanzhi"]}:{unit_name(u["zhuanzhi"])}',f'{u["zhuanzhidaoju"]}:{item_name(u["zhuanzhidaoju"])}',30 if 75<=u['zhuanzhidaoju']<79 else 15] for u in M['unit_types'] if u['zhuanzhi']>=0]))
    s+=['## 3. 16种地形修正\n','图标取自真实地图；点图可看多个实景样本。名称是外观提示，不是官方地形名。HP恢复按最大HP百分比，士气恢复为点数；恢复对双方都有效。同图块可能有不同地形标记，定位以逐关图的查格结果为准。\n']
    s.append(table(['地形','火攻伤害%','滚木/擂石伤害%','本体防御%','新轮最大HP恢复%','新轮士气恢复'],[[terrain_icon(i),*r] for i,r in enumerate(M['terrain_modifiers'])]))
    s+=['## 4. 全兵种地形移动代价\n','进入该格消耗对应移动预算；“×”表示原值≤0或≥99，正式移动不可通过。高移动力不能支付不可通行格。\n']
    s.append(table(['兵种']+[terrain_icon(i,True) for i in range(16)],[[f'{i}:{unit_name(i) or "保留"}']+['×' if v<=0 or v>=99 else v for v in M['unit_move'][str(i)]] for i in range(96)]))
    s+=['## 5. 全部策略参数与范围\n','效果=正文E(P)再乘作用格倍率；下表“参数”不是最终伤害。固定减益、控制不直接按P计算。辅助中的督战也需要概率判定。\n']
    notes=['友方HP','友方士气','友方HP/士气','敌方HP，再乘火攻地形列','敌方HP，再乘滚木地形列','敌方HP，再乘滚木地形列','敌方士气','防御完整度×0.7，底20','攻击完整度×0.7，底50','偷首件物，概率+熟练等级','等级−1，非招降','跳过当前行动','友方再动/完整度+20，45号兵种无效','敌方HP','敌方HP/士气，非持续伤害','敌方HP']
    s.append(table(['ID','策略','P1/P2','选目标','初始作用基址','对象/效果','成功率'],[[i,clean(x['name']),f'{x["para1"]}/{x["para2"]}',f'S{x["select_fw"]} {range_desc(x["select_fw"])}'+('，可自身' if i<3 else ''),f'A{x["apply_fw"]}（随熟练调整）',notes[i],'无roll' if i in [0,1,2,15] else '普通概率'+('＋熟练等级' if i==9 else '')] for i,x in enumerate(M['skills'])]))
    s+=['## 6. 160个物品槽：有效物品与占位全列\n','ID57～60、129/130/144～150为“物品”占位，156～159为空白。价格为买入标价；不代表所有城镇有售。S/A详见范围图，补给品使用不受兼容装备表限制。\n']
    s.append(table(['ID','名称','标价','当前作用'],[[i,item_name(i) or '空白',x['price'],effect(i)] for i in range(160) for x in [M['items'][str(i)]]]))
    s+=['## 7. 装备与转职道具完整适配\n','按96兵种ID列出许可，保留同名变体ID；可以携带≠能发挥装备作用。兵书使用还要按当前路线/等级检查。\n']
    s.append(table(['物品','允许兵种ID:名称'],[[f'{i}:{item_name(i)}',compatible(i)] for i in range(61,156) if item_name(i)!='物品']))
    s+=['## 8. 十种材料\n']
    s.append(table(['ID','材料','单位','单价'],[[int(i),clean(x['name']),x['unit'],x['price']] for i,x in N['materials'].items()]))
    s+=['## 9. 十种基本雷、威力、配方\n','伤害不走普攻防御差。材料成本按当前购买单价加总，不含引信额外费，不等于回收价。土雷在120威力下仅中心一格；其他范围以A模板数值为准。\n']
    rows=[]
    for i,x in enumerate(M['mines']):
        rec=N['mines'][str(i)]['recipe'];cost=sum(v*N['materials'][str(k)]['price'] for k,v in enumerate(rec))
        rows.append([i,clean(x['name']),'HP' if x['shiqi_or_tili']==0 else '士气',x['weili'],mask_stats(x['apply_fw']),x['price'],'、'.join(f'{clean(N["materials"][str(k)]["name"])}×{v}' for k,v in enumerate(rec) if v),cost])
    s.append(table(['雷种ID','名称','通道','威力','爆炸作用','仓库回收价','材料配方','购买材料成本'],rows))
    s+=['## 10. 40种成品雷的实际可埋地形\n','code=引信号×10+基本雷种。**当前执行许可查code//4行**，不能按基本雷种直接查。全40种列出，均另受空格/相邻/关卡禁雷条件限制。\n']
    s.append(table(['code','成品','引信额外费','许可行','可埋地形'],[[code,FU[code//10]+clean(M['mines'][code%10]['name']),[0,0,80,300][code//10],code//4,'、'.join(f'[T{k}](terrain.md#terrain-{k})' for k,v in enumerate(M['mine_terrain'][code//4]) if v)] for code in range(40)]))
    s+=['## 11. 雷种与引信的城镇解锁\n','默认开局许可还受开场脚本设置；此表列民房数据中的解锁奖励，不以“已到此镇”替代实际访问与事件阶段。\n']
    unlock=[]
    for tid,rules in M['town_scripts']['resident'].items():
        for r in rules:
            a=[clean(M['mines'][x]['name']) for x in r.get('unlock_mine_types',[])]+[FU[x]+'引信' for x in r.get('unlock_fuses',[])]
            if a:unlock.append([f'{tid}:{clean(N["towns"][int(tid)]["name"])}',f'访问民房，阶段{r["phase"]}→{r["set_phase"]}','、'.join(a)])
    s.append(table(['城镇','触发条件','解锁'],unlock))
    s+=['### 民房奖励与指挥部招募/出战条件\n','阶段是持久剧情状态，不等于访问次数；通常战后推进，再访会有新对白/配方。下面列当前数据全部民房阶段与指挥规则，已明确的奖励直接写出，不臆造“每镇可无限招募”。\n']
    for t in N['towns']:
        tid=str(t['index']); rows=[]
        for r in M['town_scripts']['resident'].get(tid,[]):
            rewards=[f'{item_name(int(i))}×{v}' for i,v in r.get('reward_items',{}).items()]+['解锁'+clean(M['mines'][i]['name']) for i in r.get('unlock_mine_types',[])]+['解锁'+FU[i]+'引信' for i in r.get('unlock_fuses',[])]
            rows.append(['民房',f'阶段{r["phase"]}→{r["set_phase"]}', '；'.join(rewards) or '剧情/阶段推进'])
        for r in M['town_scripts']['commander'].get(tid,[]):
            conditions=[]
            for k,label in [('phase_in','指挥阶段属于'),('phase_not_in','指挥阶段不属'),('resident_in','民房阶段属于'),('resident_not_in','民房阶段不属')]:
                if k in r:conditions.append(label+','.join(map(str,r[k])))
            a=r.get('accept',{});effects=[]
            if r.get('enter_recruit'):effects.append('进入对话即入我方：'+','.join(clean(N['people'][i]['name']) for i in r['enter_recruit']))
            if a.get('recruit'):effects.append('接受后入我方：'+','.join(clean(N['people'][i]['name']) for i in a['recruit']))
            if a.get('deploy'):effects.append('进入部署')
            if a.get('direct_solo_battle'):effects.append('单人任务选择：'+','.join(clean(x['label']) for x in r['choice_options'])+'（非普通部署）')
            if r.get('no_choice'):effects.append('仅对白，不出现出战选择')
            if 'set_phase' in a:effects.append('接受后指挥阶段='+str(a['set_phase']))
            rows.append(['指挥部','；'.join(conditions) or '按剧情', '；'.join(effects) or '对白/推进'])
        s.append(f'#### {tid}:{clean(t["name"])}\n')
        s.append(table(['入口','条件','奖励/结果'],rows) if rows else '无普通民房/指挥部规则。\n')
    s+=['## 12. 19城镇完整货单\n','只列目录，不保证剧情未开放时建筑就可用。显示物品ID与标价；每镇的军械/杂货/材料各自列全。\n']
    for t in N['towns']:
        s.append(f'### 镇{t["index"]} {clean(t["name"])}\n')
        s.append(table(['类别','完整目录（ID:名称，标价）'],[[{'junxie':'军械','zahuo':'杂货','material':'材料'}[k],'；'.join(f'{x["index"]}:{clean(x["name"])}（{x["price"]}）' for x in t['shops'][k]) or '无'] for k in ['junxie','zahuo','material']]))
    s+=['## 13. 人物初始模板（非存档现值）\n','槽0普通战役由自建主角替换，不把孙悟空模板当正常主角。槽1～31与32～39NPC性质不同；是否已加入、是否可控还取决于剧情与阵营。此表不给所有人附一个虚构的可招募入口。物品/雷槽的原始+1编码已还原为ID。\n']
    s.append(table(['slot','人物','模板兵种','等级','武/智','策略次数','随身物品ID','雷code'],[[x['pid'],clean(x['name']),f'{x["bingzhong"]}:{clean(x["unit_name"])}',x['level'],f'{x["wuli"]}/{x["zhili"]}','、'.join(f'{SN[k]}:{v}' for k,v in x['skills'].items() if v) or '无','、'.join(f'{v-1}:{item_name(v-1)}' for v in x['wupin'] if v) or '无','、'.join(str(v-1) for v in x['dilei'] if v) or '无'] for x in N['people']]))
    s+=['## 14. 全部16种选目标范围S\n','9×9，中心@为施术者；1可点、·不可点。S号不会直接告诉你落点周围伤害范围。补给/激励/医疗、物品按正文规则额外允许自己。所有方向上限不是“圆形射程”承诺。\n']
    for i in range(16):
        s.append(f'### S{i}：{range_desc(i)}\n');s.append(grid_md(M['select_ranges'][str(i)],(4,4)))
    s+=['## 15. 全部48种作用范围A\n','7×7，中心@为选定落点（该处数值非零时直接显示数值），每个数字是百分比。技能/普攻按朝向旋转，模板默认向北；南180°、西/东90°。斜方向按主轴、相等取纵向。地雷不按角色朝向旋转。食物/投掷当前用角色已有朝向。\n',
        '普攻作用组G的A索引：`4×G−1+ceil(本次预计熟练等级/3)`；预计等级用普攻次数+1。策略：`base−1+ceil(当前熟练等级/3)`。熟练1～3/4～6/7～9/10级对应组内第1/2/3/4模板。攻击力仍按行动开始时已有熟练算，不能提前加。\n']
    s.append(table(['普攻G组','熟练1～3','4～6','7～9','10'],[[g,*[f'A{g*4+k}' for k in range(4)]] for g in range(10)]))
    for i in range(48):s.append(f'### {mask_stats(i)}\n');s.append(grid_md(M['apply_ranges'][str(i)],(3,3)))
    return '\n'.join(s)

FIELDS={'behavior':'AI行为','pad3e':'可控标志','faction':'阵营','level':'等级','hp':'HP','max_hp':'HP上限','morale':'士气','bingzhong':'兵种','target_x':'目标x','target_y':'目标y','target_slot':'追踪人物槽','home_x':'归位x','home_y':'归位y','wuli':'武力','zhili':'智力','integrity':'攻击完整度','defense_integrity':'防御完整度'}
class MissionText:
    def __init__(self,l):
        self.l=l; self.units={u['slot']:u for u in l.get('slot_pool',[])+l.get('units',[])};self.flags={}
    def who(self,i):
        if i==0:return '主角[0]'
        u=self.units.get(i,{})
        name=clean(u.get('name','')) or (clean(N['people'][i]['name']) if 0<=i<40 else '人物')
        return f'{name}[{i}]'
    def flag(self,a):
        a=str(a).lower()
        if a not in self.flags:self.flags[a]=f'F{len(self.flags)+1}'
        return self.flags[a]
    def cmp(self,q):return '且'.join(f'{op}{q[k]}' for k,op in [('eq','='),('neq','≠'),('gte','≥'),('lt','<'),('gt','>'),('le','≤')] if k in q)
    def cond(self,c):
        if not c:return '无额外条件'
        k=next(iter(c));q=c[k]
        if k in ['all','any']:return '('+(' 且 ' if k=='all' else ' 或 ').join(self.cond(x) for x in q)+')'
        if k=='not':return '非('+self.cond(q)+')'
        if k=='unit_stage':return self.who(q['slot'])+('不在场/已退场' if q.get('eq',0)==0 else f'在场状态={q["eq"]}')
        if k=='unit_dest':return self.who(q['slot'])+f'位于({q["x"]},{q["y"]})'
        if k=='unit_dest_area':return self.who(q['slot'])+f'进入x={q["x"]}..{q["x"]+q["w"]-1}, y={q["y"]}..{q["y"]+q["h"]-1}'
        if k=='adjacent':return self.who(q['a'])+'与'+self.who(q['b'])+'正交相邻且都在场'
        if k in ['flag','global']:return '标记'+self.flag(q['addr'])+self.cmp(q)
        if k=='flag_bit':return '标记'+self.flag(q['addr'])+f'的位{q["mask"]}'+('已置' if q.get('set',False) else '未置')
        if k in ['turn_eq_flag','turn_gt_flag']:return '回合'+('=' if k=='turn_eq_flag' else '>')+self.flag(q['addr'])+f'+({q.get("add",0)})'
        if k in ['flag_sum_lt','flag_sum_eq']:return '+'.join(self.flag(a) for a in q['addrs'])+('<' if k.endswith('lt') else '=')+str(q['value'])
        if k=='turn':return '回合'+self.cmp(q)
        if k=='all_units_dead':return '在场敌军全灭' if q else '仍有敌军'
        if k=='all_players_dead':return '在场我方全灭' if q else '仍有我方'
        if k=='map_cell_occupied':return f'格({q["x"]},{q["y"]})占位码={q.get("eq",1)}'
        if k=='slot_pos_cell_occupied':return self.who(q['slot'])+f'所在坐标占位码={q.get("eq",1)}'
        if k=='cell_region_gt':return f'区域({q["x"]},{q["y"]})大小{q["w"]}×{q["h"]}内存在占位码>{q.get("count",1)}'
        if k=='people_compare':return self.who(q['a'])+FIELDS.get(q['field'],q['field'])+('>' if q.get('op','gt')=='gt' else '≥')+self.who(q['b'])+f'+({q.get("add",0)})'
        if k=='any_player_death':return '刚有我方退场'
        if k=='unit_dead':return self.who(q)+'刚退场'
        if k=='unit_count':
            filt=f'槽{q.get("from",0)}～{q.get("to",128)-1}存活在场单位'
            if 'slots' in q:filt+='，限人物槽'+','.join(map(str,q['slots']))
            if 'faction' in q:filt+='，阵营'+self.cmp(q['faction'])
            return filt+'的数量'+self.cmp(q)
        raise ValueError(('Unknown condition',k))
    def act(self,arr):
        out=[]
        for a in arr:
            k=next(iter(a));q=a[k]
            if k in ['message','message_record']:continue
            if k=='result':out.append('判胜' if q=='victory' else '判败')
            elif k in ['flag_set','global_set','flag_or']:out.append(self.flag(q['addr'])+('按位或' if k=='flag_or' else '=')+str(q.get('mask',q.get('value',1 if k=='flag_set' else 0))))
            elif k=='flag_set_from_turn':out.append(self.flag(q['addr'])+f'=当前回合+({q.get("add",0)})')
            elif k in ['spawn','remove']:out.append(('出场：' if k=='spawn' else '撤出：')+self.who(q))
            elif k in ['spawn_range','remove_range','scripted_clear_range']:out.append({'spawn_range':'出场','remove_range':'撤出','scripted_clear_range':'脚本清除'}[k]+f'槽{q["from"]}～{q["to"]-1}'+('（仅在场）' if q.get('alive_only') else ''))
            elif k=='money':out.append(f'资金+{q}')
            elif k=='party_morale':out.append(f'我方士气+{q}')
            elif k=='recruit':out.append('入队：'+','.join(self.who(x) for x in q))
            elif k=='global_add':out.append(self.flag(q['addr'])+f'+={q.get("value",1)}')
            elif k=='random_behavior':out.append('随机AI变化：'+j(q))
            elif k=='party_levels':out.append(f'槽{q["from"]}～{q["to"]-1}等级+{q["add"]}，上限99')
            elif k=='set_faction':out.append(self.who(q['slot'])+'阵营='+str(q['value'])+'（0为我方）')
            elif k=='restore_hp_range':out.append(f'槽{q["from"]}～{q["to"]-1}HP回满')
            elif k in ['set_field','set_field_range']:
                who=self.who(q['slot']) if k=='set_field' else f'槽{q["from"]}～{q["to"]-1}'
                out.append(who+FIELDS.get(q['field'],q['field'])+'='+str(q['value']))
            elif k=='adjust_field_range':out.append(f'槽{q["from"]}～{q["to"]-1}'+FIELDS.get(q['field'],q['field'])+f'→原值×{q.get("mul",1)}/{q.get("div",1)}+({q.get("add",0)})'+(f'，最低{q["min"]}' if 'min' in q else '')+(f'；特殊语义{q["source_semantics"]}' if 'source_semantics' in q else ''))
            elif k=='if':out.append('若'+self.cond(q.get('when',{}))+'：'+self.act(q.get('then',[]))+('；否则：'+self.act(q['else']) if q.get('else') else ''))
            elif k=='choice':out.append('选择分支：'+' ／ '.join(clean(x.get('label','?'))+'→'+self.act(x.get('then',[])) for x in q['options']))
            elif k=='random_choice':out.append('随机等概率分支：'+' ／ '.join(self.act(x) for x in q['options']))
            elif k=='random_slot_dest':out.append(self.who(q['slot'])+'随机出现于'+j(q['options']))
            elif k=='set_map_cell_at_slot':out.append(self.who(q['slot'])+f'坐标的剧情占位标记={q.get("value",1)}')
            elif k=='success_text':out.append('任务文字改为：'+clean(q))
            elif k=='failure_text':out.append('失败文字改为：'+clean(q))
            elif k=='text_digit_from_flags':out.append('按已完成标记更新任务剩余数字')
            elif k=='presentation_sequence':out.append('顺序演出：'+self.act(q))
            elif k in ['phase_movie','phase_flm']:out.append('剧情演出')
            elif k=='phase_move':out.append(self.who(q['slot'])+f'剧情移动至({q["x"]},{q["y"]})')
            elif k=='phase_mine':out.append('脚本爆炸：'+j(q))
            elif k=='mine_bytes':out.append(self.who(q['slot'])+'剧情设雷包：'+j(q['values']))
            elif k=='clear_skills':out.append('清空策略：'+','.join(self.who(x) for x in q))
            elif k=='scripted_attack':out.append(self.who(q['attacker_slot'])+'脚本攻击'+self.who(q['target_slot']))
            else:raise ValueError(('Unknown action',k))
        return '；'.join(out) or '仅剧情对白/提示'


def missions():
    s=['# 47关任务与事件资料（剧透）\n','> 自动生成。关号=index+1；主线1～36，模拟37～40、虚构41～44、彩蛋45～47。不意味着同一存档连续走满47关。以下为源码/模板情报，不是逐关实测保胜攻略。\n',
       '## 阅读规则\n','“任务文字”照录数据；**实际判定看事件规则**。坐标从(0,0)起。人物[数字]为槽位ID。事件按表顺序检查，tick表示行动/位置/退场等事件检查，turn表示新轮事件；“仅一次”和“检查结束”不能忽略。全灭只计算当前在场敌人，之后尚未出场者由脚本另定。初始敌数不含后来增援，数值/阵营仍可能被开场脚本与难度改变。标记F只在本关页编号，附地址对照，不代表可由玩家直接设置。\n',
       '占位码：0为空，1为我方，非我方为阵营+1；特殊脚本占位会覆盖人物坐标的查询。单位未出场与阵亡都可能满足“不在场”，不要擅自换成“必须击杀”。条件间uint32溢出等边界以规则原表与当前解释器为准。\n',
       '## 关卡总表\n']
    s.append(table(['关/index','名称','类型','任务文字','失败文字','时限','部署上限','评分分母'],[[f'{l["index"]+1}/{l["index"]}',f'[{clean(l["name"])}](#mission-{l["index"]})',l['kind']+('/'+l['hidden_mode'] if l['hidden_mode'] else ''),l['success'],l['failure'],l['turn_limit'],l['max_deploy'] if l['party_deploy'] else '固定/脚本',l['difficulty']] for l in M['levels']]))
    for l in M['levels']:
        i=l['index'];t=MissionText(l);dep=l.get('deployment',{})
        s += [f'<a id="mission-{i}"></a>\n',f'## 第{i+1}关 {clean(l["name"])}（index{i}）\n',f'- 任务文字：{clean(l["success"])}；失败文字：{clean(l["failure"])}。\n- 时限字段：{l["turn_limit"]}；地图{l["map"]["width"]}×{l["map"]["height"]}；初始模板敌军{l["enemies"]}。\n- 部署：'+(f'上限{dep.get("max_units",l["max_deploy"])}；强制'+('、'.join(t.who(x) for x in dep.get('forced_slots',[])) or '无')+'；排除'+('、'.join(t.who(x) for x in dep.get('excluded_slots',[])) or '无') if l['party_deploy'] else '固定模板/剧情出场，不套普通选人上限')+'。\n- 保护提示：'+('、'.join(map(clean,l.get('protect',[]))) or '模板未列，仍查下方主角/关键槽败北规则')+'。\n',
              f'- 普通埋雷：{"本关禁用" if i in [14,17] else "按携带与地形许可"}。评分分母：{l["difficulty"]}。\n']
        ch=[c for c in l.get('chests',[]) if c.get('wupin',-1)>=0]
        s.append('- 宝箱：'+('；'.join(f'({c["x"]},{c["y"]}) {c["wupin"]}:{item_name(c["wupin"])}' for c in ch) or '无有效初始宝箱')+'。\n')
        p=l.get('start_phase',{})
        s.append('- 开场出场槽：'+(','.join(str(x) for x in p.get('spawn_slots',[])) or '无额外列表')+'；撤出槽：'+(','.join(str(x) for x in p.get('remove_slots',[])) or '无')+'。\n')
        # Full start/victory payload is preserved separately, including skill rewrites.
        rules=l['triggers'].get('rules',[])
        overrides=list(dict.fromkeys(r['note'].split('可玩性修正：',1)[1] for r in rules if '可玩性修正：' in r.get('note','')))
        if overrides:s.append('> **当前重制版修正**：'+'；'.join(overrides)+'。这不是新增的叛变剧情。\n')
        rows=[]
        for pos,r in enumerate(rules):
            when=t.cond(r.get('when',{}));action=t.act(r.get('then',[]))
            gate=('仅结果未定；' if r.get('requires_result_zero',r.get('on','tick')!='turn') else '可在已写结果后继续；')+('仅一次；' if r.get('once') else '')+('命中后结束本次检查' if r.get('on_match') in ['return','end_function'] else '命中后继续后续规则')
            rows.append([pos+1,r.get('id',''),r.get('on','tick'),when,action,gate])
        s.append(table(['顺序','规则','时机','条件','后果','执行门槛'],rows))
        s.append('### 出场人物模板（不含自选部署覆盖）\n')
        slots={u['slot']:u for u in l.get('slot_pool',[])+l.get('units',[])}
        used=set(u['slot'] for u in l.get('units',[]))|set(p.get('spawn_slots',[]))
        for r in rules:
            def collect(arr):
                for a in arr:
                    if 'spawn' in a:used.add(a['spawn'])
                    if 'spawn_range' in a:used.update(range(a['spawn_range']['from'],a['spawn_range']['to']))
                    if 'if' in a:collect(a['if'].get('then',[]));collect(a['if'].get('else',[]))
                    if 'choice' in a:
                        for x in a['choice']['options']:collect(x.get('then',[]))
            collect(r.get('then',[]))
        s.append(table(['slot','人物','阵营/可控','兵种','级/武/智','坐标','携物'],[[z,clean(u.get('name','')),f'{u.get("faction","?")}/'+('可控' if u.get('control',True) else '自动'),f'{u["bingzhong"]}:{unit_name(u["bingzhong"])}',f'{u.get("level",1)}/{u.get("wuli",0)}/{u.get("zhili",0)}',f'({u.get("x",0)},{u.get("y",0)})','、'.join(item_name(v-1) for v in u.get('item_slots',[]) if v) or '无'] for z in sorted(used) if (u:=slots.get(z)) is not None]))
        if t.flags:s.append('事件标记对照：'+'；'.join(f'{v}=`{k}`' for k,v in t.flags.items())+'。\n')
        # Excludes binary blobs and evidence metadata, retains exact semantic payloads.
        phase={k:{a:b for a,b in l.get(k,{}).items() if a not in ['entry','evidence_id']} for k in ['start_phase','victory_phase'] if isinstance(l.get(k),dict)}
        phase['start_actions']=l.get('start_actions',[])
        s += ['<details><summary>开场/战后精确字段（含剧情重写；技术附录）</summary>\n', '```json\n'+json.dumps(phase,ensure_ascii=False,indent=2)+'\n```\n','</details>\n']
    return '\n'.join(s)



def guide_js():
    terrain=[{'name':q['appearance'],'mods':M['terrain_modifiers'][q['type']],'icon':q['samples'][0]['png'] if q['samples'] else ''} for q in VISUALS['terrains']]
    return '<script>const guideTerrain='+j(terrain)+r""";
const cards=[...document.querySelectorAll('.unit-card')];
const search=document.getElementById('unit-search');
function filterUnits(){const q=search.value.trim().toLowerCase();let n=0;for(const c of cards){const text=c.dataset.search.toLowerCase();c.hidden=!!q&&!( /^\d+$/.test(q)?text.split(' ').includes(q):text.includes(q));if(!c.hidden)n++;}document.getElementById('unit-count').textContent=n+' / '+cards.length+'类';document.querySelector('.unit-index').hidden=!!q;}
search.addEventListener('input',filterUnits);filterUnits();
document.getElementById('range-facing').addEventListener('change',e=>{
 const d=Number(e.target.value);document.querySelectorAll('.range-direction').forEach(p=>p.textContent='伤害图朝'+({0:'北 ↑',1:'南 ↓',2:'西 ←',3:'东 →'}[d]));
 for(const sym of document.querySelectorAll('symbol[data-kind="apply"]')){
  const mat=JSON.parse(sym.dataset.matrix);let body='<rect width="168" height="168" fill="#faf9f2"/>';
  for(let y=0;y<7;y++)for(let x=0;x<7;x++){
   const v=mat[y][x];if(v<=0)continue;let dx=x-3,dy=y-3;
   if(d===1)[dx,dy]=[-dx,-dy];else if(d===2)[dx,dy]=[dy,-dx];else if(d===3)[dx,dy]=[-dy,dx];
   const px=(dx+3)*24,py=(dy+3)*24;
   body+=`<rect x="${px}" y="${py}" width="24" height="24" fill="${v>=100?'#edac60':'#f3d3a2'}"/><text x="${px+12}" y="${py+16}" text-anchor="middle">${v}</text>`;
  }
  let grid='';for(let z=0;z<=7;z++)grid+=`M${z*24},0V168M0,${z*24}H168`;
  sym.innerHTML=body+`<path d="${grid}" fill="none" stroke="#c5c8bb" stroke-width=".7"/><rect x="73" y="73" width="22" height="22" fill="none" stroke="#713c10" stroke-width="3"/>`+(mat[3][3]===0?'<circle cx="84" cy="84" r="4" fill="none" stroke="#713c10"/>':'');
 }
});
for(const details of document.querySelectorAll('.terrain-map')){
 const svg=details.querySelector('svg'),w=Number(svg.dataset.width),h=Number(svg.dataset.height),types=svg.dataset.terrain.split(',').map(Number),readout=details.querySelector('.map-readout');
 details.querySelector('.map-toggle').addEventListener('change',e=>{svg.querySelector('.map-types').style.display=e.target.checked?'inline':'none';});
 function inspect(e){const point=new DOMPoint(e.clientX,e.clientY).matrixTransform(svg.getScreenCTM().inverse()),x=Math.floor((point.x-31)/22),y=Math.floor((point.y-29)/22);if(x<0||y<0||x>=w||y>=h)return;
  const t=types[y*w+x],q=guideTerrain[t],v=q.mods,sign=n=>(n>=0?'+':'')+n;
  readout.innerHTML=`坐标 (${x},${y})　<a class="terrain-badge" href="#terrain-terrain-${t}">${q.icon?`<img class="terrain-icon" src="${q.icon}" alt="T${t}实景">`:''}<b>T${t} · ${q.name}</b></a><br>本体防御${sign(v[2])}% · 新轮HP${sign(v[3])}% / 士气${sign(v[4])} · 火攻${sign(v[0])}% · 滚木/擂石${sign(v[1])}%`;
  const cursor=svg.querySelector('.map-cursor');cursor.setAttribute('x',31+x*22);cursor.setAttribute('y',29+y*22);cursor.setAttribute('visibility','visible');
 }
 svg.addEventListener('pointermove',inspect);svg.addEventListener('click',inspect);
}
"""+'</script>'

def maps_html():
    s=['<section id="terrain-maps"><h1>逐关实景与地形坐标图</h1><p>底图直接取游戏地图美术。悬停或点击格子显示该处真实地形与修正，可勾选叠加类型色块。编号0～9为T0～T9，A～F为T10～T15；金色系T9～T12为恢复地形。横轴x、纵轴y从0起；地图可横向滚动。本图不是当前存档，未叠人物、雷或宝箱。</p>']
    for l in M['levels']:
        m=l['map'];w=m['width'];h=m['height'];size=22
        s.append(f'<details class="terrain-map"><summary>第{l["index"]+1}关 {html.escape(clean(l["name"]))}：{w}×{h}</summary><label><input class="map-toggle" type="checkbox"> 叠加地形类型/编号</label><div class="map-readout" aria-live="polite">悬停或点击地图格子查看实际类型。</div><div class="map-scroll"><svg class="terrain-grid" data-width="{w}" data-height="{h}" data-terrain="{",".join(map(str,m["terrain"]))}" role="img" aria-label="第{l["index"]+1}关实景地形图" width="{w*size+42}" height="{h*size+42}" viewBox="0 0 {w*size+42} {h*size+42}">')
        s.append(f'<image x="31" y="29" width="{w*22}" height="{h*22}" href="{VISUALS["maps"][l["index"]]}" style="image-rendering:pixelated"/><g class="map-types">')
        paths=[[] for _ in range(16)]
        for y in range(h):
            for x in range(w):
                t=m['terrain'][y*w+x];cx=31+x*size;cy=29+y*size
                paths[t].append(f'M{cx},{cy}h22v22h-22z')
        for t,path in enumerate(paths):
            if path:s.append(f'<path d="{"".join(path)}" fill="{TERRAIN_COLORS[t]}" fill-opacity=".85" stroke="#fff" stroke-width=".3"/>')
        for y in range(h):
            xs=' '.join(str(38.4+x*size) for x in range(w))
            chars=''.join(f'{m["terrain"][y*w+x]:X}' for x in range(w))
            s.append(f'<text x="{xs}" y="{44+y*size}">{chars}</text>')
        s.append('</g>')
        for x in range(w):s.append(f'<text x="{42+x*size}" y="17" text-anchor="middle">{x}</text>')
        for y in range(h):s.append(f'<text x="15" y="{45+y*size}" text-anchor="middle">{y}</text>')
        s.append('<rect class="map-cursor" width="22" height="22" fill="none" stroke="#fff3a0" stroke-width="3" visibility="hidden"/></svg></div></details>')
    return ''.join(s)+'</section>'


def render(docs):
    import markdown
    parts=[]
    for name,src in docs.items():
        # Prefix all anchors per document so repeated headings cannot collide.
        content=markdown.markdown(src,extensions=['tables','fenced_code','toc'],extension_configs={'toc':{'toc_depth':'1-3'}})
        prefix=name.replace('.md','')+'-'
        content=re.sub(r'id="([^"]+)"',lambda m:'id="'+('' if m[1].startswith('range-') or m[1] in ['unit-search','unit-count'] else prefix)+m[1]+'"',content)
        content=re.sub(r'href="#([^"]+)"',lambda m:'href="#'+('' if m[1].startswith('range-') else prefix)+m[1]+'"',content)
        parts.append(f'<article id="{name}">'+content+'</article>')
    body='\n<hr>\n'.join(parts)+maps_html()
    for name in docs:
        body=body.replace(f'href="{name}"',f'href="#{name}"')
        body=re.sub(r'href="'+re.escape(name)+r'#([^"]+)"',lambda m:'href="#'+name.replace('.md','')+'-'+m[1]+'"',body)
    body=body.replace('href="guide.html"','href="#top"')
    return '''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>抗日：地雷战 · 当前实现版攻略</title><style>
:root{color-scheme:light}*{box-sizing:border-box}body{margin:0;color:#24312b;background:#f4f2e9;font:16px/1.8 system-ui,-apple-system,"PingFang SC",sans-serif}nav{position:sticky;top:0;z-index:2;display:flex;flex-wrap:wrap;gap:6px 22px;padding:12px 5%;background:#193d32;color:white;box-shadow:0 2px 8px #0002}nav a{color:#fff;text-decoration:none}main{max-width:1360px;padding:30px 4%;margin:auto}h1{font-size:30px;color:#173c30}h2{margin-top:46px;border-bottom:2px solid #afbb9f;padding-bottom:8px}h3{color:#425b3c}a{color:#165d58}blockquote{border-left:4px solid #9a6c30;padding:8px 18px;background:#ece5d5;margin-left:0}pre{padding:18px;overflow:auto;background:#e5e9df;line-height:1.5;border-radius:6px}code{font-family:ui-monospace,monospace}table{border-collapse:collapse;width:100%;font-size:14px;line-height:1.65;margin:18px 0}th{background:#dbe4d3;text-align:left}td,th{padding:9px 11px;border:1px solid #c8d0c0;vertical-align:top}tr:nth-child(even){background:#eef0e7}.table-wrap{overflow-x:auto}summary{cursor:pointer;font-weight:600;padding:12px 0}details{padding:4px 12px;background:#ecefe5;margin:12px 0}hr{margin:58px 0;border:0;border-top:3px solid #aab898}.map-scroll{overflow:auto}svg{background:#f6f6ef}svg text{font:12px ui-monospace,monospace;fill:#13291e}h1,h2,h3,article,section{scroll-margin-top:90px}@media(max-width:700px){main{padding:20px 12px}body{font-size:15px}h1{font-size:24px}td,th{padding:6px;min-width:65px}nav{font-size:14px}}@media print{nav{position:static}body{background:white}main{max-width:none;padding:0}pre{white-space:pre-wrap}table{font-size:10px}h1,h2,h3{break-after:avoid}tr{break-inside:avoid}a{color:inherit}}

.terrain-icon{width:40px;height:40px;image-rendering:pixelated;vertical-align:middle;border:1px solid #788575;border-radius:3px}.terrain-badge{display:inline-flex;align-items:center;gap:8px;min-width:76px;text-decoration:none}.terrain-empty{display:inline-flex;width:40px;height:40px;align-items:center;justify-content:center;background:repeating-linear-gradient(45deg,#ddd6c9,#ddd6c9 5px,#f2ede4 5px,#f2ede4 10px);color:#766b58;font-size:12px}.terrain-cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,360px),1fr));gap:20px}.terrain-card,.unit-card{border:1px solid #c4cbb8;border-radius:9px;padding:20px;background:#fffdf7;min-width:0}.terrain-card h2,.unit-card h2{margin:0 0 12px;font-size:22px;border:none;padding:0}.terrain-card small,.muted{color:#6c7367}.terrain-samples{display:flex;flex-wrap:wrap;gap:12px;min-height:112px}.terrain-samples figure{margin:0;text-align:center}.terrain-samples img{image-rendering:pixelated;border:1px solid #aeb79d}.terrain-samples figcaption{font-size:11px;line-height:1.5}.unit-cards{display:grid;gap:26px}.unit-card h2 small{font-size:14px;font-weight:400;color:#6b7568}.range-direction{font-size:13px;color:#77714e;margin:4px 0}.range-row{display:flex;gap:18px;overflow-x:auto;padding:6px 0 14px}.range-figure{margin:0;flex:none}.range-figure figcaption{font-size:14px;margin-bottom:8px;color:#595d4f}.range-chart{display:block}.range-chart text{font:11px system-ui,sans-serif;fill:#553417}.range-chart .actor{fill:white;font-size:14px;font-weight:bold}.range-definitions{position:absolute;width:0;height:0;overflow:hidden}.range-controls{display:flex;flex-wrap:wrap;gap:14px 24px;align-items:center;background:#e2e9db;border-radius:8px;padding:16px}.range-controls input,.range-controls select{font:inherit;padding:5px 8px;max-width:100%;border:1px solid #acb89e;border-radius:4px}.range-controls label{min-width:0}.unit-index{font-size:14px;line-height:2.2}.map-types{display:none}.map-readout{padding:10px 0;min-height:68px;font-size:14px;line-height:1.6}.map-readout img{width:36px;height:36px}.terrain-grid{touch-action:pan-x pan-y}.map-toggle{width:17px;height:17px;vertical-align:middle}[hidden]{display:none!important}section[id^="terrain-terrain-"],section[id^="unit_ranges-unit-"]{scroll-margin-top:110px}@media(max-width:700px){.terrain-card,.unit-card{padding:14px}.range-controls{padding:12px}.range-controls input{width:200px}.unit-card h2{font-size:20px}nav{gap:4px 16px}.terrain-samples{gap:8px}h1,h2,h3,article,section{scroll-margin-top:120px}}

</style></head><body id="top"><nav><b>地雷战 · 攻略</b><a href="#README.md">核心规则与战术</a><a href="#terrain.md">地形图鉴</a><a href="#unit_ranges.md">兵种范围图</a><a href="#reference.md">全数值表</a><a href="#missions.md">47关任务事件</a><a href="#terrain-maps">地形坐标图</a></nav><main>'''+re.sub(r'(<table>.*?</table>)',r'<div class="table-wrap">\1</div>',body,flags=re.S)+'</main>'+guide_js()+'</body></html>\n'


def build():
    prepare_visuals()
    docs={'README.md':(OUT/'README.md').read_text(),'terrain.md':terrain_guide(),'unit_ranges.md':unit_ranges(),'reference.md':reference(),'missions.md':missions()}
    sources=['data/map.json','godot/data/m2.json','godot/data/m4.json','tools/build_player_guide.py','tools/test_player_guide.py','godot/tests/AttackAreaPresentationTest.gd','godot/tests/YulaiCrateFactionTest.gd','tools/trigger_data.py','tools/repair_yulai_save.py','tools/test_repair_yulai_save.py','tools/verify_original.py','docs/guide/README.md']+[str(p.relative_to(ROOT)) for p in sorted((ROOT/'godot/scripts').rglob('*.gd'))]+[f'godot/assets/map/map_{i:02}.png' for i in range(47)]
    hashes={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in sources}
    manifest={'date':'2026-10-29','baseline_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'scope':'current implementation documentation, not campaign completion evidence','counts':{'unit_slots':96,'named_units':sum(bool(x['name']) for x in M['unit_types']),'terrains':16,'skills':16,'item_slots':160,'named_nonplaceholder_items':sum(bool(clean(x['name'])) and clean(x['name'])!='物品' for x in M['items'].values()),'mine_bases':10,'mine_products':40,'materials':10,'towns':19,'people_templates':40,'missions':47,'trigger_rules':sum(len(l['triggers'].get('rules',[])) for l in M['levels']),'select_masks':16,'apply_masks':48,'terrain_maps':47,'terrain_types_with_verified_icons':sum(bool(t['samples']) for t in VISUALS['terrains']),'unit_range_cards':len(unit_groups())},'source_sha256':hashes}
    content={k:v for k,v in docs.items() if k!='README.md'}
    content['guide.html']=render(docs)
    content['terrain_samples.json']=json.dumps([{**q,'samples':[{k:v for k,v in a.items() if k!='png'} for a in q['samples']]} for q in VISUALS['terrains']],ensure_ascii=False,indent=2)+'\n'
    # Exact payloads remain available for edge-ordering/nested scripts; no binary data.
    content['mission_rules.json']=json.dumps([{'index':l['index'],'name':l['name'],'triggers':l['triggers'],'start_phase':l.get('start_phase',{}),'start_actions':l.get('start_actions',[]),'victory_phase':l.get('victory_phase',{}),'waves':l.get('waves',[])} for l in M['levels']],ensure_ascii=False,indent=2)+'\n'
    manifest['output_sha256']={k:hashlib.sha256(v.encode()).hexdigest() for k,v in content.items()}
    content['manifest.json']=json.dumps(manifest,ensure_ascii=False,indent=2)+'\n'
    return content,manifest


def validate_data():
    assert len(M['unit_types'])==len(M['unit_move'])==96
    assert len(M['levels'])==47 and len(N['towns'])==19 and len(N['people'])==40
    assert len(M['items'])==160 and len(M['terrain_modifiers'])==16
    assert all(len(r)==5 for r in M['terrain_modifiers'])
    assert all(len(r)==16 for r in M['unit_move'].values())
    assert len(M['select_ranges'])==16 and len(M['apply_ranges'])==48
    assert all(len(r)==9 and all(len(x)==9 for x in r) for r in M['select_ranges'].values())
    assert all(len(r)==7 and all(len(x)==7 for x in r) for r in M['apply_ranges'].values())
    for i,u in enumerate(M['unit_types']):assert u==N['units'][str(i)],('unit mismatch',i)
    for i,x in M['items'].items():
        assert all(x[k]==N['items'][i][k] for k in x if k in N['items'][i]),('item mismatch',i)
    for l in M['levels']:assert len(l['map']['terrain'])==l['map']['width']*l['map']['height']
    assert attack(M['unit_types'][4],w=100)==124
    assert attack(M['unit_types'][4],w=80)==96
    assert rank(0)==0 and rank(299)==9 and rank(300)==10


def main():
    global M,N,SN
    M=load('m4');N=load('m2');SN=dict(zip(KEYS,[clean(x['name']) for x in M['skills']]))
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--check',action='store_true');args=p.parse_args()
    validate_data();content,manifest=build()
    if args.check:
        # The baseline records generation provenance, not freshness. A commit
        # alone must not invalidate unchanged source/output fingerprints.
        recorded=OUT/'manifest.json'
        if recorded.exists():
            manifest['baseline_commit']=json.loads(recorded.read_text())['baseline_commit']
            content['manifest.json']=json.dumps(manifest,ensure_ascii=False,indent=2)+'\n'
        bad=[n for n,v in content.items() if not (OUT/n).exists() or (OUT/n).read_text()!=v]
        if bad:raise SystemExit('Stale/missing generated guide files: '+', '.join(bad))
    else:
        OUT.mkdir(exist_ok=True)
        for n,v in content.items():(OUT/n).write_text(v)
    print(('CHECK OK' if args.check else 'GENERATED')+' '+j(manifest['counts']))

if __name__=='__main__':main()
