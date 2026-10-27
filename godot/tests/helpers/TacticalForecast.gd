extends RefCounted

# Player-planning aid only. Disposable shadow nodes, public board/rules, no live
# resolver calls, no RNG state, no future scenario triggers or unrevealed units.
# Offensive enemy skills assume success (conservative); uncertain player skills
# do not remove hypothetical enemies. This is NOT an original-rules oracle.
class ShadowBoard extends "res://scripts/Battle.gd":
	var occupied:Dictionary={}
	var mine_events:Array=[]
	func refresh_occupancy() -> void:
		occupied.clear()
		for u in units:
			if u.alive and u.placed:occupied[Vector2i(u.x,u.y)]=u
	func _unit_at(t:Vector2i) -> Node2D:return occupied.get(t)
	func _is_occupied(t:Vector2i,ignore:Node2D=null,pass_allies:=false,mover:Node2D=null) -> bool:
		var u=_unit_at(t)
		if u==null or u==ignore:return false
		return not (pass_allies and mover!=null and same_faction(u,mover))
const Unit=preload("res://scripts/BattleUnit.gd")
const AI=preload("res://scripts/battle/OriginalAI.gd")
const Rules=preload("res://scripts/battle/CombatRules.gd")

static func copy_board(source):
	var shadow=ShadowBoard.new()
	shadow.data=source.data
	shadow.level=source.level
	shadow.turn=source.turn
	shadow.map_w=source.map_w;shadow.map_h=source.map_h
	shadow.terrain=source.terrain
	shadow.mines=source.mines.duplicate(true)
	for live in source.units:
		if not live.alive or not live.placed:continue
		var u=Unit.new()
		u.data=live.data.duplicate(true)
		for field in Unit.STATE_FIELDS:
			var value=live.get(field)
			u.set(field,value.duplicate(true) if value is Dictionary or value is Array else value)
		shadow.add_child(u)
		shadow.units.append(u)
		if u.side=="player":shadow.player_units.append(u)
		else:shadow.enemy_units.append(u)
	shadow.refresh_occupancy()
	return shadow

static func prepare_ai(b,u) -> void:
	for i in range(8):
		if u.behavior in [2,3,6] and b.unit_by_slot(u.target_slot)==null:u.behavior=7 if u.behavior==3 else 1
		elif u.behavior in [4,5] and u.x==u.target_x and u.y==u.target_y:u.behavior=7 if u.behavior==4 else 0
		elif u.behavior in [8,10] and u.x==u.target_x and u.y==u.target_y and (u.home_x!=u.target_x or u.home_y!=u.target_y):
			var old:=Vector2i(u.home_x,u.home_y)
			u.home_x=u.target_x;u.home_y=u.target_y;u.target_x=old.x;u.target_y=old.y
		else:break

static func plan(b,u) -> Dictionary:
	prepare_ai(b,u)
	var stations:Array=b.compute_reachable(u).keys()
	stations.sort_custom(func(a,c):return a.y<c.y or (a.y==c.y and a.x<c.x))
	for cmd in AI.TABLE[u.behavior&15]:
		var choice:Dictionary=AI._command(b,u,int(cmd),stations)
		if choice.is_empty():continue
		if u.behavior==7 and choice.kind=="attack":u.behavior=2;u.target_slot=int(choice.target)
		return choice
	return {"kind":"wait","station":Vector2i(u.x,u.y)}

static func apply_action(b,u,action:Dictionary,enemy:=false) -> void:
	var station:Vector2i=action.get("station",Vector2i(u.x,u.y))
	var origin:=Vector2i(u.x,u.y)
	if station!=origin:
		var reachable:Dictionary=b.compute_reachable(u)
		if not reachable.has(station):u.acted=true;return
		for step in b._path_to(station,origin):
			u.direction=b._facing(Vector2i(u.x,u.y),step)
			u.x=step.x;u.y=step.y;u.moved=true
			b.refresh_occupancy()
			var index:int=b._mine_at(step)
			if index<0:continue
			if int(u.bingzhong)==46:b.mines.remove_at(index);continue
			if int(b.mines[index].get("code",b.mines[index].get("mine_id",0)))/10!=0:continue
			detonate(b,step,u.slot)
			u.acted=true
			return # the real mine interrupts movement AND the planned action
	var kind:String=action.kind
	if kind in ["wait","move"]:u.acted=true;return
	if kind=="mine":
		var code:int=action.mine
		var raw:int=u.mine_slots.find(code+1)
		if raw>=0 and b._mine_place_tiles(u,code).has(action.tile):
			u.mine_slots[raw]=0
			var definition:Dictionary=b.data.mines[code%10]
			b.mines.append({"tile":action.tile,"mine":definition,"mine_id":code%10,"code":code,"low":1,"owner_side":u.side,"apply_fw":int(definition.apply_fw)})
		u.acted=true
		return
	var target=b.unit_by_slot(int(action.get("target",-1)))
	var tile:Vector2i=action.get("tile",Vector2i(target.x,target.y) if target!=null else station)
	var sid:=int(action.get("skill",-1))
	var definition:Dictionary={}
	var apply:=0
	var direction:int=b._facing(station,tile)
	var e1:=0;var e2:=0
	if kind=="attack":apply=Rules.attack_apply(int(b.unit_class(u).apply),u.attack_count)
	elif kind=="skill":
		definition=b.data.skills[sid]
		apply=Rules.skill_apply(int(definition.apply_fw),b._skill_count(u,sid))
		e1=Rules.skill_effect(int(u.data.zhili),int(definition.para1),b._skill_count(u,sid))
		e2=Rules.skill_effect(int(u.data.zhili),int(definition.para2),b._skill_count(u,sid))
	else:
		definition=b.data.items[str(action.item)]
		apply=int(definition.apply_fw);e1=int(definition.para1);e2=int(definition.para2)
		direction=u.direction
	var support:bool=(kind=="skill" and sid in [0,1,2,12]) or (kind=="item" and int(action.item)<21)
	var attack_power:int=b._effective_attack(u)
	u.acted=true
	for cell in b._apply_tiles(tile,apply,direction):
		var v=b._unit_at(cell.tile)
		if v==null or support!=b.same_faction(u,v):continue
		if not enemy and kind=="skill" and sid not in [0,1,2,15]:
			if 30+2*(int(u.data.zhili)-int(v.data.zhili))<100:continue
		var hp:int=e1*int(cell.pct)/100
		var morale:int=e2*int(cell.pct)/100
		if kind=="attack":
			hp=mini(v.hp,maxi(1,maxi(v.hp/20,Rules.damage(attack_power,b._effective_defense(v),int(cell.pct)))))
			morale=b._morale_loss(hp,v.max_hp)
			u.attack_count+=1
		elif kind=="skill" and sid in [3,4,5]:hp=hp*(100+int(b.data.terrain_modifiers[b._terrain_at(cell.tile)][0 if sid==3 else 1]))/100
		if support:
			v.hp=mini(v.max_hp,v.hp+hp);v.morale=mini(100,v.morale+morale)
			if sid==12:v.acted=false;v.integrity=mini(100,v.integrity+20);v.defense_integrity=mini(100,v.defense_integrity+20)
		else:
			if kind=="skill":
				if sid==7:v.defense_integrity=maxi(20,v.defense_integrity*7/10);continue
				if sid==8:v.integrity=maxi(50,v.integrity*7/10);continue
				if sid==10:
					v.data.level=maxi(1,int(v.data.level)-1)
					v.max_hp=int(b.unit_class(v).tili)+(int(v.data.level)-1)*int(b.unit_class(v).tili_plus)
					v.hp=mini(v.hp,v.max_hp);continue
				if sid==11:v.acted=true;v.moved=true;continue
			v.hp=maxi(0,v.hp-hp);v.morale=maxi(0,v.morale-morale)
			v.data.last_attacker_slot=u.slot
			if v.hp<=0 or v.morale<=0:v.alive=false

	b.refresh_occupancy()

static func detonate(b,tile:Vector2i,walker:int) -> void:
	# Public, deterministic mine geometry only. No live resolver, scenario,
	# random roll, XP oracle, or instruction for the real enemy to step here.
	var queue:Array=[tile]
	var seen:Dictionary={}
	while not queue.is_empty():
		var at:Vector2i=queue.pop_front()
		if seen.has(at):continue
		seen[at]=true
		var index:int=b._mine_at(at)
		if index<0:continue
		var record:Dictionary=b.mines[index]
		var definition:Dictionary=record.get("mine",b.data.mines[int(record.get("mine_id",0))%10])
		b.mines.remove_at(index)
		var victims:Array=[]
		for cell in b._mine_area(at,int(definition.apply_fw)):
			if b._mine_at(cell.tile)>=0 and not seen.has(cell.tile):queue.append(cell.tile)
			var target=b._unit_at(cell.tile)
			if target==null:continue
			var amount:int=maxi(0,int(definition.weili)*int(cell.pct)/100)
			if int(definition.shiqi_or_tili)==0:
				amount=mini(amount,target.hp);target.hp-=amount
			else:
				amount=mini(amount,target.morale);target.morale-=amount
			victims.append({"slot":target.slot,"amount":amount,"alive":target.hp>0 and target.morale>0})
			if target.hp<=0 or target.morale<=0:target.alive=false
		b.mine_events.append({"walker":walker,"tile":at,"code":record.get("code",0),"victims":victims})
		b.refresh_occupancy()

static func evaluate(source,slot:int,action:Dictionary) -> Dictionary:
	return evaluate_sequence(source,[{"slot":slot,"action":action}])

static func evaluate_sequence(source,actions:Array) -> Dictionary:
	var shadow=copy_board(source)
	for entry in actions:
		var actor=shadow.unit_by_slot(int(entry.slot))
		if actor==null:continue
		apply_action(shadow,actor,entry.action)
	# Unused controlled units will wait when the real player ends the phase.
	for u in shadow.player_units:
		if u.control and not u.auto:u.acted=true
	var plans:Array=[]
	for step in range(256):
		var next=null
		for u in shadow.units:
			if u.alive and not u.acted and (next==null or u.slot<next.slot):next=u
		if next==null:break
		var choice:Dictionary=plan(shadow,next)
		var path:Array=[]
		if choice.get("station",Vector2i(next.x,next.y))!=Vector2i(next.x,next.y):
			shadow.compute_reachable(next)
			path=shadow._path_to(choice.station,Vector2i(next.x,next.y))
		plans.append({"slot":next.slot,"choice":choice,"path":path})
		apply_action(shadow,next,choice,true)
	var cost:=0
	var health:Dictionary={}
	for live in source.player_units:
		if not live.alive:continue
		var predicted=null
		for u in shadow.player_units:
			if u.slot==live.slot:predicted=u;break
		if predicted==null:continue
		var remaining:int=predicted.hp
		var loss:int=live.hp-remaining
		var critical:bool=live.slot==0 or source._bot_is_protected(live)
		# Team casualties also lower the hero's level. Never knowingly sacrifice
		# a teammate merely to make a damage-only utility score look attractive.
		cost+=loss*2+maxi(0,predicted.max_hp/3-remaining)*3
		if not predicted.alive:cost+=100000 if critical else 5000
		if critical:cost+=maxi(0,predicted.max_hp/2-remaining)*8
		health[live.slot]={"hp":remaining,"morale":predicted.morale,"alive":predicted.alive}
	var enemy_loss:=0
	for live in source.enemy_units:
		if not live.alive:continue
		var predicted=null
		for u in shadow.enemy_units:
			if u.slot==live.slot:predicted=u;break
		if predicted!=null:enemy_loss+=live.hp-predicted.hp+(150 if not predicted.alive else 0)
	var events:Array=shadow.mine_events.duplicate(true)
	shadow.free()
	return {"cost":cost,"units":health,"plans":plans,"enemy_loss":enemy_loss,"mine_events":events}
