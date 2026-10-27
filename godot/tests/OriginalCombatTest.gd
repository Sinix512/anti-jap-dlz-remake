extends SceneTree
const State=preload("res://scripts/m2/GameState.gd")
const Builder=preload("res://scripts/m4/LevelBuilder.gd")
const Rules=preload("res://scripts/battle/CombatRules.gd")
class Observer extends RefCounted:
	var status_text:=""
	var ticks:=0
	func on_tick() -> void:ticks+=1
	func on_unit_moved(_u) -> void:pass
	func on_unit_died(_u) -> void:pass
	func check_end() -> bool:return false
var failures:=0
var checks:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label_:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("COMBAT_FAIL "+label_)
func run() -> void:
	for row in [[1,0],[45,1],[135,2],[300,3]]:
		check(Rules.attack_apply(1,int(row[0]))==4+int(row[1]),"attack range rank %d"%row[0])
		check(Rules.skill_apply(40,int(row[0]))==40+int(row[1]),"skill range rank %d"%row[0])
	check(Rules.attack_apply(1,44)==5,"normal attack mask anticipates next practice")
	var m2:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/m2.json"))
	var m4:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json"))
	var gs=State.new();gs.new_game(m2);gs.setup_m4(m4)
	var b=load("res://scripts/Battle.gd").new();root.add_child(b)
	b.setup(m4,Builder.build(m4,m2,0,[gs.protagonist_member()]),load("res://assets/font/hzk16.fnt"),gs.battle_context())
	b.fast_sim=true;b.set_process(false);b.animations_enabled=false;b.sfx_enabled=false
	var observer=Observer.new();b.scenario=observer
	var hero=b.unit_by_slot(0);var target=b.unit_by_slot(40)
	hero.set_tile(10,10);target.set_tile(10,9)
	check(b._skill_targets(hero,b.data.skills[0]).has(Vector2i(11,10)),"player skill empty landing")
	check(not b._skill_targets(hero,b.data.skills[0],true).has(Vector2i(11,10)),"AI targets remain occupied")
	for sid in range(16):
		target.set_tile(10,6 if sid==15 else 9)
		hero.data.zhili=100;hero.data.level=10;hero.data.xp=0;hero.hp=hero.max_hp
		hero.morale=100;hero.acted=false;hero.moved=false;hero.item_slots=[0,0,0,0,0,0,0,0]
		hero.skill_counts[b.SKILL_KEYS[sid]]=1
		target.side="player" if sid in [0,1,2,12] else "enemy"
		target.data.faction=0 if target.side=="player" else 1
		target.data.level=10;target.data.zhili=0;target.hp=10000;target.max_hp=20000;target.morale=50
		target.defense_integrity=60 if sid==12 else 100;target.integrity=60 if sid==12 else 100
		target.acted=true;target.moved=true;target.alive=true;target.item_slots=[2,3,0,0,0,0,0,0]
		if sid==9:hero.item_slots=[82,0,91,0,0,0,0,0]
		b.selected=hero;b.active_skill_id=sid;b.active_skill=b.data.skills[sid]
		var effect1:int=b.active_skill.para1;var effect2:int=b.active_skill.para2
		var hp_before:int=target.hp
		var expected_hp:=hp_before
		if sid in [3,4,5,13,14,15]:
			var modifier:=0
			if sid in [3,4,5]:modifier=int(b.data.terrain_modifiers[b._terrain_at(Vector2i(10,9))][0 if sid==3 else 1])
			expected_hp-=maxi(0,effect1*(100+modifier)/100)
		b._execute_skill_at(Vector2i(target.x,target.y))
		match sid:
			0:check(target.hp==hp_before+effect1 and target.morale==50,"supply exact")
			1:check(target.hp==hp_before and target.morale==mini(100,50+effect2),"encourage exact")
			2:check(target.hp==hp_before+effect1 and target.morale==mini(100,50+effect2),"medicine exact")
			3,4,5,13,15:check(target.hp==expected_hp and target.morale==50,"damage skill %d exact channels"%sid)
			6:check(target.hp==hp_before and target.morale==maxi(0,50-effect2),"intimidate morale only")
			7:check(target.defense_integrity==70,"harass defense integrity")
			8:check(target.integrity==70,"sabotage attack integrity")
			9:check(hero.item_slots==[82,2,91,0,0,0,0,0] and target.item_slots[0]==0 and target.item_slots[1]==3,"plunder actor fills then compacts; target deliberately keeps hole")
			10:check(target.data.level==9 and target.hp<=target.max_hp,"counterintelligence loses one level")
			11:check(target.acted and target.moved,"feint consumes current action")
			12:check(not target.acted and not target.moved and target.integrity==80 and target.defense_integrity==80,"supervise renews action and repairs")
			14:check(target.hp==expected_hp and target.morale==maxi(0,50-effect2),"poison two channels")
		check(hero.acted and int(hero.skill_counts[b.SKILL_KEYS[sid]])==2,"skill %d practice once per target"%sid)
	check(observer.ticks==16,"all skill action hooks synchronous")
	hero.data.level=99;hero.data.xp=90;await b._gain_xp(hero,15)
	check(hero.data.level==99 and hero.data.xp==5,"level99 experience modulo")
	hero.data.level=98;hero.data.xp=90;await b._gain_xp(hero,250)
	check(hero.data.level==99 and hero.data.xp==40,"cap multiple levels modulo")
	# Script gunner45 remains absent but uses the ordinary resolver and updates pool.
	b.scenario=null
	hero.data.faction=1;target.side="enemy";target.data.faction=2
	target.set_tile(hero.x,hero.y-1)
	check(not b.same_faction(hero,target) and b.attack_targets(hero).has(Vector2i(target.x,target.y)),"faction1 and faction2 are hostile despite same UI side")
	target.data.faction=1
	check(b.same_faction(hero,target) and not b.attack_targets(hero).has(Vector2i(target.x,target.y)),"exact faction equality filters attacks")
	hero.data.faction=0
	hero.hp=hero.max_hp;hero.morale=100
	var before:int=b.get_slot_field(45,"attack_count")
	b.scripted_attack(45,0)
	check(b.unit_by_slot(45)==null and b.get_slot_field(45,"attack_count")==before+1,"absent scripted gunner normal practice")
	check(int(hero.data.get("last_attacker_slot",-1))==45,"scripted attack records attacker")
	# Isolated native selector contract; not claimed to be a reachable L05
	# plan bug (behavior7's self-heal commands precede ally-heal commands).
	var ai=preload("res://scripts/battle/OriginalAI.gd")
	for unit in b.units:
		unit.alive=(unit==hero or unit==target)
	hero.set_tile(4,2);target.set_tile(5,3)
	hero.data.faction=0;target.data.faction=0;hero.hp=50;target.hp=50
	hero.max_hp=100;target.max_hp=100
	var targets:Dictionary=ai._targets(b,hero,Vector2i(4,3),0)
	check(targets.keys()==[Vector2i(4,2),Vector2i(5,3)],"401708 candidate center retains original occupancy and row-major scan")
	check(targets[Vector2i(4,2)]==hero and targets[Vector2i(5,3)]==target,"401708 actual caster stays in old tile")
	check(Vector2i(hero.x,hero.y)==Vector2i(4,2),"AI query never relocates caster")
	hero.set_tile(14,14);target.alive=false
	check(ai._targets(b,hero,Vector2i(4,3),0).is_empty(),"hypothetical center has no invented self occupant")
	# Native 44BC50 copy survives nested selector failures: the third supplied
	# reachable station, not an expanded/cleared global search mask, must win.
	hero.set_tile(3,3);target.set_tile(6,3);target.alive=true
	hero.hp=100;target.hp=50;hero.skill_counts.buji=1
	b._clear_native_range()
	var visible_mask:PackedByteArray=b.native_dark_mask.duplicate()
	var plan:Dictionary=ai._command(b,hero,7,[Vector2i(3,2),Vector2i(2,3),Vector2i(4,3),Vector2i(3,4)])
	check(plan.get("station")==Vector2i(4,3) and int(plan.get("target",-1))==int(target.slot),"44BC50 nested selectors retain independent station set")
	check(b.native_dark_mask==visible_mask and b.native_dark_mask.count(0)==b.map_w*b.map_h,"AI work range never flashes in visible native mask")
	b.queue_free();await process_frame;await create_timer(0.15).timeout
	print("ORIGINAL_COMBAT checks=",checks," failures=",failures)
	quit(1 if failures else 0)
