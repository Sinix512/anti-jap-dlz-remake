extends SceneTree
const State=preload("res://scripts/m2/GameState.gd")
const Builder=preload("res://scripts/m4/LevelBuilder.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("PRESENTATION_FAIL "+label)
func run() -> void:
	var m2:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/m2.json"))
	var m4:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json"))
	var gs=State.new();gs.new_game(m2);gs.setup_m4(m4)
	var camp=load("res://scripts/m4/Campaign.gd").new();root.add_child(camp)
	camp.setup(load("res://assets/font/hzk16.fnt"));camp.qa_mode=false
	var b=load("res://scripts/Battle.gd").new();camp.add_child(b)
	b.setup(m4,Builder.build(m4,m2,0,[gs.protagonist_member()]),load("res://assets/font/hzk16.fnt"),gs.battle_context())
	b.set_process(false);b.sfx_enabled=false;b.animation_speed=1
	check(is_equal_approx(b._play_flm(0,Vector2.ZERO),0.32),"area FLM retains 20ms x16")
	var area=b.fx_root.get_child(b.fx_root.get_child_count()-1)
	check(is_equal_approx(area.sprite_frames.get_animation_speed("default"),50.0),"area rate50fps")
	check(is_equal_approx(b._play_single_cell_flm(0,Vector2.ZERO),0.64),"single cell FLM40ms x16")
	var cell=b.fx_root.get_child(b.fx_root.get_child_count()-1)
	check(is_equal_approx(cell.sprite_frames.get_animation_speed("default"),25.0),"single cell rate25fps")
	b.animation_speed=0
	var before:int=b.fx_root.get_child_count()
	check(b._play_single_cell_flm(0,Vector2.ZERO)==0.0 and b.fx_root.get_child_count()==before,"fastest FLM is immediate, no synthetic1ms")
	var hero=b.unit_by_slot(0);hero.data.level=1;hero.data.xp=99
	var started:=Time.get_ticks_msec()
	b._gain_xp(hero,1)
	check(hero.data.level==1 and hero.data.xp==100 and b.progress_fx_active,"level-up retains old level/full XP during fixed100ms even at speed0")
	await b._wait_for_progress_fx()
	check(Time.get_ticks_msec()-started>=95,"level-up postwait does not end early")
	check(not b.progress_fx_active and hero.data.level==2 and hero.data.xp==0,"level-up commits only after postwait completes")
	var actions:Array=m4.levels[25].start_actions
	var explosions:Array=actions.filter(func(a):return a.has("phase_flm"))
	check(explosions.size()==3 and explosions.map(func(a):return a.phase_flm.tile)==[[10,9],[12,9],[24,10]],"L25 exact three ordered explosion tiles")
	var first:int=actions.find(explosions[0])
	check(actions[first-1].get("message_record",-1)==187 and actions[first+3].get("message_record",-1)==188,"L25 explosion dialogue ordering")
	check(explosions.map(func(a):return a.phase_flm.camera)==[true,false,true] and explosions.all(func(a):return a.phase_flm.wait_ms==1000),"L25 source camera pans and fixed waits")
	var turn11:Dictionary={}
	for rule in m4.levels[12].triggers.rules:
		if rule.id=="t750_turn11":turn11=rule
	check(not turn11.is_empty() and turn11.then[0].presentation_sequence[0].phase_flm.tile==[9,5],"L12 T11 explosion precedes dialogue")
	# Numeric state remains synchronous before the round maintenance, even when
	# Campaign owns the deferred visual presentation.
	b.battle_context.campaign_story=true
	var target=b.unit_by_slot(40);target.morale=51
	b.scenario._apply(turn11.then)
	check(target.morale==25,"L12 morale halving not deferred past maintenance")
	camp.battle=b;camp.current_battle_index=0;camp.current_battle_standalone=false
	b.story_event.connect(camp._on_battle_story_event)
	b.animations_enabled=false
	# Let expensive setup/render frames settle before sampling a mid-wait frame.
	for i in range(5):await process_frame
	b.emit_story_event("visual_steps",{"steps":[{"phase_flm":{"index":0,"tile":[9,5],"camera":true,"wait_ms":100}},{"flag_set":{"addr":"0x583f48","value":73}}]})
	await create_timer(0.04).timeout
	check(camp.battle_visual_active and b.busy and b.scenario._global_value("0x583f48")!=73,"visual wait blocks process reentry and state-step consumption")
	await create_timer(0.13).timeout
	check(not camp.battle_visual_active and camp.battle_visual_sequences==0 and not b.busy and b.scenario._global_value("0x583f48")==73,"visual queue resumes once without start-phase replay")
	b.fast_sim=true
	check(b._play_single_cell_flm(0,Vector2.ZERO)==0.0,"fast simulation skips visual waits only")
	await create_timer(0.5).timeout
	camp.queue_free();await process_frame;await create_timer(0.2).timeout
	print("ORIGINAL_PRESENTATION checks=",checks," failures=",failures)
	quit(1 if failures else 0)
