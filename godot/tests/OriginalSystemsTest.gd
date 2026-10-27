extends SceneTree
const State=preload("res://scripts/m2/GameState.gd")
const Save=preload("res://scripts/m2/OriginalSave.gd")
const Builder=preload("res://scripts/m4/LevelBuilder.gd")
const Rules=preload("res://scripts/battle/CombatRules.gd")
const GBK=preload("res://scripts/m2/GBK.gd")
var failures:=0
var checks:=0
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error("SYSTEM_FAIL "+label)
func json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var m2:=json("res://data/m2.json")
	var m4:=json("res://data/m4.json")
	var state=State.new()
	state.new_game(m2);state.setup_m4(m4)
	state.player_name="张三李勇"
	state.protagonist_member()
	state.battle_turn=63
	state.play_seconds=7321
	state.town_bgm_scene=51
	state.money=18765
	state.main_score_snapshot=3012
	for i in range(40): state.mines[str(i)]=i+1
	for i in range(10): state.materials[str(i)]=100+i
	for i in range(14): state.script_globals["0x%x"%(0x95eaf8+i*4)]=i%2
	for i in range(95): state.script_globals["0x%x"%(0x7d06c8+i*4)]=i+20
	state.script_globals["0x7d0830"]=3012
	state.person(31).level=77
	state.person(31).xp=94
	state.set_person_side(31,0)
	state.person(31).mine_slots=[1,11,21,31,10,20,30,40]
	var unknown:=PackedByteArray();unknown.resize(32768)
	for i in range(unknown.size()):unknown[i]=(i*37+17)%256
	state.original_blocks.block22=unknown
	var raw:=Save.encode(state,state.m4_level(0))
	check(raw.size()==85072,"save fixed length")
	var decoded:=Save.decode(raw)
	check(decoded.game_state==57 and decoded.battle_turn==63,"strategic mode / actual turn")
	check(decoded.people[0].name=="张三李勇","GBK protagonist")
	check(decoded.people[31].level==77 and decoded.people[31].xp==94,"persistent growth")
	check(decoded.people[31].mines==[1,11,21,31,10,20,30,40],"all four fuse bytes")
	check(decoded.mines.size()==40 and int(decoded.mines["39"])==40,"40 warehouse mine codes")
	check(decoded.materials.size()==10 and int(decoded.materials["9"])==109,"materials are u32")
	check(decoded.main_score_snapshot==3012,"frozen main score")
	check(decoded.town_bgm_scene==51 and decoded.play_seconds==7321,"music / clock blocks")
	check(decoded._raw.block22==unknown,"unknown raw bytes")
	var loaded=State.new();loaded.new_game(m2);loaded.setup_m4(m4)
	loaded.money=99999;loaded.set_person_side(3,0)
	var battle_save:Dictionary=decoded.duplicate(true);battle_save.game_state=150
	var preserved_money:int=loaded.money
	check(not Save.apply(loaded,battle_save,"test-only") and loaded.money==preserved_money,"unsupported native battle rejected transactionally")
	check(Save.apply(loaded,decoded,"test-only"),"apply valid save")
	check(loaded.money==18765 and loaded.player_name=="张三李勇","replace previous state")
	check(loaded.has_member(31) and not loaded.has_member(3),"membership from side not private tags")
	var json_state: Dictionary=JSON.parse_string(JSON.stringify(loaded.to_dict()))
	var reloaded=State.new();reloaded.new_game(m2);reloaded.setup_m4(m4);reloaded.from_dict(json_state)
	check(reloaded.original_blocks.block22==unknown,"unknown bytes survive JSON")
	check(Save.decode(Save.encode(reloaded,reloaded.m4_level(0))).people[31].mines==decoded.people[31].mines,"save matrix reexport")
	check(Save.decode(raw.slice(0,85071)).is_empty(),"reject short file")
	check(GBK.decode(GBK.encode("抗日地雷战",16))=="抗日地雷战","GBK codec")
	for diff in range(3):
		state.new_game(m2);state.setup_m4(m4);state.difficulty=diff
		state.protagonist.skills.buji=1
		state.save_checkpoint(false)
		state.protagonist.level=3;state.protagonist.xp=66;state.protagonist.attack_count=47
		state.protagonist.skills.buji=12;state.protagonist.skills.kongxi=33
		state.load_checkpoint()
		check(int(state.protagonist.level)==(3 if diff==0 else 1),"retry difficulty level %d"%diff)
		check(int(state.protagonist.skills.buji)==(1 if diff==2 else 12),"retry skill practice %d"%diff)
		check(int(state.protagonist.skills.kongxi)==0,"no new skill from failed battle %d"%diff)
	state.new_game(m2);state.setup_m4(m4)
	state.campaign_index=40;state.main_score_snapshot=3600;state.hidden_unlocked=true
	state.complete_level(40,50,true)
	check(state.campaign_index==41 and not state.campaign_level().is_empty(),"fiction town continuation L41")
	# L01's captive is already faction0 by L00's real victory phase, not by
	# being in a named slot. Use that fixture state, not a fresh faction1 template.
	state.new_game(m2);state.setup_m4(m4)
	state.apply_phase_state(m4.levels[0].victory_phase)
	var people:Array=[]
	for i in range(40):people.append(state.person(i))
	var lv:=Builder.build(m4,m2,1,people)
	for rec in lv.units:
		if int(rec.slot)==1:check(not rec.control and rec.auto,"captive cannot be controlled")
	var b=load("res://scripts/Battle.gd").new();root.add_child(b)
	state.new_game(m2);state.setup_m4(m4)
	b.setup(m4,Builder.build(m4,m2,0,[state.protagonist_member()]),load("res://assets/font/hzk16.fnt"),state.battle_context())
	b.fast_sim=true;b.scenario=null
	var hero=b.unit_by_slot(0)
	var enemy=b.unit_by_slot(40)
	hero.set_tile(4,4);enemy.set_tile(5,4)
	b.camera.position=b._focus_position(Vector2(4*48+24,4*48+24));b._clamp_camera()
	check(b.screen_to_tile(Vector2(14,32))==Vector2i(0,0),"map top-left exact")
	check(b.screen_to_tile(Vector2(445,463))==Vector2i(8,8),"map last pixel exact")
	for p in [Vector2(13,32),Vector2(446,463),Vector2(445,464)]:check(b.screen_to_tile(p)==Vector2i(-1,-1),"map rejects border %s"%p)
	hero.select=0
	check(b.attack_targets(hero).is_empty(),"zero select template has no attack")
	hero.select=4
	var before_hp:int=hero.hp
	var expected:int=b.compute_damage(hero,enemy)
	var enemy_hp:int=enemy.hp
	await b._perform_attack(hero,enemy)
	check(hero.hp==before_hp,"no automatic counterattack")
	check(enemy.hp==enemy_hp-expected,"exact normal attack damage")
	check(int(hero.data.xp)>0,"immediate attack XP")
	enemy.hp=1;enemy.last_damage_kind="skill";b._on_unit_died(enemy)
	check(int(b.stats.kills_by_gun)==1,"skill kills share ordinary channel")
	b.queue_free();await process_frame
	print("ORIGINAL_SYSTEMS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
