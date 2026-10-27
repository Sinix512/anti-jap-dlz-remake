extends RefCounted

# Test player only: plan a whole visible player phase on disposable boards.
# No RNG reads, scenario lookahead, hidden reserves or changes to the resolver.
# Keeping offensive AND defensive beams avoids the old per-actor deadlock:
# each rifleman used to reject advancing because his allies had not moved yet.
const Forecast=preload("res://tests/helpers/TacticalForecast.gd")
const Rules=preload("res://scripts/battle/CombatRules.gd")
const WIDTH=12

static func candidates(b,u) -> Array:
	var origin:=Vector2i(u.x,u.y)
	var nearest=b._nearest_side(u,"enemy")
	if nearest==null:return [{"kind":"wait","station":origin,"tile":origin,"utility":0}]
	if int(b.level.index)==5 and b.alive_enemies()>1:
		# Join the main squad before hunting the lone eastern guard. The old
		# nearest-enemy objective took the medic around the north-east houses.
		var central=null;var distance:=999999
		for enemy in b.enemy_units:
			if not enemy.alive or enemy.slot==50:continue
			var d:int=absi(enemy.x-u.x)+absi(enemy.y-u.y)
			if d<distance:central=enemy;distance=d
		if central!=null:nearest=central
	var goal:=Vector2i(nearest.x,nearest.y)
	if int(b.level.index)==5 and u.slot==6:
		var wounded=null;var priority:=-1
		for ally in b.player_units:
			if not ally.alive or ally.slot in [0,6] or not ally.control:continue
			var need:int=ally.max_hp-ally.hp
			if need>priority:wounded=ally;priority=need
		if wounded!=null:goal=Vector2i(wounded.x,wounded.y+2)
	if b.move_cost(u.bingzhong,b._terrain_at(goal))>=99:goal=b._adjacent_free(goal,u)
	var route:Array=b._astar(origin,goal,u,true)
	var stations:Array=[] if u.moved or u.acted else b.compute_reachable(u).keys()
	stations.push_front(origin)
	var choices:Array=[]
	for station in stations:
		# Do not knowingly walk onto a visible mine. A planted ambush is handled
		# by a separate legal action, not by pretending mines do not exist.
		if station!=origin and b._mine_at(station)>=0:continue
		if int(b.level.index)==5:
			# The two real reinforcements are not controllable until turn8.
			# Rally before entering the northern gun line, rather than allowing
			# the initial five to outrun both rifleman and medic.
			if b.turn<=10 and u.slot<5 and station.y<9:continue
			if u.slot==0 and b.alive_enemies()>2:
				var front:int=b.map_h
				for ally in b.player_units:
					if ally.alive and ally.slot!=0:front=mini(front,ally.y)
				if station.y<mini(b.map_h-1,front+3):continue
		u.x=station.x;u.y=station.y;b.refresh_occupancy()
		var progress:int=(origin.distance_to(goal)-station.distance_to(goal))*6
		if route.has(station):progress=maxi(progress,(route.find(station)+1)*6)
		if u.slot==0:progress/=2
		choices.append({"kind":"wait","station":station,"tile":station,"utility":progress})
		for tile in b._select_tiles(u,u.select):
			var a:Dictionary={"kind":"attack","station":station,"tile":tile}
			var value:=effect_value(b,u,a)
			if value>0:a.utility=value+progress/3;choices.append(a)
		for sid in [0,1,2,3,4,5,7,8,11,15]:
			if b._skill_count(u,sid)<=0:continue
			for tile in b._skill_targets(u,b.data.skills[sid]):
				var a:Dictionary={"kind":"skill","skill":sid,"station":station,"tile":tile}
				var value:=effect_value(b,u,a)
				if value>0:a.utility=value+progress/3;choices.append(a)
		for raw in u.item_slots:
			var iid:=int(raw)-1
			if iid<0 or (iid>=21 and iid not in range(41,57)):continue
			var it:Dictionary=b.data.items[str(iid)]
			for tile in b._item_targets(u,it,"apply" if iid<21 else "throw"):
				var a:Dictionary={"kind":"item","item":iid,"station":station,"tile":tile}
				var value:=effect_value(b,u,a)
				if value>0:a.utility=value+progress/3;choices.append(a)
		u.x=origin.x;u.y=origin.y;b.refresh_occupancy()
	# Retain different action/target combinations, not twelve copies of the
	# same heal at adjacent endpoints. Always retain true retreat endpoints.
	choices.sort_custom(func(a,c):return int(a.utility)>int(c.utility))
	var out:Array=[];var seen:Dictionary={}
	for a in choices:
		var key:String=a.kind+str(a.get("skill",a.get("item",-1)))+str(a.tile)
		if seen.has(key):continue
		seen[key]=true;out.append(a)
		if out.size()>=8:break
	var waits:Array=choices.filter(func(a):return a.kind=="wait")
	waits.sort_custom(func(a,c):return immediate_risk(b,u,a.station)<immediate_risk(b,u,c.station))
	for a in waits.slice(0,3):out.append(a)
	out.append({"kind":"wait","station":origin,"tile":origin,"utility":0})
	return out

static func effect_value(b,u,a:Dictionary) -> int:
	var apply:=0;var e1:=0;var e2:=0;var sid:=-1
	var direction:int=b._facing(Vector2i(u.x,u.y),a.tile)
	if a.kind=="attack":apply=Rules.attack_apply(int(b.unit_class(u).apply),u.attack_count)
	elif a.kind=="skill":
		sid=int(a.skill);var sk:Dictionary=b.data.skills[sid]
		apply=Rules.skill_apply(int(sk.apply_fw),b._skill_count(u,sid))
		e1=Rules.skill_effect(int(u.data.zhili),int(sk.para1),b._skill_count(u,sid))
		e2=Rules.skill_effect(int(u.data.zhili),int(sk.para2),b._skill_count(u,sid))
	else:
		var it:Dictionary=b.data.items[str(a.item)]
		apply=int(it.apply_fw);e1=int(it.para1);e2=int(it.para2);direction=u.direction
	var support:bool=(a.kind=="skill" and sid<3) or (a.kind=="item" and int(a.item)<21)
	var value:=0
	for cell in b._apply_tiles(a.tile,apply,direction):
		var v=b._unit_at(cell.tile)
		if v==null or support!=b.same_faction(u,v):continue
		if not support and int(b.level.index)==5 and v.slot==50 and b.alive_enemies()>1:continue
		var hp:int=e1*int(cell.pct)/100;var morale:int=e2*int(cell.pct)/100
		if support:
			value+=mini(v.max_hp-v.hp,hp)*2+mini(100-v.morale,morale)
			continue
		if a.kind=="attack":
			hp=maxi(1,maxi(v.hp/20,Rules.damage(b._effective_attack(u),b._effective_defense(v),int(cell.pct))))
			morale=b._morale_loss(mini(hp,v.hp),v.max_hp)
		elif a.kind=="skill":
			# A phase plan may not rely on winning an unknown random roll.
			if sid!=15 and 30+2*(int(u.data.zhili)-int(v.data.zhili))<100:continue
			if sid in [3,4,5]:hp=hp*(100+int(b.data.terrain_modifiers[b._terrain_at(cell.tile)][0 if sid==3 else 1]))/100
			if sid==7:value+=maxi(0,v.defense_integrity-maxi(20,v.defense_integrity*7/10));continue
			if sid==8:value+=maxi(0,v.integrity-maxi(50,v.integrity*7/10));continue
			if sid==11:value+=80 if not v.acted else 0;continue
		value+=mini(v.hp,hp)*2+mini(v.morale,morale)+ (350 if hp>=v.hp or morale>=v.morale else 0)
	return value

static func immediate_risk(b,u,tile:Vector2i) -> int:
	var old:=Vector2i(u.x,u.y);u.x=tile.x;u.y=tile.y
	var risk:=0
	for e in b.enemy_units:
		if not e.alive:continue
		var distance:int=absi(e.x-tile.x)+absi(e.y-tile.y)
		if distance>e.move+8:continue
		if b._in_attack_range(e,u):risk+=b.compute_damage(e,u)
	u.x=old.x;u.y=old.y
	return risk

static func sequence_risk(b) -> int:
	var risk:=0
	for u in b.player_units:
		if not u.alive:continue
		var hit:=immediate_risk(b,u,Vector2i(u.x,u.y))
		risk+=hit+(2000 if hit>=u.hp else 0)*(10 if u.slot==0 else 1)
	return risk

static func plan(source,slots:Array) -> Array:
	var beam:Array=[{"board":Forecast.copy_board(source),"actions":[],"utility":0,"risk":0}]
	for slot in slots:
		var branches:Array=[]
		for node in beam:
			var u=node.board.unit_by_slot(int(slot))
			if u==null or u.acted or not u.control:
				branches.append(node);continue
			for a in candidates(node.board,u):
				var board=Forecast.copy_board(node.board)
				var actor=board.unit_by_slot(int(slot))
				Forecast.apply_action(board,actor,a)
				var actions:Array=node.actions.duplicate();actions.append({"slot":slot,"action":a})
				branches.append({"board":board,"actions":actions,"utility":int(node.utility)+int(a.utility),"risk":sequence_risk(board)})
			node.board.free()
		beam=[]
		# Different safety weights preserve both coordinated assaults and
		# withdrawals until all allies have had a chance to act.
		for weight in [0,3]:
			branches.sort_custom(func(a,c):return int(a.utility)-int(a.risk)*weight>int(c.utility)-int(c.risk)*weight)
			var added:=0
			for node in branches:
				if beam.has(node):continue
				beam.append(node);added+=1
				if added>=WIDTH/4:break
		# Score a bounded candidate pool with the full visible enemy phase.
		# Pure geometric risk misses enemies that move before shooting.
		var pool:Array=[]
		for weight in [0,3]:
			branches.sort_custom(func(a,c):return int(a.utility)-int(a.risk)*weight>int(c.utility)-int(c.risk)*weight)
			for node in branches.slice(0,12):
				if not pool.has(node):pool.append(node)
		for node in pool:
			node.cost=int(Forecast.evaluate_sequence(source,node.actions).cost)
		for safety_only in [false,true]:
			pool.sort_custom(func(a,c):return (-int(a.cost) if safety_only else int(a.utility)-int(a.cost)*2)>(-int(c.cost) if safety_only else int(c.utility)-int(c.cost)*2))
			var added:=0
			for node in pool:
				if beam.has(node):continue
				beam.append(node);added+=1
				if added>=WIDTH/4:break
		for node in branches:
			if not beam.has(node):node.board.free()
	var chosen:Array=[];var best:=-2147483648
	var best_cost:=0
	for node in beam:
		var forecast:Dictionary=Forecast.evaluate_sequence(source,node.actions)
		var score:int=int(node.utility)-int(forecast.cost)*2
		if score>best:best=score;chosen=node.actions;best_cost=int(forecast.cost)
		node.board.free()
	print("JOINT_SCORE T",source.turn," utility_cost=",best," incoming=",best_cost)
	return chosen
