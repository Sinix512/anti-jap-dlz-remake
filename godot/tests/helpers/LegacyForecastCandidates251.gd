extends RefCounted
# Frozen pre252 candidate reference, source SHA 7a7db94fb69415ce20d81fe8ce4fef164347515546eafa743fa93c1a066253ac.
# Test-only parity reference, NOT a combat or campaign oracle.
const Rules=preload("res://scripts/battle/CombatRules.gd")
var focus_enemy_slot:=40
var bridge_hold:=3
func tactic_enabled(flag:String) -> bool:
	var args:=OS.get_cmdline_user_args()
	return args.has(flag) or (not args.has("--baseline-tactics") and flag in ["--stone-ambush","--stone-cache","--north-lure","--cache-book","--bridge-mines","--bridge-grenades"])

func legal_stations(b,u) -> Array:
	var stations:Array=[] if u.moved or u.acted else b.compute_reachable(u).keys()
	stations.push_front(Vector2i(u.x,u.y))
	if int(b.level.index)==7 and b.turn<=bridge_hold:
		stations=stations.filter(func(tile):return tile.x>=25 and tile.y>=(29 if u.slot==0 else 27))
	return stations

# Use the actual wait command: pickup and T510 are action-tail operations,
# not a side effect of reversible pre-movement or raw acted flag writes.

func generate(b,u,move_goal:=Vector2i(-1,-1)) -> Dictionary:
	var origin:=Vector2i(u.x,u.y)
	var nearest=b.unit_by_slot(48) if int(b.level.index)==5 and u.slot<5 else null
	if nearest==null:nearest=b._nearest_side(u,"enemy")
	if nearest==null:return {"candidates":[],"shortlist":[{"kind":"wait","station":origin,"tile":origin,"utility":0}]}
	var goal:Vector2i=Vector2i(nearest.x,nearest.y) if move_goal.x<0 else move_goal
	if b.move_cost(u.bingzhong,b._terrain_at(goal))>=99:goal=b._adjacent_free(goal,u)
	var route:Array=b._astar(origin,goal,u,true)
	var candidates:Array=[]
	for station in legal_stations(b,u):
		if b._mine_at(station)>=0:continue
		if int(b.level.index)==5 and u.slot==0 and b.alive_enemies()>2:
			# A commander with repeated casualty penalties stays behind the
			# actual frontline; one-phase forecasts do not cover the next wave.
			var front:int=b.map_h
			for ally in b.player_units:
				if ally.alive and ally.slot in [1,2,3,4,5,6]:front=mini(front,ally.y)
			if station.y<mini(b.map_h-1,front+2):continue
			if tactic_enabled("--north-lure") and b.alive_enemies()<=3 and station.x<8:continue
		if int(b.level.index)==7 and u.slot==0:
			# A weak commander should remain behind the recruited medic, not
			# walk into the next wave because one enemy phase looks survivable.
			var medic=b.unit_by_slot(7)
			if medic!=null and b.alive_enemies()>3 and station.y<mini(b.map_h-1,medic.y+2):continue
		if int(b.level.index)==6 and u.slot==0:
			var girl=b.unit_by_slot(7)
			if girl!=null and b.turn<17 and station.y<girl.y:continue
		u.x=station.x;u.y=station.y
		var pace:=(32 if b.turn>=20 else 16) if int(b.level.index)==7 else (32 if int(b.level.index)==5 and b.turn>=13 and u.slot!=0 else 8)
		if int(b.level.index)==5 and b.alive_enemies()<=3 and (OS.get_cmdline_user_args().has("--north-push") or (tactic_enabled("--north-lure") and u.slot!=0)):pace=128
		var progress:int=(absi(origin.x-goal.x)+absi(origin.y-goal.y)-absi(station.x-goal.x)-absi(station.y-goal.y))*pace
		if route.has(station):progress=maxi(progress,(route.find(station)+1)*pace)
		var base:Dictionary={"kind":"wait","station":station,"tile":station,"utility":progress}
		candidates.append(base)
		for target in b.attack_targets(u).values():
			var a:Dictionary={"kind":"attack","station":station,"tile":Vector2i(target.x,target.y),"target":target.slot}
			a.utility=area_estimate(b,u,a).value+progress/3
			candidates.append(a)
		for sid in ([0,1,2,3,4,5,6,7,8,10,11,13,14,15] if int(b.level.index)==7 else [0,1,2,3,4,5,13,14,15]):
			if b._skill_count(u,sid)<=0:continue
			for tile in b._skill_targets(u,b.data.skills[sid]):
				var a:Dictionary={"kind":"skill","skill":sid,"station":station,"tile":tile}
				if sid<3:a.utility=support_value(b,u,tile,sid)+progress/3
				else:a.utility=area_estimate(b,u,a).value+progress/3
				if a.utility>progress/3:candidates.append(a)
		for raw in u.item_slots:
			var iid:int=int(raw)-1
			if iid<0 or (iid>=21 and (iid<41 or iid>56)):continue
			var it:Dictionary=b.data.items[str(iid)]
			for tile in b._item_targets(u,it,"throw" if iid>=41 else "apply"):
				var a:Dictionary={"kind":"item","item":iid,"station":station,"tile":tile}
				if iid<21:
					a.utility=0
					for cell in b._apply_tiles(tile,int(it.apply_fw),u.direction):
						var ally=b._unit_at(cell.tile)
						if ally!=null and b.same_faction(u,ally):a.utility+=mini(ally.max_hp-ally.hp,int(it.para1)*int(cell.pct)/100)
				else:a.utility=area_estimate(b,u,a).value
				a.utility+=progress/3
				if a.utility>progress/3:candidates.append(a)
		u.x=origin.x;u.y=origin.y
	# First retain utility-diverse endpoints; exact AI forecast is expensive.
	candidates.sort_custom(func(a,c):return a.utility>c.utility)
	var shortlist:Array=[]
	var seen:Dictionary={}
	for a in candidates:
		var key:String=str(a.station)+a.kind+str(a.get("skill",a.get("item",-1)))
		if seen.has(key):continue
		seen[key]=true;shortlist.append(a)
		if shortlist.size()>=12:break
	if int(b.level.index)>=6:
		# High-utility healing must not crowd every retreat out of the shortlist.
		var waits:=0
		for a in candidates:
			if a.kind!="wait":continue
			var key:String=str(a.station)+a.kind+str(a.get("skill",a.get("item",-1)))
			if seen.has(key):continue
			seen[key]=true;shortlist.append(a);waits+=1
			if waits>=12:break
	shortlist.append({"kind":"wait","station":origin,"tile":origin,"utility":0})
	return {"candidates":candidates,"shortlist":shortlist}

func support_value(b,u,tile:Vector2i,sid:int) -> int:
	var sk:Dictionary=b.data.skills[sid]
	var e1:int=Rules.skill_effect(int(u.data.zhili),int(sk.para1),b._skill_count(u,sid))
	var e2:int=Rules.skill_effect(int(u.data.zhili),int(sk.para2),b._skill_count(u,sid))
	var value:=0
	for cell in b._apply_tiles(tile,Rules.skill_apply(int(sk.apply_fw),b._skill_count(u,sid)),b._facing(Vector2i(u.x,u.y),tile)):
		var ally=b._unit_at(cell.tile)
		if ally==null or not b.same_faction(u,ally):continue
		value+=mini(ally.max_hp-ally.hp,e1*int(cell.pct)/100)+mini(100-ally.morale,e2*int(cell.pct)/100)*2
	return value

func area_estimate(b,u,action:Dictionary) -> Dictionary:
	var direction:int=b._facing(Vector2i(u.x,u.y),action.tile)
	var apply:=0
	var effect1:=0
	var effect2:=0
	var sid:=-1
	if action.kind=="attack":apply=Rules.attack_apply(int(b.unit_class(u).apply),u.attack_count)
	elif action.kind=="skill":
		sid=int(action.skill)
		var skill:Dictionary=b.data.skills[sid]
		var count:int=b._skill_count(u,sid)
		apply=Rules.skill_apply(int(skill.apply_fw),count)
		effect1=Rules.skill_effect(int(u.data.zhili),int(skill.para1),count)
		effect2=Rules.skill_effect(int(u.data.zhili),int(skill.para2),count)
	else:
		var it:Dictionary=b.data.items[str(action.item)]
		apply=int(it.apply_fw);effect1=int(it.para1);effect2=int(it.para2);direction=u.direction
	var value:=0
	var killed:Array=[]
	for cell in b._apply_tiles(action.tile,apply,direction):
		var victim=b._unit_at(cell.tile)
		if victim==null or b.same_faction(victim,u):continue
		var hp:int=effect1*int(cell.pct)/100
		var morale:int=effect2*int(cell.pct)/100
		var probability:=100
		if action.kind=="attack":
			hp=maxi(1,maxi(int(victim.hp)/20,Rules.damage(b._effective_attack(u),b._effective_defense(victim),int(cell.pct))))
			morale=b._morale_loss(mini(hp,int(victim.hp)),victim.max_hp)
		elif action.kind=="skill":
			if sid in [3,4,5]:hp=hp*(100+int(b.data.terrain_modifiers[b._terrain_at(cell.tile)][0 if sid==3 else 1]))/100
			if sid!=15:probability=clampi(30+2*(int(u.data.zhili)-int(victim.data.zhili)),0,100)
			# Status utility is not HP damage and must not receive a fake kill
			# bonus. Repeated suppression must not starve real focus fire.
			if sid==7:hp=0;value+=maxi(0,victim.defense_integrity-maxi(20,victim.defense_integrity*7/10))*probability/200
			if sid==8:hp=0;value+=maxi(0,victim.integrity-maxi(50,victim.integrity*7/10))*probability/200
			if sid==10:hp=0;value+=12*probability/100
			if sid==11:hp=0;value+=(180 if u.slot in [4,6,7,8] else 30)*probability/100 if not victim.acted else 0
		var lethal:bool=hp>0 and (hp>=victim.hp or morale>=victim.morale)
		if int(b.level.index)==4 and victim.slot==focus_enemy_slot:value+=2000*probability/100
		value+=(mini(hp,int(victim.hp))+mini(morale,int(victim.morale))/2+150*(1 if lethal else 0))*probability/100
		if lethal and probability==100:killed.append(victim)
	return {"value":value,"killed":killed}
