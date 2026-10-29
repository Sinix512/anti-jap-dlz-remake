extends SceneTree
# Synthetic isolated fixtures, NOT a campaign/playability claim. No saves.
const State=preload("res://scripts/m2/GameState.gd")
const Builder=preload("res://scripts/m4/LevelBuilder.gd")
const Rules=preload("res://scripts/battle/CombatRules.gd")
class Observer extends RefCounted:
	var status_text:=""
	func on_tick() -> void:pass
	func on_unit_moved(_u) -> void:pass
	func on_unit_died(_u) -> void:pass
	func check_end() -> bool:return false
var checks:=0
var failures:=0
var fx_positions:Array=[]
var capture_fx:=false
var b
var hero
var victims:Array=[]
var geometry_cases:=0
var resolver_cases:=0
var fx_cases:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		if failures<=20:push_error("ATTACK_AREA_FAIL "+label)
# Independent oracle: inverse rotation (production rotates source offsets).
func oracle(u:Dictionary,count:int,center:Vector2i,d:int) -> Dictionary:
	var rank:=0
	for threshold in [1,10,25,45,70,100,135,175,225,300]:
		if count+1>=threshold:rank+=1
	var index:int=int(u.apply)*4+ceili(float(rank)/3.0)-1
	var mat:Array=b.data.apply_ranges[str(index)]
	var result:Dictionary={}
	for y in range(maxi(0,center.y-3),mini(b.map_h,center.y+4)):
		for x in range(maxi(0,center.x-3),mini(b.map_w,center.x+4)):
			var dx:int=x-center.x;var dy:int=y-center.y
			var sx:=dx;var sy:=dy
			match d:
				1:sx=-dx;sy=-dy
				2:sx=-dy;sy=dx
				3:sx=dy;sy=-dx
			var pct:int=int(mat[sy+3][sx+3])
			if pct>0:result[Vector2i(x,y)]=pct
	return result
func as_dict(cells:Array) -> Dictionary:
	var out:Dictionary={}
	var prev:=Vector2i(-1,-1)
	for cell in cells:
		check(cell.tile.y>prev.y or (cell.tile.y==prev.y and cell.tile.x>prev.x),"row-major unique cells")
		out[cell.tile]=int(cell.pct);prev=cell.tile
	return out
func set_actor(uid:int,count:int,pos:Vector2i) -> void:
	hero.bingzhong=uid;hero.select=int(b.data.unit_types[uid].select)
	hero.set_tile(pos.x,pos.y);hero.alive=true;hero.acted=false;hero.moved=false
	hero.attack_count=count;hero.data.level=99;hero.data.xp=0;hero.data.wuli=100
	hero.attack_bonus=2000;hero.morale=100;hero.integrity=100
	hero.hp=10000;hero.max_hp=10000;hero.direction=1;hero.data.faction=0
	hero.display_action_lock=false
	b.busy=false;b.finished_flag=false;b.phase="player";b.mode="idle";b.selected=null
func layout(center:Vector2i) -> void:
	for i in range(victims.size()):
		var v=victims[i];var t:=center+Vector2i(i%9-4,i/9-4)
		v.set_tile(t.x,t.y);v.hp=10000;v.max_hp=10000;v.alive=b._in_bounds(t) and t!=Vector2i(hero.x,hero.y)
		v.data.faction=0 if i%5==0 else 1
		v.side="player" if i%5==0 else "enemy"
		v.control=(i==40) # One ready friendly prevents unrelated auto-round AI.
		v.data.level=1;v.morale=100;v.defense_integrity=100;v.data.erase("last_attacker_slot")
func expected_hp(area:Dictionary) -> Array:
	var out:Array=[];var power:int=b._effective_attack(hero)
	for v in victims:
		var t:=Vector2i(v.x,v.y);var hp:=10000
		if v.alive and area.has(t) and int(v.data.faction)!=0:
			hp-=mini(hp,maxi(1,maxi(hp/20,Rules.damage(power,b._effective_defense(v),int(area[t])))))
		out.append(hp)
	return out
func check_hp(expected:Array,label:String) -> void:
	for i in range(victims.size()):check(victims[i].hp==expected[i],label+" HP cell "+str(i))
func on_fx(child:Node) -> void:
	if capture_fx and child is AnimatedSprite2D:fx_positions.append(child.position)
func run() -> void:
	var m2:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/m2.json"))
	var m4:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json"))
	var gs=State.new();gs.new_game(m2);gs.setup_m4(m4)
	b=load("res://scripts/Battle.gd").new();root.add_child(b)
	b.setup(m4,Builder.build(m4,m2,0,[gs.protagonist_member()]),load("res://assets/font/hzk16.fnt"),gs.battle_context())
	b.set_process(false);b.fast_sim=true;b.animations_enabled=false;b.sfx_enabled=false
	b.scenario=Observer.new();b.mines.clear();b.chests.clear()
	hero=b.unit_by_slot(0)
	for u in b.units:
		if u!=hero:u.alive=false;u.visible=false
	for i in range(81):
		victims.append(b._spawn_unit({"slot":40+i,"name":"范围测试","bingzhong":1,"side":"enemy","faction":1,"x":0,"y":0,"hp":10000,"max_hp":10000,"level":1,"wuli":10,"control":false}))
	# Every slot, four rotations, both sides of all three expansion thresholds,
	# interior and clipped corner. Also independently check the actual S mask.
	for uid in range(96):
		set_actor(uid,0,Vector2i(10,10))
		b._target_native_range(hero,hero.select,false,"test")
		var select_mat:Array=m4.select_ranges[str(hero.select)]
		for y in range(b.map_h):
			for x in range(b.map_w):
				var dx:=x-10;var dy:=y-10
				var allowed:bool=absi(dx)<=4 and absi(dy)<=4 and int(select_mat[dy+4][dx+4])>0
				check((b.native_dark_mask[y*b.map_w+x]==0)==allowed,"S mask %d (%d,%d)"%[uid,x,y])
		for count in [0,43,44,133,134,298,299,300]:
			hero.attack_count=count
			for d in range(4):
				for center in [Vector2i(10,9),Vector2i(0,0)]:
					var expect:=oracle(m4.unit_types[uid],count,center,d)
					check(as_dict(b.normal_attack_cells(hero,center,d))==expect,"area %d/%d/%d/%s"%[uid,count,d,center]);geometry_cases+=1
	# Real resolver, not just helper: enemies, allies, empty border and a
	# practice threshold crossed during multi-target damage.
	for uid in range(96):
		for count in [43,44,134,299]:
			for d in range(4):
				set_actor(uid,count,Vector2i(2,10));layout(Vector2i(10,10))
				var area:=oracle(m4.unit_types[uid],count,Vector2i(10,10),d)
				var expected:=expected_hp(area);var hits:=0
				for i in range(expected.size()):
					if int(expected[i])<10000:hits+=1
				await b._resolve_attack_at(hero,Vector2i(10,10),d)
				check_hp(expected,"resolver %d/%d/%d"%[uid,count,d])
				check(hero.attack_count==count+hits and hero.acted,"per enemy practice, frozen area")
				resolver_cases+=1
	# Actual attack-mode hover contract: cannot preview outside S, busy, modal,
	# enemy turn or after cancellation; hover must not turn or train the actor.
	set_actor(16,299,Vector2i(10,10));b.selected=hero;b._on_attack()
	b.hover_tile=Vector2i(10,6)
	var before_direction:int=hero.direction
	check(as_dict(b.attack_preview_cells())==oracle(m4.unit_types[16],299,b.hover_tile,0),"hover same area")
	check(hero.direction==before_direction and hero.attack_count==299,"hover is read only")
	b.hover_tile=Vector2i(10,10);check(b.attack_preview_cells().is_empty(),"blind zone no preview")
	b.hover_tile=Vector2i(10,6);b.busy=true;check(b.attack_preview_cells().is_empty(),"busy no preview");b.busy=false
	b.phase="enemy";check(b.attack_preview_cells().is_empty(),"enemy phase no preview");b.phase="player"
	b.action_panel=Control.new();b.add_child(b.action_panel);check(b.attack_preview_cells().is_empty(),"modal no preview")
	b._close_action_panel();b._cancel();check(b.attack_preview_cells().is_empty(),"cancel clears preview")
	# Real presentation path captures actual FX node centers. Retain sparse
	# enemies/allies/empty cells: effects cover the area, only enemies lose HP.
	b.fx_root.child_entered_tree.connect(on_fx)
	b.fast_sim=false;b.animations_enabled=true;b.presentation_in_headless=true;b.animation_speed=1
	for row in [[4,0,0,false],[3,44,3,false],[9,134,2,false],[16,299,1,false],[10,43,0,false],[10,44,0,false],[16,299,0,true]]:
		var uid:int=row[0];var count:int=row[1];var d:int=row[2]
		var pos:=Vector2i(2,4) if row[3] else Vector2i(10,10)
		set_actor(uid,count,pos)
		var vec:Vector2i=[Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT][d]
		var aim:=pos
		for radius in range(1,5):
			var offset:=vec*radius
			if int(m4.select_ranges[str(hero.select)][offset.y+4][offset.x+4])>0:aim=pos+offset;break
		check(aim!=pos,"fixture aims at legal S landing")
		layout(aim)
		var area:=oracle(m4.unit_types[uid],count,aim,d)
		var expected:=expected_hp(area)
		b.selected=hero;b._on_attack();b.hover_tile=aim
		check(as_dict(b.attack_preview_cells())==area,"real attack preview")
		fx_positions.clear();capture_fx=true
		b._on_map_click(aim)
		while b.busy or b.action_resolution_depth>0:await process_frame
		capture_fx=false
		var expected_positions:Array=[]
		for t in area:expected_positions.append(Vector2(t*48)+Vector2(24,24))
		check(fx_positions.size()==expected_positions.size(),"one FLM per damage cell")
		for point in expected_positions:check(fx_positions.has(point),"FX center matches cell "+str(point))
		check_hp(expected,"presented attack")
		check(b.attack_preview_cells().is_empty() and not b.busy and b.action_resolution_depth==0,"action releases aim/input lock")
		fx_cases+=1
	# Speed0 and disabled animation must not suppress or expand real damage.
	for variant in [0,1]:
		set_actor(16,299,Vector2i(10,10));layout(Vector2i(10,6))
		var expected:=expected_hp(oracle(m4.unit_types[16],299,Vector2i(10,6),0))
		b.animation_speed=0 if variant==0 else 1;b.animations_enabled=variant==0
		fx_positions.clear();capture_fx=true
		await b._perform_attack_at(hero,Vector2i(10,6));capture_fx=false
		check(fx_positions.is_empty(),"no visual FX at speed0/disabled")
		check_hp(expected,"no animation damage")
	b.queue_free();await process_frame;await create_timer(0.15).timeout
	print("ATTACK_AREA_PRESENTATION checks=",checks," failures=",failures," geometry_cases=",geometry_cases," resolver_cases=",resolver_cases," fx_cases=",fx_cases)
	if failures==0:print("ATTACK_AREA_PRESENTATION_OK")
	quit(1 if failures else 0)
