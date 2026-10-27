extends SceneTree
var manifest:Dictionary={}
const OUT="res://../out/ui_ending/"
func _initialize() -> void:call_deferred("run")
func shot(name:String,info:Dictionary) -> void:
	for i in range(3):await process_frame
	RenderingServer.force_sync();RenderingServer.force_draw()
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT+name+".png"))
	manifest[name]=info
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var c=preload("res://scripts/m4/Campaign.gd").new();root.add_child(c);c.setup(load("res://assets/font/hzk16.fnt"));c.qa_mode=true
	OriginalUI.native_text_index=0x48;c.state.player_name="李勇";c.state.hidden_unlocked=true;c.state.main_score_snapshot=3600
	# Explicit ending preview fixtures, NOT campaign progress or fresh evidence.
	for i in range(6):
		c._show_ending(i)
		var page=c.ending_layer.get_child(0);page.set_process(false);page.set_process_input(false)
		await shot("end%02d"%i,{"kind":"end","index":i})
	# Static snapshots of the native synchronous palette writes. Not timed
	# animation observations; expected math comes from the original RGB loop.
	c._show_ending(0)
	var fade_page=c.ending_layer.get_child(0);fade_page.set_process(false);fade_page.set_process_input(false)
	var fade=preload("res://scripts/ui/OriginalPaletteFade.gd")
	for spec in [[true,128,1],[false,128,1],[false,32,4],[false,256,1]]:
		var overlay=fade.surface(fade_page,fade_page.get_child(0).texture);fade.phase(overlay,int(spec[1]),bool(spec[0]),int(spec[2]))
		await shot("fade_%s_%d_%d"%[str(spec[0]),spec[1],spec[2]],{"kind":"fade","index":0,"entering":spec[0],"step":spec[1],"increment":spec[2]})
		overlay.free()
	var choice=preload("res://scripts/ui/OriginalChoice.gd").new();fade_page.add_child(choice)
	choice.setup(c.font,["模  拟","虚  构"],Vector2(320,200),true,preload("res://scripts/ui/OriginalPalette.gd").colors("KUANG04"))
	choice.set_process_input(false)
	await shot("choice_on_end",{"kind":"choice","row":0,"end_background":true})
	choice._restore_background()
	await shot("choice_restored",{"kind":"end","index":0})
	c._show_hidden_choice()
	var notice=c.ending_layer.get_child(-1)
	notice.native_page.set_process(false);notice.native_page.set_process_input(false);notice.native_page.height=99;notice.native_page._scroll_step()
	await shot("hidden_notice",{"kind":"notice"})
	c._show_hidden_menu()
	var menu=c.ending_layer.get_child(-1);menu.set_process_input(false)
	await shot("hidden_simulation",{"kind":"choice","row":0})
	menu._select(1);await shot("hidden_fiction",{"kind":"choice","row":1})
	c._show_finale();c.ending_layer.get_child(-1).set_process_input(false)
	await shot("finale1",{"kind":"finale","index":1})
	c._show_final_image(1);c.ending_layer.get_child(-1).set_process_input(false)
	await shot("finale2",{"kind":"finale","index":2})
	var f:=FileAccess.open(OUT+"manifest.json",FileAccess.WRITE);f.store_string(JSON.stringify(manifest));f.close()
	c.queue_free();await process_frame;await process_frame
	root.get_node("Music").release_playback();OriginalUI.release_native_sfx()
	await create_timer(.3).timeout
	print("ORIGINAL_ENDING_QA_COMPLETE");quit()
