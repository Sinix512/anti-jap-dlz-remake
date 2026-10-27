extends SceneTree
const Palette=preload("res://scripts/ui/OriginalPalette.gd")
func _initialize() -> void:call_deferred("run")
func shot(name:String) -> void:
	for i in range(3):await process_frame
	RenderingServer.force_sync();RenderingServer.force_draw()
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../out/ui_save/"+name+".png"));print("SAVE_SHOT ",name)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../out/ui_save"))
	var slots:Array=[{}, {"mode":150,"level":9,"difficulty":1,"turn":3,"intro":"虎口救亲人"},{},{"mode":57,"level":4,"difficulty":2,"turn":8,"intro":"高家庄"},{}]
	for key in ["BG01","KUANG04","PLACE04","PLACE05","K00"]:
		var bg:=ColorRect.new();bg.size=Vector2(640,480);bg.color=Palette.color_at(Palette.colors(key),0x7F);root.add_child(bg)
		var p=load("res://scripts/ui/OriginalSavePicker.gd").new();root.add_child(p);p.setup(load("res://assets/font/hzk16.fnt"),Palette.colors(key),slots,true)
		await shot(key+"_normal");p._select(1);await shot(key+"_row1");p._select(4);await shot(key+"_row4")
		var e:=InputEventMouseMotion.new();e.position=Vector2(20,450);e.global_position=e.position;root.push_input(e,true);await shot(key+"_retained")
		p.free();bg.free()
	root.get_node("Music").release_playback();OriginalUI.release_native_sfx();await create_timer(0.3).timeout
	print("ORIGINAL_SAVE_QA_COMPLETE");quit()
