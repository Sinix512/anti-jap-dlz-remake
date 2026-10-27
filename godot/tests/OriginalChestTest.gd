extends SceneTree
const Codec=preload("res://scripts/battle/StateCodec.gd")
const AI=preload("res://scripts/battle/OriginalAI.gd")
class ObservedBattle extends "res://scripts/Battle.gd":
	var sound_events:Array=[]
	func _play_sfx(index:int,volume:float=-6.0) -> void:
		sound_events.append(index)
		super._play_sfx(index,volume)

# The mechanics fixtures deliberately isolate the source contract. They are
# not campaign wins, and never alter original generated level data.
class ObservedScenario extends "res://scripts/m4/Scenario.gd":
	var events:Array=[]
	var defer_move:=false
	var watched=null
	func ai_prepare(_u) -> bool:return false
	func check_end() -> bool:return false
	func on_unit_died(u) -> void:events.append(["death",u.slot])
	func on_unit_moved(u) -> void:
		events.append(["moved",u.slot])
		if defer_move:await battle.get_tree().process_frame
		events.append(["moved_done",u.slot])
	func on_tick() -> void:events.append(["tick",0 if watched==null else watched.hp])
	func on_chest(u,chest:Dictionary) -> void:
		events.append(["chest",u.slot,int(chest.wupin),0 if watched==null else watched.hp])
		super.on_chest(u,chest)

var checks:=0
var failures:=0
var m2:Dictionary
var m4:Dictionary
var b
var spy
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("CHEST_FAIL "+label)
func fixture() -> void:
	if b!=null:b.free()
	b=ObservedBattle.new();root.add_child(b)
	b.setup(m4.duplicate(true),m4.levels[0].duplicate(true),load("res://assets/font/hzk16.fnt"),{})
	b.set_process(false);b.fast_sim=true;b.animations_enabled=false;b.sfx_enabled=false;b.phase="qa"
	for u in b.units:u.free()
	b.units.clear();b.player_units.clear();b.enemy_units.clear();b.chests.clear();b.mines.clear()
	b.terrain.fill(0);b.level.index=2;b.level.difficulty_setting=1
	b.finished_flag=false;b.busy=false;b.stats={"chests":0,"loot_count":0}
	spy=ObservedScenario.new();spy.battle=b;spy.level=b.level;b.scenario=spy
	b.sound_events.clear()
func unit(slot:int,side:int,tile:Vector2i,hp:=1000):
	var d:Dictionary=m4.levels[0].units[0].duplicate(true)
	d.merge({"slot":slot,"pid":slot,"name":"fixture%d"%slot,"side":"player" if side==0 else "enemy","faction":side,"x":tile.x,"y":tile.y,"hp":hp,"max_hp":hp,"morale":100,"level":1,"xp":0,"item_slots":[0,0,0,0,0,0,0,0],"mine_slots":[0,0,0,0,0,0,0,0],"control":side==0,"bingzhong":1,"select":1,"move":8,"zhili":100,"wuli":100,"behavior":13},true)
	var u=b._spawn_unit(d);u.skill_counts={};return u
func chest(tile:Vector2i,iid:=81) -> Dictionary:
	var c:Dictionary={"x":tile.x,"y":tile.y,"wupin":iid,"opened":false,"appearance":0,"item_name":"fixture"}
	b.chests.append(c);return c
func count_event(kind:String) -> int:return spy.events.filter(func(e):return e[0]==kind).size()
func moving_actor(hp:=1000):
	var u=unit(40,1,Vector2i(5,4),hp)
	u.behavior=8;u.target_x=5;u.target_y=3;u.move=8
	return u
func run() -> void:
	m2=Codec.integers(JSON.parse_string(FileAccess.get_file_as_string("res://data/m2.json")))
	m4=Codec.integers(JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json")))
	for side in [0,1,2]:
		fixture();var u=unit(40+side,side,Vector2i(5,5));u.control=false;u.auto=true
		b.battle_context={"items":{"81":4},"temporary_loot":{"81":9}}
		var c=chest(Vector2i(5,5));var before:bool=u.acted
		await b._after_unit_step(u)
		check(u.item_slots[0]==82 and c.opened and c.wupin==-1,"same-tile pickup without side/control gate side%d"%side)
		check(b.battle_context.items["81"]==4 and b.battle_context.temporary_loot["81"]==9,"carrier pickup never also credits player warehouse or temp side%d"%side)
		var receipt:Dictionary=b.pending_story.filter(func(e):return e.kind=="chest")[0].data
		check(receipt.actor_slot==u.slot and receipt.actor_faction==side and receipt.item_id==81 and receipt.destination=="carrier" and receipt.recipient_slot==u.slot,"receipt identifies actual carrier, not implied player side%d"%side)
		check(u.acted==before and b.stats.chests==1 and spy.chests_opened==1,"pickup itself never spends action side%d"%side)
		await b._after_unit_step(u)
		check(u.item_slots.count(82)==1 and b.stats.chests==1 and spy.chests_opened==1,"opened native field cannot grant twice side%d"%side)
	fixture();var h=unit(0,0,Vector2i(5,5));h.item_slots=[2,0,7,0,2,0,0,0]
	chest(Vector2i(5,5),6);await b._after_unit_step(h)
	check(h.item_slots==[2,7,7,2,0,0,0,0],"first hole inserted before stable compaction; duplicates retained")
	fixture();h=unit(0,0,Vector2i(5,5));var c=chest(Vector2i(5,5),-1)
	b._open_chest(h,0);await b._after_unit_step(h)
	check(b._chest_at(Vector2i(5,5))==-1 and count_event("chest")==0 and not c.opened and int(b.stats.get("chests",0))==0,"negative native field neither awards nor counts even without UI flag")
	check(b.sound_events.is_empty(),"empty native box does not play a reward sound")
	chest(Vector2i(5,5),6);await b._after_unit_step(h)
	check(not b.chests[1].opened and h.item_slots.count(7)==0,"first empty overlapping box blocks later one")
	fixture();h=unit(0,0,Vector2i(5,5));c=chest(Vector2i(5,5));h.alive=false
	b._open_chest(h,0);await b._after_unit_step(h)
	check(not c.opened and count_event("chest")==0,"stage0 cannot pick even via direct helper")
	fixture();h=unit(0,0,Vector2i(5,5));c=chest(Vector2i(6,5));await b._after_unit_step(h)
	check(not c.opened and count_event("chest")==0,"adjacent chest is not reachable by pickup")
	fixture();var e=unit(40,1,Vector2i(5,5));e.item_slots.fill(2);c=chest(Vector2i(5,5),6)
	b.battle_context={"items":{"6":65535},"temporary_loot":{"6":9}}
	var campaign=load("res://scripts/m4/Campaign.gd").new();root.add_child(campaign)
	campaign.state=load("res://scripts/m2/GameState.gd").new();campaign.state.new_game(m2);campaign.state.setup_m4(m4);campaign.state.items={"6":65535}
	b.looted.connect(campaign._on_loot)
	await b._after_unit_step(e)
	check(e.item_slots==[2,2,2,2,2,2,2,2] and b.battle_context.items["6"]==0 and campaign.state.item_count(6)==0,"full enemy bag uses permanent u16 warehouse, overflow mirrored to campaign")
	check(b.battle_context.temporary_loot["6"]==9 and c.wupin==-1 and b.stats.loot_count==1,"full-bag reward is not temporary loot and consumes source once")
	var receipt:Dictionary=b.pending_story.filter(func(event):return event.kind=="chest")[0].data
	check(receipt.actor_slot==40 and receipt.actor_faction==1 and receipt.item_id==6 and receipt.destination=="warehouse" and receipt.recipient_slot==-1,"full enemy-bag receipt explicitly identifies permanent warehouse")
	campaign.free()
	# The player can still undo pre-movement: no box or position/T510 hook yet.
	fixture();h=unit(0,0,Vector2i(5,6));c=chest(Vector2i(5,5));b.phase="player"
	b._select_unit(h);await b._player_move(Vector2i(5,5))
	check(Vector2i(h.x,h.y)==Vector2i(5,5) and not c.opened and not h.acted and spy.events.is_empty(),"reversible player move defers pickup and position/T510")
	b._cancel_action_menu()
	check(Vector2i(h.x,h.y)==Vector2i(5,6) and not c.opened and h.item_slots[0]==0 and spy.events.is_empty(),"menu cancel restores location with no pickup or trigger side effect")
	b._select_unit(h);await b._player_move(Vector2i(5,5));await b._on_wait()
	check(c.opened and h.item_slots[0]==82 and h.acted and count_event("tick")==1,"explicit player wait commits pickup and one T510")
	# Await a suspended position hook before T510 (no fire-and-forget tail).
	fixture();h=unit(0,0,Vector2i(5,5));chest(Vector2i(5,5));spy.defer_move=true
	b._after_completed_action(h)
	check(count_event("chest")==1 and count_event("moved")==1 and count_event("tick")==0,"completion waits for pending position hook")
	await process_frame;await process_frame
	check(spy.events.map(func(a):return a[0])==["chest","moved","moved_done","tick"],"pickup -> completed position hook -> one T510")
	# AI ordinary attacks must use PRE-chest equipment and finish before pickup.
	for moving in [false,true]:
		fixture();h=unit(0,0,Vector2i(5,5));e=unit(40,1,Vector2i(5,7) if moving else Vector2i(5,6))
		e.behavior=7;e.move=8 if moving else 0
		var plan:Dictionary=AI.plan(b,e);var destination:Vector2i=plan.station
		e.behavior=7;c=chest(destination,91);spy.watched=h
		check(plan.kind=="attack" and (destination!=Vector2i(e.x,e.y))==moving,"fixture actual AI chooses attack with expected displacement")
		var expected:int=b.compute_damage(e,h);var hp:int=h.hp
		b.phase="enemy";await b._ai_act(e,"player")
		var pickup:Array=spy.events.filter(func(a):return a[0]=="chest")
		check(h.hp==hp-expected and pickup.size()==1 and pickup[0][3]==h.hp,"AI damage is committed before equipment pickup moving%d"%int(moving))
		check(e.item_slots.has(92) and c.wupin==-1 and count_event("tick")==1 and spy.events[-1][0]=="tick","AI attack runs pickup/position/T510 exactly once moving%d"%int(moving))
	fixture();e=moving_actor();c=chest(Vector2i(5,3));b.phase="enemy";await b._ai_act(e,"player")
	check(Vector2i(e.x,e.y)==Vector2i(5,3) and c.opened and e.acted and count_event("tick")==1,"AI pure real move picks at action tail with one T510")
	fixture();e=unit(40,1,Vector2i(5,5));e.behavior=13;c=chest(Vector2i(5,5));b.phase="enemy";await b._ai_act(e,"player")
	check(e.acted and not c.opened and spy.events.is_empty(),"AI pure wait skips pickup and T510 entirely")
	fixture();e=moving_actor();e.target_x=e.x;e.target_y=e.y;c=chest(Vector2i(e.x,e.y));b.phase="enemy";await b._ai_act(e,"player")
	check(e.acted and not c.opened and spy.events.is_empty(),"AI non-improving move plan also skips action tail")
	for survives in [true,false]:
		fixture();e=moving_actor(1000 if survives else 1);unit(0,0,Vector2i(1,1));c=chest(Vector2i(5,3))
		b.mines=[{"tile":Vector2i(5,3),"mine":b.data.mines[0],"mine_id":0,"code":0,"low":1}]
		b.phase="enemy";await b._ai_act(e,"player")
		check(e.alive==survives and b.mines.is_empty() and e.acted and count_event("tick")==1,"AI mine interruption still executes one T510 survives%d"%int(survives))
		check(c.opened==survives and count_event("chest")==int(survives),"AI mine survivor picks, dead stage refuses survives%d"%int(survives))
		if survives:check(e.hp<e.max_hp and spy.events[0][0]=="chest","mine damage precedes surviving pickup")
	# Headless movement facade must have the same deferred pickup as the UI.
	fixture();h=unit(0,0,Vector2i(5,6));c=chest(Vector2i(5,5));b.phase="player"
	await b._bot_move_to(h,Vector2i(5,5))
	check(not c.opened and spy.events.is_empty(),"bot movement cannot acquire a box before actual wait/action")
	b.selected=h;await b._on_wait()
	check(c.opened and h.acted and count_event("tick")==1,"bot uses real explicit wait to finalize movement")
	fixture();h=unit(0,0,Vector2i(5,6));c=chest(Vector2i(5,5));b.phase="player"
	await b._bot_move_to(h,Vector2i(5,4));b.selected=h;await b._on_wait()
	check(Vector2i(h.x,h.y)==Vector2i(5,4) and not c.opened and count_event("chest")==0,"passing through a box never picks it at an intermediate path cell")
	for survives in [true,false]:
		fixture();h=unit(0,0,Vector2i(5,6),1000 if survives else 1);c=chest(Vector2i(5,5));b.phase="player"
		b.mines=[{"tile":Vector2i(5,5),"mine":b.data.mines[0],"mine_id":0,"code":0,"low":1}]
		b._select_unit(h);await b._player_move(Vector2i(5,5))
		check(h.alive==survives and h.acted and c.opened==survives and count_event("tick")==1,"player mine interruption commits tail, unlike reversible movement survives%d"%int(survives))
	# Real asynchronous pickup must block T510 and box-emptying until key-UP.
	fixture();h=unit(0,0,Vector2i(5,5));c=chest(Vector2i(5,5),7);b.fast_sim=false
	b._after_completed_action(h);await process_frame
	check(h.item_slots[0]==8 and c.wupin==7 and not c.opened and b.busy and b.action_resolution_depth==1 and count_event("tick")==0,"modal reward is committed before box-emptying and T510")
	check(b.sound_events==[524] and b.action_panel.get_child(1).text=="       得到  "+str(b.data.items["7"].name)+"  ！","reward uses item audio_get and exact original GBK-spaced text")
	b._open_chest(h,0)
	check(h.item_slots.count(8)==1 and count_event("chest")==1 and b.sound_events.size()==1,"blocking notice prevents pickup reentry without prematurely changing native ID")
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=false;root.push_input(click,true);await process_frame
	check(b.action_panel!=null and not b.action_panel.skip_left and c.wupin==7 and count_event("tick")==0,"first left-UP is ignored by chest's original notice flag")
	var key:=InputEventKey.new();key.keycode=KEY_SPACE;key.pressed=false;root.push_input(key,true);await process_frame
	check(b.action_panel==null and c.wupin==-1 and c.opened and not b.busy and b.action_resolution_depth==0 and count_event("tick")==1,"any key-UP acknowledges before emptying box and resuming exactly one T510")
	fixture();e=unit(40,1,Vector2i(5,5));e.item_slots.fill(2);c=chest(Vector2i(5,5),0);b.fast_sim=false
	b._open_chest(e,0);await process_frame
	check(b.action_panel!=null and b.sound_events==[513] and b.battle_context.items["0"]==1 and c.wupin==0,"enemy full-bag warehouse branch gets the same blocking item feedback")
	click=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_RIGHT;click.pressed=false;root.push_input(click,true);await process_frame
	b.queue_free();await process_frame;await create_timer(0.5).timeout
	root.get_node("Music").release_playback()
	print("ORIGINAL_CHEST checks=",checks," failures=",failures)
	quit(1 if failures else 0)
