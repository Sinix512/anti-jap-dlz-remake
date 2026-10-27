extends SceneTree
const State=preload("res://scripts/m2/GameState.gd")
const Builder=preload("res://scripts/m4/LevelBuilder.gd")
const Rules=preload("res://scripts/battle/CombatRules.gd")
class ActionObserver extends RefCounted:
	var ticks:=0
	var status_text:=""
	func on_tick() -> void: ticks+=1
	func on_unit_moved(_u) -> void: pass
	func check_end() -> bool: return false
var failures:=0
var checks:=0
var b
var hero
var enemy
var observer
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error("ITEM_FAIL "+label)
func use_item(iid: int, tile: Vector2i) -> void:
	hero.item_slots=[iid+1,0,0,0,0,0,0,0]
	hero.acted=false;hero.moved=false
	b.selected=hero;b.active_item_id=iid
	b._execute_item_at(tile)
func run() -> void:
	var m2:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/m2.json"))
	var m4:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json"))
	var gs=State.new();gs.new_game(m2);gs.setup_m4(m4)
	b=load("res://scripts/Battle.gd").new();root.add_child(b)
	b.setup(m4,Builder.build(m4,m2,0,[gs.protagonist_member()]),load("res://assets/font/hzk16.fnt"),gs.battle_context())
	b.fast_sim=true;b.set_process(false);b.animations_enabled=false;b.sfx_enabled=false
	observer=ActionObserver.new();b.scenario=observer
	hero=b.unit_by_slot(0);enemy=b.unit_by_slot(40)
	hero.set_tile(10,10);enemy.set_tile(11,10)
	var walnut:Dictionary=b.data.items["1"]
	var mask:Dictionary=b._item_targets(hero,walnut,"food")
	check(mask.has(Vector2i(10,10)),"food always permits self")
	check(mask.has(Vector2i(11,10)),"food landing can be enemy")
	check(mask.has(Vector2i(10,9)),"food landing can be empty")
	check(b._item_targets(hero,b.data.items["41"],"throw").has(Vector2i(10,10)),"throw permits self landing")
	hero.hp=1;hero.morale=20
	var xp_before:int=hero.data.xp
	var attacks:int=hero.attack_count
	var skills:Dictionary=hero.skill_counts.duplicate()
	var hp_gain:=mini(hero.max_hp-1,int(walnut.para1))
	var morale_gain:=mini(80,int(walnut.para2))
	use_item(1,Vector2i(10,10))
	check(hero.hp==1+hp_gain and hero.morale==20+morale_gain,"food restores HP and morale independently")
	check(hero.data.xp==xp_before and hero.attack_count==attacks and hero.skill_counts==skills,"food no XP or practice")
	check(hero.acted and not hero.item_slots.has(2),"food consumes one and action")
	check(observer.ticks==1,"food action T510 synchronous once")
	# para4 is animation, not an effect selector.
	b.data.items["1"]=walnut.duplicate();b.data.items["1"].para4=17
	hero.hp=1;hero.morale=20
	use_item(1,Vector2i(10,10))
	check(hero.hp==1+hp_gain,"para4 never suppresses HP channel")
	hero.hp=1;hero.morale=20
	use_item(21,Vector2i(10,10))
	check(hero.hp==1 and hero.morale==20 and hero.acted and not hero.item_slots.has(22),"original wine bug: consumes without recovery")
	var before_enemy:int=enemy.hp
	use_item(1,Vector2i(11,10))
	check(enemy.hp==before_enemy and hero.acted and not hero.item_slots.has(2),"enemy food landing consumed but filters effects")
	use_item(1,Vector2i(10,9))
	check(hero.acted and not hero.item_slots.has(2),"empty cast consumes one item")
	hero.data.wuli=100;hero.data.zhili=100
	var tick_before:int=observer.ticks
	use_item(33,Vector2i(10,10))
	check(hero.data.wuli==100 and hero.data.zhili==100 and hero.acted and not hero.item_slots.has(34),"maxed book still consumes")
	check(observer.ticks==tick_before+1 and hero.data.xp==xp_before,"book action hook, no XP")
	# Throwing has no minimum damage and no ordinary-attack morale channel.
	b.data.items["41"]=b.data.items["41"].duplicate()
	b.data.items["41"].para1=0;b.data.items["41"].para2=100
	enemy.hp=50;enemy.max_hp=100;enemy.morale=10
	use_item(41,Vector2i(11,10))
	check(enemy.hp==50 and enemy.morale==0 and enemy.alive,"zero HP damage never triggers throw retirement")
	check(enemy.data.last_attacker_slot==0,"throw records last attacker")
	b.data.items["41"].para1=1;b.data.items["41"].para2=0
	enemy.morale=10
	use_item(41,Vector2i(11,10))
	check(enemy.hp==49 and enemy.morale==10,"throw no implicit gun morale loss")
	b.data.items["41"].para1=0
	use_item(41,Vector2i(11,10))
	check(enemy.hp==49,"throw no minimum one damage")
	b.data.items["41"].para1=1;b.data.items["41"].para2=100
	enemy.hp=49;enemy.morale=1
	var expected_xp:int=Rules.kill_experience(int(hero.data.level),int(enemy.data.level))>>1
	var gained_before:int=hero.gained_xp
	# Observer does not implement the real retirement hooks; use the real scenario here.
	b.scenario=null
	use_item(41,Vector2i(11,10))
	check(not enemy.alive and enemy.hp==48 and enemy.morale==0,"morale kill evaluated after both throw channels")
	check(hero.gained_xp==gained_before+expected_xp,"throw kill gives half XP")
	check(b.stats.kills_by_gun==1,"throw kill ordinary result channel")
	# Asymmetric fixture verifies all four 427A71 rotations and percentage retention.
	var mat:Array=[]
	for row in range(7): mat.append([0,0,0,0,0,0,0])
	mat[2][3]=70;b.data.apply_ranges["999"]=mat
	var offsets:=[Vector2i(0,-1),Vector2i(0,1),Vector2i(-1,0),Vector2i(1,0)]
	for direction in range(4):
		var area:Array=b._apply_tiles(Vector2i(10,10),999,direction)
		check(area.size()==1 and area[0].tile==Vector2i(10,10)+offsets[direction] and area[0].pct==70,"rotation %d"%direction)
	check(b._facing(Vector2i(10,10),Vector2i(11,11))==1 and b._facing(Vector2i(10,10),Vector2i(10,10))==-1,"facing vertical tie/self")
	b.queue_free();await process_frame
	print("ORIGINAL_ITEMS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
