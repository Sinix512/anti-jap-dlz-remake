extends SceneTree
class Observer extends RefCounted:
	var status_text:=""
	func on_tick() -> void:pass
	func on_unit_moved(_u) -> void:pass
	func on_unit_died(_u) -> void:pass
	func check_end() -> bool:return false
var checks:=0
var failures:=0
var m4:Dictionary
var b
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("MINE_FAIL "+label)
func fixture() -> void:
	if b!=null:b.free()
	b=load("res://scripts/Battle.gd").new();root.add_child(b)
	b.setup(m4.duplicate(true),m4.levels[0].duplicate(true),load("res://assets/font/hzk16.fnt"),{})
	b.fast_sim=true;b.animations_enabled=false;b.sfx_enabled=false;b.set_process(false);b.scenario=Observer.new()
	for u in b.units:u.free()
	b.units.clear();b.player_units.clear();b.enemy_units.clear();b.mines.clear()
	b.level.index=2
	for row in b.data.terrain_modifiers:row[3]=0;row[4]=0
func unit(slot:int,side:int,tile:Vector2i,hp:=500,morale:=100,level:=1):
	var d:Dictionary=m4.levels[0].units[0].duplicate(true)
	d.merge({"slot":slot,"pid":slot,"name":"fixture%d"%slot,"side":"player" if side==0 else "enemy","faction":side,"x":tile.x,"y":tile.y,"hp":hp,"max_hp":hp,"morale":morale,"level":level,"xp":0,"item_slots":[0,0,0,0,0,0,0,0],"mine_slots":[0,0,0,0,0,0,0,0],"control":true,"bingzhong":1},true)
	return b._spawn_unit(d)
func mine(code:int,tile:Vector2i,low:=1) -> void:
	b.mines.append({"tile":tile,"mine":b.data.mines[code%10],"mine_id":code%10,"code":code,"low":low,"owner_side":"enemy"})
func run() -> void:
	m4=JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json"))
	for code in [0,10,20,30]:
		fixture();var u=unit(0,0,Vector2i(5,5));mine(code,Vector2i(5,5),3 if code==20 else 1)
		var stop:bool=b._trigger_mine(Vector2i(5,5),u)
		check(stop==(code==0) and u.hp==(380 if code==0 else 500) and u.morale==100 and b.mines.size()==(0 if code==0 else 1),"fuse %d stepping"%code)
		fixture();u=unit(0,0,Vector2i(5,5));u.bingzhong=46;mine(code,Vector2i(5,5),3 if code==20 else 1)
		check(not b._trigger_mine(Vector2i(5,5),u) and u.hp==500 and u.morale==100 and b.mines.is_empty(),"tank clears fuse %d"%code)
	fixture();var u=unit(0,0,Vector2i(5,5));var v=unit(1,0,Vector2i(8,7))
	mine(30,Vector2i(8,7));b.selected=u;b._mine_command("remote")
	check(b.attack_tiles.has(Vector2i(8,7)),"remote Manhattan5 no owner filter")
	b._mine_click(Vector2i(8,7))
	check(v.hp==380 and v.morale==100 and b.mines.is_empty() and u.acted,"remote damages friendly and costs action")
	fixture();u=unit(0,0,Vector2i(5,5));mine(30,Vector2i(8,8));mine(30,Vector2i(5,5));mine(20,Vector2i(6,5),2)
	b.selected=u;b._mine_command("remote")
	check(b.attack_tiles.is_empty() and not u.acted,"remote rejects distance6/self/nonremote")
	fixture();u=unit(0,0,Vector2i(5,5));mine(20,Vector2i(5,5),3)
	b._round_maintenance();check(b.mines.size()==1 and b.mines[0].low==2 and u.hp==500,"timer2 first boundary decrements")
	b._round_maintenance();check(b.mines.is_empty() and u.hp==380 and u.morale==100,"timer2 second boundary detonates")
	fixture();u=unit(0,0,Vector2i(4,5));mine(20,Vector2i(5,5),3);b.selected=u
	b._mine_command("timer");check(b.attack_tiles.has(Vector2i(5,5)),"timer editable low3")
	b._set_mine_timer(Vector2i(5,5),10,false)
	check(b.mines[0].low==11 and b.mines[0].code==20 and u.acted,"retimer n+1 preserves code")
	fixture();var victims:Array=[]
	for i in range(4):victims.append(unit(i,i%2,Vector2i(5+i,4),1000))
	u=unit(10,0,Vector2i(5,5),1000)
	for i in range(4):mine([31,11,21,1][i],Vector2i(5+i,5),11 if i==2 else 1)
	b._detonate_mines(Vector2i(5,5))
	check(b.mines.is_empty() and u.hp==568 and u.morale==100,"mixed-fuse FIFO chain and center overlap")
	for i in range(4):check(victims[i].hp==808 and victims[i].morale==100,"chain victim %d exact192"%i)
	fixture();u=unit(60,1,Vector2i(6,5),100,30);mine(23,Vector2i(7,5),2);mine(21,Vector2i(5,5),2)
	b._round_maintenance()
	check(not u.alive and u.hp==0 and u.morale==30 and b.mines.is_empty() and b.stats.kills_by_mine==1,"due mines map order not insertion order")
	fixture();u=unit(60,1,Vector2i(5,5),100,100,3);var a=unit(41,0,Vector2i(1,1));var c=unit(59,0,Vector2i(1,2));mine(0,Vector2i(5,5))
	b._detonate_mines(Vector2i(5,5));check(a.gained_xp==0 and c.gained_xp==0,"zero slot0..39 denominator awards no XP")
	fixture();u=unit(60,1,Vector2i(5,5),100,100,3);a=unit(39,0,Vector2i(1,1));c=unit(41,0,Vector2i(1,2));var d=unit(59,0,Vector2i(1,3));var e=unit(61,0,Vector2i(1,4));mine(0,Vector2i(5,5))
	b._detonate_mines(Vector2i(5,5));check(a.gained_xp==12 and c.gained_xp==12 and d.gained_xp==12 and e.gained_xp==0,"mine XP denominator40 recipient60 boundary")
	fixture();u=unit(0,0,Vector2i(4,5));b.selected=u;u.mine_slots=[1,11,21,31,0,0,0,0]
	b._consume_inventory("mines",10);check(u.mine_slots==[1,21,31,0,0,0,0,0],"remove stably compacts mine bag")
	u.mine_slots=[1,0,21,0,31,0,0,0];mine(10,Vector2i(5,5));b._mine_command("recover");b._mine_click(Vector2i(5,5))
	check(u.mine_slots==[1,11,21,31,0,0,0,0] and b.mines.is_empty() and u.acted,"recover inserts first hole then compacts")
	u.acted=false;u.mine_slots=[1,1,1,1,1,1,1,1];b.selected=u;mine(30,Vector2i(5,5));b._mine_command("recover");b._mine_click(Vector2i(5,5))
	check(u.mine_slots==[1,1,1,1,1,1,1,1] and b.mines.is_empty() and u.acted,"original full-bag recovery loses mine and action")
	fixture();u=unit(0,0,Vector2i(4,5));v=unit(40,1,Vector2i(5,5));u.mine_slots=[31,1,1,1,1,1,1,1];v.mine_slots=[1,1,1,1,1,1,1,1];b.selected=u;b._choose_mine_transfer(30)
	check(b.attack_tiles.has(Vector2i(5,5)),"give may target full hostile bag")
	b._mine_click(Vector2i(5,5));check(u.mine_slots==[1,1,1,1,1,1,1,0] and v.mine_slots==[1,1,1,1,1,1,1,1] and u.acted,"original full-bag give loses mine and action")
	for enemy_first in [false,true]:
		fixture();a=unit(0,0,Vector2i(1,1));c=unit(2,0,Vector2i(1,2));u=unit(1,0,Vector2i(5,5) if enemy_first else Vector2i(5,4),200 if enemy_first else 100)
		v=unit(40,1,Vector2i(5,4) if enemy_first else Vector2i(5,5),100 if enemy_first else 200)
		mine(1,Vector2i(5,5));b._detonate_mines(Vector2i(5,5))
		check(a.gained_xp==(9 if enemy_first else 10) and c.gained_xp==a.gained_xp and u.gained_xp==(9 if enemy_first else 0),"map death order affects stage-based XP %s"%enemy_first)
	b.queue_free();await process_frame
	print("ORIGINAL_MINES checks=",checks," failures=",failures)
	quit(1 if failures else 0)
