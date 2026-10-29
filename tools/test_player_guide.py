#!/usr/bin/env python3
"""Limited documentation QA, not a gameplay or 47-mission test."""
import importlib.util
import base64
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
from html.parser import HTMLParser
from PIL import Image, ImageChops

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('guide',ROOT/'tools/build_player_guide.py')
g=importlib.util.module_from_spec(spec);spec.loader.exec_module(g)
g.M=g.load('m4');g.N=g.load('m2');g.SN=dict(zip(g.KEYS,[g.clean(x['name']) for x in g.M['skills']]))
g.validate_data()
for rule in g.M['levels'][17]['triggers']['rules']:
    if rule['id'].startswith('occupy_'):
        assert len(rule['then'])==2 and '0x7D1648' not in json.dumps(rule['then']), 'Yulai crate override lost'
subprocess.run(['python3',str(ROOT/'tools/build_player_guide.py'),'--check'],check=True,cwd=ROOT)

class CheckHTML(HTMLParser):
    def __init__(self):super().__init__();self.ids=[];self.links=[];self.images=[];self.maps=0;self.charts=0;self.symbols={};self.uses=[];self.unit_cards=[];self.terrain_cards=[]
    def handle_starttag(self,tag,attrs):
        d=dict(attrs)
        if 'id' in d:self.ids.append(d['id'])
        if tag=='a' and 'href' in d:self.links.append(d['href'])
        if tag in ['img','image']:self.images.append(d.get('src',d.get('href','')))
        if tag=='svg' and d.get('class')=='terrain-grid':self.maps+=1
        if tag=='svg' and d.get('class')=='range-chart':self.charts+=1
        if tag=='symbol':self.symbols[d['id']]=json.loads(d['data-matrix'])
        if tag=='use':self.uses.append(d['href'])
        if tag=='section' and d.get('class')=='unit-card':self.unit_cards.append(d['id'])
        if tag=='section' and d.get('class')=='terrain-card':self.terrain_cards.append(d['id'])
p=CheckHTML();p.feed((g.OUT/'guide.html').read_text())
assert len(p.ids)==len(set(p.ids)), 'duplicate HTML IDs'
assert all(x[1:] in p.ids for x in p.links if x.startswith('#')), 'missing anchor'
assert p.maps==47 and all(x.startswith('data:image/png;base64,') for x in p.images), 'images must be self-contained'
assert len(p.terrain_cards)==16 and len(p.unit_cards)==52 and p.charts==260
assert len(p.symbols)==64 and all(x[1:] in p.symbols for x in p.uses)
for kind,key,count in [('select','select_ranges',16),('apply','apply_ranges',48)]:
    for i in range(count):assert p.symbols[f'range-{kind}-{i}']==g.M[key][str(i)]
assert sorted(i for ids in g.unit_groups().values() for i in ids)==list(range(90)), 'all named variants covered'
g.prepare_visuals()
assert [q['type'] for q in g.VISUALS['terrains'] if not q['samples']]==[3,8]
samples=0
for q in g.VISUALS['terrains']:
    for a in q['samples']:
        im=Image.open(io.BytesIO(base64.b64decode(a['png'].split(',')[1]))).convert('RGB')
        source=Image.open(ROOT/f'godot/assets/map/map_{a["mission_index"]:02}.png').convert('RGB')
        x,y=a['x']*48,a['y']*48
        assert ImageChops.difference(im,source.crop((x,y,x+48,y+48))).getbbox() is None
        l=g.M['levels'][a['mission_index']]['map']
        assert l['terrain'][a['y']*l['width']+a['x']]==q['type']
        samples+=1
assert all(not x.startswith(('https:','http:')) for x in p.links),'unexpected network links'

out=ROOT/'out/evidence/player_guide_20261027';out.mkdir(parents=True,exist_ok=True)
cases=[]
for u in g.M['unit_types']:
    for lv in [1,15,30]:cases.append({'unit':u,'level':lv,'attack':g.attack(u,lv),'defense':g.defense(u,lv),'hp':g.hp(u,lv)})
cp=out/'formula_cases.json';cp.write_text(json.dumps(cases,ensure_ascii=False))
script=out/'GuideFormulaCheck.gd'
script.write_text('''extends SceneTree
const Rules=preload("res://scripts/battle/CombatRules.gd")
const State=preload("res://scripts/m2/GameState.gd")
func _initialize() -> void:
\tvar cases:Array=JSON.parse_string(FileAccess.get_file_as_string(CASE_PATH))
\tvar state=State.new()
\tvar types:Dictionary={}
\tfor c in cases:types[str(int(c.unit.index))]=c.unit
\tstate.data={"units":types}
\tvar checks:=0
\tfor c in cases:
\t\tvar member:Dictionary={"wuli":80,"level":int(c.level)}
\t\tassert(Rules.attack_power(member,c.unit,100,100,1,0)==int(c.attack))
\t\tassert(Rules.defense_power(member,c.unit,100,0,0,100)==int(c.defense))
\t\tassert(state.max_hp_for(int(c.unit.index),int(c.level))==int(c.hp))
\t\tchecks+=3
\tassert(Rules.skill_level(0)==0)
\tassert(Rules.skill_level(299)==9)
\tassert(Rules.skill_level(300)==10)
\tassert(Rules.skill_effect(61,120,1)==73)
\tassert(Rules.hit_experience(1,1)==8)
\tassert(Rules.kill_experience(1,1)==12)
\tassert(Rules.hit_experience(1,6)==32)
\tassert(Rules.kill_experience(1,6)==80)
\tchecks+=8
\tprint("GUIDE_FORMULAS_OK ",checks," assertions; ",cases.size()," scenarios")
\tquit(0)
'''.replace('CASE_PATH',json.dumps(str(cp))))
godot=os.environ.get('GODOT') or shutil.which('godot') or '/Applications/Godot.app/Contents/MacOS/Godot'
r=subprocess.run([godot,'--headless','--path',str(ROOT/'godot'),'--log-file',str(out/'godot.log'),'--script',str(script)],capture_output=True,text=True,timeout=60)
(out/'formula_stdout.log').write_text(r.stdout);(out/'formula_stderr.log').write_text(r.stderr)
assert r.returncode==0 and 'GUIDE_FORMULAS_OK 872 assertions' in r.stdout,(r.returncode,r.stdout,r.stderr)
assert not any(t in r.stdout+r.stderr for t in ['SCRIPT ERROR','Parse Error','Assertion failed']), 'runtime diagnostics'
print(r.stdout.strip())
report={'scope':'documentation-only; no campaign execution; no user save reads/writes','data_validation':'PASS','generation_freshness':'PASS','html_ids_unique':len(p.ids),'internal_links_resolved':sum(x.startswith('#') for x in p.links),'terrain_maps':p.maps,'terrain_pixel_samples':samples,'unit_range_cards':len(p.unit_cards),'range_charts':p.charts,'range_templates':len(p.symbols),'formula_scenarios':len(cases),'godot_assertions':872,'godot_exit':r.returncode}
(out/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False))
