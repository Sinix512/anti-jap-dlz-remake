extends SceneTree
## Isolated rendered fixtures. Hidden window + offscreen viewport; no saves/input.
const State=preload("res://scripts/m2/GameState.gd")
const Builder=preload("res://scripts/m4/LevelBuilder.gd")
class Observer extends RefCounted:
	var status_text:=""
	func on_tick() -> void:pass
	func on_unit_moved(_u) -> void:pass
	func on_unit_died(_u) -> void:pass
	func check_end() -> bool:return false
var b
var hero
var viewport:SubViewport
var output:String
var manifest:Dictionary={}
func _initialize() -> void:
	root.unfocusable=true
	root.hide()
	call_deferred("run")
func actor(slot:int,tile:Vector2i,faction:int,zhili:int):
	return b._spawn_unit({"slot":slot,"name":"预览夹具","bingzhong":1 if faction==0 else 50,"army_png":"res://assets/army/army_%03d.png"%[30 if faction==0 else 24],"side":"player" if faction==0 else "enemy","faction":faction,"x":tile.x,"y":tile.y,"hp":500,"max_hp":1000,"morale":50,"zhili":zhili,"level":1,"control":false})
func capture(name:String) -> void:
	for i in range(5):await process_frame
	RenderingServer.force_sync()
	RenderingServer.force_draw()
	var pixels:Image=viewport.get_texture().get_image()
	if pixels==null or pixels.is_empty():
		push_error("SKILL_QA missing rendered pixels");quit(1);return
	pixels.save_png(output+"/"+name+".png")
func fixture(name:String,sid:int,center:Vector2i,full:bool) -> void:
	for u in b.units:
		if u!=hero:u.alive=false;u.visible=false
	hero.set_tile(center.x,center.y+2);hero.alive=true;hero.acted=false;hero.moved=false
	hero.hp=500;hero.max_hp=1000;hero.morale=50;hero.data.zhili=80
	hero.skill_counts[b.SKILL_KEYS[sid]]=300
	b.selected=hero;b.busy=false;b.phase="player";b.finished_flag=false
	if sid==3:
		actor(40,center,1,80) # 30%, independent of the template's 100% strength.
		actor(41,center+Vector2i(-1,-1),1,40) # 100%, but strength only 70%.
		actor(42,center+Vector2i(0,-1),1,100) # 0% from intelligence difference.
		actor(43,center+Vector2i(1,-1),0,40) # Wrong faction, 0%.
		actor(44,center+Vector2i(0,-3),1,70) # 50% (40% strength).
	else:
		actor(40,center,0,80)
		var full_target=actor(41,center+Vector2i(-1,0),0,40)
		full_target.hp=full_target.max_hp
		actor(42,center+Vector2i(1,0),1,40)
		actor(43,center+Vector2i(0,-1),0,40)
	if b.fullscreen_map!=full:b._toggle_map_mode()
	b._native_camera_focus(center,"skill_qa")
	b._choose_skill(sid);b.hover_tile=center
	var cells:Array=b.skill_preview_cells()
	if cells.is_empty():push_error("SKILL_QA empty fixture "+name);quit(1);return
	var origin:Vector2=b.camera.position-Vector2(320,240)
	var serial:Array=[]
	for cell in cells:
		serial.append({"tile":[cell.tile.x,cell.tile.y],"screen":[cell.tile.x*48-origin.x,cell.tile.y*48-origin.y],"strength":cell.pct,"chance":cell.chance,"effective":cell.effective})
	var clip:Rect2=b.map_rect()
	manifest[name]={"cells":serial,"map_rect":[clip.position.x,clip.position.y,clip.size.x,clip.size.y],"skill":sid}
	b.overlay.hide();await capture(name+"_base")
	b.overlay.show();b.overlay.queue_redraw();await capture(name)
func run() -> void:
	output=ProjectSettings.globalize_path("res://../out/evidence/strategy_preview_20261029/visual")
	DirAccess.make_dir_recursive_absolute(output)
	viewport=SubViewport.new();viewport.size=Vector2i(640,480)
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	viewport.gui_disable_input=true;root.add_child(viewport)
	var m2:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/m2.json"))
	var m4:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json"))
	var gs=State.new();gs.new_game(m2);gs.setup_m4(m4)
	b=load("res://scripts/Battle.gd").new();viewport.add_child(b)
	b.sfx_enabled=false
	b.setup(m4,Builder.build(m4,m2,0,[gs.protagonist_member()]),load("res://assets/font/hzk16.fnt"),gs.battle_context())
	b.set_process(false);b.scenario=Observer.new();b.animations_enabled=false
	b.mines.clear();b.chests.clear()
	hero=b.unit_by_slot(0)
	await fixture("fire_normal",3,Vector2i(10,9),false)
	await fixture("supply_normal",0,Vector2i(10,9),false)
	await fixture("fire_full",3,Vector2i(10,9),true)
	await fixture("fire_edge",3,Vector2i(2,1),false)
	# Push motion into this isolated viewport, never the OS/user's live game.
	var motion=InputEventMouseMotion.new()
	var origin:Vector2=b.camera.position-Vector2(320,240)
	motion.position=Vector2(2*48+24,48+24)-origin
	motion.global_position=motion.position
	viewport.gui_disable_input=false
	viewport.push_input(motion,true);b._process(0.0)
	if b.hover_tile!=Vector2i(2,1) or b.skill_preview_cells().is_empty():
		push_error("SKILL_QA mouse hover does not update strategy preview: "+str(b.hover_tile)+" mouse="+str(viewport.get_mouse_position()));quit(1);return
	motion=InputEventMouseMotion.new();motion.position=Vector2(600,200)
	motion.global_position=motion.position
	viewport.push_input(motion,true);b._process(0.0)
	if not b.skill_preview_cells().is_empty():
		push_error("SKILL_QA HUD hover retains stale strategy preview");quit(1);return
	var file=FileAccess.open(output+"/manifest.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest,"\t")+"\n");file.close()
	b.queue_free();await process_frame
	viewport.queue_free();await process_frame
	print("SKILL_AREA_PRESENTATION_QA_OK fixtures=",manifest.size())
	quit()
