extends SceneTree
const Codec=preload("res://scripts/battle/StateCodec.gd")
const Builder=preload("res://scripts/m4/LevelBuilder.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("MEDIA_FAIL "+label)
func run() -> void:
	var m5:Dictionary=Codec.integers(JSON.parse_string(FileAccess.get_file_as_string("res://data/m5.json")))
	var evidence:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../extract/research_visual_remaining_20261025.checks.json"))
	var hs=load("res://scripts/m5/HistorySlideshow.gd").new();root.add_child(hs)
	hs.setup(load("res://assets/font/hzk16.fnt"),m5.history)
	check(hs._timer.time_left>15.0 and hs._timer.time_left<=15.125,"history keeps original275 x55ms first hold")
	for entry in m5.history:
		hs._show(int(entry.index))
		var stem:String=str(entry.path).get_file().get_basename()
		var fact:Dictionary=evidence.history_photos.filter(func(f):return f.id==stem)[0]
		check(hs._tex.size==Vector2(fact.size[0],fact.size[1]),"unscaled original history size "+stem)
		check(hs._tex.position==Vector2(fact.original_position[0],fact.original_position[1]),"integer original history center "+stem)
		check(hs._background.color==Color8(int(fact.fill_RGB[0]),int(fact.fill_RGB[1]),int(fact.fill_RGB[2])) and int(entry.background_index)==int(fact.nearest_black_index),"original palette fill "+stem)
	check(hs._timer.is_stopped(),"final history image waits for user")
	hs._close();await process_frame
	var camp=load("res://scripts/m4/Campaign.gd").new();root.add_child(camp);camp.setup(load("res://assets/font/hzk16.fnt"))
	var music=root.get_node("Music")
	var enabled_before:bool=music.enabled
	var ended:=[false]
	camp.state.story_variant=true
	camp._play_media(0,func():ended[0]=true)
	check(music.playback_suspended() and not music.playing and is_instance_valid(camp.story_player),"entry TXT suspends old track")
	music._try_loop()
	check(not music.playing and music.enabled==enabled_before,"focus loop cannot restart or unmute suspended entry")
	camp.story_player._finish();await process_frame
	check(ended[0] and not music.playback_suspended(),"skip releases entry music gate exactly once")
	camp._play_media(0,func():pass)
	camp.queue_free();await process_frame
	check(not music.playback_suspended(),"leaving campaign releases outstanding entry gate")
	# Entry MPEG nests the outer entry gate and the inner MPEG/CD-close gate.
	# A method.bind(token) signal connection aliases these two cleanup handlers.
	camp=load("res://scripts/m4/Campaign.gd").new();root.add_child(camp);camp.setup(load("res://assets/font/hzk16.fnt"));camp.state.story_variant=false
	ended[0]=false
	camp._play_media(0,func():ended[0]=true)
	check(is_instance_valid(camp.cutscene) and music._suspensions.size()==2,"MPEG entry acquires two independently releasable gates")
	music._try_loop()
	check(not music.playing,"focus cannot restart BGM during nested MPEG entry")
	camp.cutscene._finish();await process_frame
	check(ended[0] and not music.playback_suspended(),"MPEG skip releases both nested gates")
	camp._play_media(0,func():pass)
	check(music._suspensions.size()==2,"second MPEG entry acquires fresh nested gates")
	camp.queue_free();await process_frame
	check(not music.playback_suspended(),"leaving MPEG entry releases every nested gate")
	# L32/L33 victory TXT is the explicit no-stop exception, unlike MPEG.
	camp=load("res://scripts/m4/Campaign.gd").new();root.add_child(camp);camp.setup(load("res://assets/font/hzk16.fnt"));camp.state.story_variant=true
	camp._play_chapter(32,"victory",func():pass)
	check(not music.playback_suspended(),"L32 victory TXT does not acquire MPEG/entry gate")
	if is_instance_valid(camp.story_player):camp.story_player._finish()
	camp.queue_free();await process_frame
	var m2:Dictionary=Codec.integers(JSON.parse_string(FileAccess.get_file_as_string("res://data/m2.json")))
	var m4:Dictionary=Codec.integers(JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json")))
	var gs=load("res://scripts/m2/GameState.gd").new();gs.new_game(m2);gs.setup_m4(m4)
	var b=load("res://scripts/Battle.gd").new();root.add_child(b)
	b.setup(m4,Builder.build(m4,m2,0,[gs.protagonist_member()]),load("res://assets/font/hzk16.fnt"),gs.battle_context())
	b.set_process(false);b.presentation_in_headless=true;b.sfx_enabled=false;b.animation_speed=1;b.phase="qa";b.scenario=null
	var anm_events:Array=[]
	b.presentation_step.connect(func(kind,payload):
		if kind.begins_with("anm_"):anm_events.append({"kind":kind,"payload":payload}))
	var u=b.unit_by_slot(0);var enemy=b.unit_by_slot(40)
	u.set_tile(5,5);enemy.set_tile(6,5);enemy.hp=500;enemy.max_hp=500;u.data.zhili=100;enemy.data.zhili=20;u.skill_counts.huogong=1
	b.selected=u;b.active_skill_id=3;b.active_skill=b.data.skills[3]
	var started:=Time.get_ticks_msec()
	b._execute_skill_at(Vector2i(6,5))
	check(b.busy and enemy.hp==500 and not u.acted,"ANM begins before damage/practice/action commit")
	var anim=b.fx_root.get_child(b.fx_root.get_child_count()-1)
	check(anim is AnimatedSprite2D and anim.scale==Vector2.ONE and anim.sprite_frames.get_frame_texture("default",0).region.size==Vector2(320,200),"ANM native320x200, unscaled")
	check(not anim.visible and anim.sprite_frames.get_animation_speed("default")==20.0,"ANM waits before first frame at50ms")
	var bounds:Vector4=anim.material.get_shader_parameter("clip_bounds")
	check(bounds.is_equal_approx(Vector4(14.0/640,32.0/480,446.0/640,464.0/480)),"ANM exact normal-map shader clip")
	var first_flm:=-1
	var seen_overlap:=false
	var original_hp_during_flm:=false
	while b.busy and Time.get_ticks_msec()-started<12000:
		var anm_visible:=false
		var flm_visible:=false
		for fx in b.fx_root.get_children():
			if not fx is AnimatedSprite2D or fx.is_queued_for_deletion():continue
			var width:int=fx.sprite_frames.get_frame_texture("default",0).region.size.x
			if width==320:anm_visible=true
			elif width==48:flm_visible=true
		if flm_visible:
			if first_flm<0:first_flm=Time.get_ticks_msec()-started;original_hp_during_flm=enemy.hp==500
			seen_overlap=seen_overlap or anm_visible
		await process_frame
	check(first_flm>=1485 and not seen_overlap and original_hp_during_flm,"30 native ANM frames complete before20ms FLM, before damage")
	check(anm_events.filter(func(e):return e.kind=="anm_frame").map(func(e):return e.payload.frame)==range(30),"FFPACT00 frame sequence0..29, no loop-back record")
	check(anm_events[0].kind=="anm_begin" and anm_events[-1].kind=="anm_end","ANM publishes complete begin/frame/end transaction")
	check(not b.busy and enemy.hp<500 and u.skill_counts.huogong==2 and u.acted,"skill commits exactly once after complete presentation")
	b.animation_speed=0
	anm_events.clear()
	started=Time.get_ticks_msec()
	await b._play_anm_sheet("res://assets/m5/anm/ffpact00_sheet.png",Vector2.ZERO)
	check(Time.get_ticks_msec()-started>=1485 and anm_events.filter(func(e):return e.kind=="anm_frame").size()==30,"speed0 still keeps original30 x50ms; only FLM skips")
	b.animation_speed=4;anm_events.clear();started=Time.get_ticks_msec()
	await b._play_anm_sheet("res://assets/m5/anm/ffpact04_sheet.png",Vector2.ZERO)
	check(Time.get_ticks_msec()-started>=3485 and anm_events.filter(func(e):return e.kind=="anm_frame").map(func(e):return e.payload.frame)==range(70),"FFPACT04 speed4 native70 frames, fixed50ms")
	b.fullscreen_map=true
	bounds=b._effect_clip_material().get_shader_parameter("clip_bounds")
	check(bounds.is_equal_approx(Vector4(0,0,624.0/640,1)),"full-map clip excludes original right16px strip")
	check(int(b.data.items["44"].anm_index)==44,"battle generator carries original throwing ANM index")
	b.fullscreen_map=false;b.animation_speed=0
	anm_events.clear()
	enemy.hp=500;enemy.morale=100
	var tile:=Vector2i(enemy.x,enemy.y)
	b.mines.append({"tile":tile,"mine":b.data.mines[0],"mine_id":0,"code":0,"low":1})
	started=Time.get_ticks_msec()
	b._detonate_mines(tile)
	check(b.busy and enemy.hp==500 and b.mines.is_empty(),"mine removes trigger but awaits ANM before damage")
	while b.busy and Time.get_ticks_msec()-started<12000:await process_frame
	check(not b.busy and enemy.hp==380 and Time.get_ticks_msec()-started>=1735,"35-frame native mine ANM completes before exact120 damage")
	check(anm_events.filter(func(e):return e.kind=="anm_frame").map(func(e):return e.payload.frame)==range(35),"MINE00 frame sequence0..34, no repeated first frame")
	u.acted=false;u.item_slots=[45,0,0,0,0,0,0,0]
	b.selected=u;b.active_item_id=44
	started=Time.get_ticks_msec()
	b._execute_item_at(tile)
	check(b.busy and enemy.hp==380 and u.item_slots[0]==45 and not u.acted,"throwing ANM precedes damage and consumption")
	while b.busy and Time.get_ticks_msec()-started<12000:await process_frame
	check(not b.busy and enemy.hp==320 and u.item_slots[0]==0 and u.acted,"throw resolves/consumes once after presentation")
	b.queue_free();await process_frame;await create_timer(0.5).timeout
	music.release_playback()
	print("ORIGINAL_MEDIA checks=",checks," failures=",failures)
	if failures==0:print("ORIGINAL_MEDIA_OK")
	quit(1 if failures else 0)
