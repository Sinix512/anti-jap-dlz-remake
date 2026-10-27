extends SceneTree
var font:Font
var manifest:Dictionary={}
var out:="res://../out/ui_story_report/"
const Palette=preload("res://scripts/ui/OriginalPalette.gd")
const Layout=preload("res://scripts/ui/OriginalStoryLayout.gd")
func _initialize() -> void:call_deferred("run")
func shot(name:String,state:Dictionary) -> void:
	for i in range(3):await process_frame
	RenderingServer.force_sync();RenderingServer.force_draw()
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(out+name+".png"));manifest[name]=state
	print("STORY_REPORT_SHOT ",name)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out));font=load("res://assets/font/hzk16.fnt")
	OriginalUI.native_text_index=0x48
	var report=preload("res://scripts/ui/OriginalVictoryReport.gd").new();root.add_child(report);report.setup(font,{"kills_by_mine":2,"kills_by_gun":1,"losses":1,"captured_items":4},76,126);report.set_process(false)
	await shot("report_background",{"mode":"report","values":report.displayed.duplicate(),"grade":report.grade_visible})
	report._advance(1);await shot("report_first",{"mode":"report","values":report.displayed.duplicate(),"grade":report.grade_visible})
	report._advance(.04);await shot("report_mine2",{"mode":"report","values":report.displayed.duplicate(),"grade":report.grade_visible})
	while report.counter<5:report._advance(.001)
	await shot("report_score1",{"mode":"report","values":report.displayed.duplicate(),"grade":report.grade_visible})
	while report.counter<6:report._advance(.001)
	await shot("report_total1",{"mode":"report","values":report.displayed.duplicate(),"grade":report.grade_visible})
	for i in range(30):report._advance(1)
	await shot("report_done",{"mode":"report","values":report.displayed.duplicate(),"grade":report.grade_visible})
	report.free()
	var bg:=TextureRect.new();bg.texture=Palette.asset("bg02",640,480,Palette.colors("KUANG04"));root.add_child(bg)
	var fixtures:=[{"name":"narrator","text":"战斗胜利！","speaker":"","face":-1,"width":46},{"name":"portrait","text":"GG，AA李AA正同志，BB冈BB村已经来了！".repeat(3),"speaker":"李  勇","face":103,"width":36},{"name":"battle_narrator","text":"一".repeat(15)+"，战斗失败！","speaker":"","face":-1,"width":36}]
	for fixture in fixtures:
		var page=preload("res://scripts/ui/OriginalStoryPage.gd").new();root.add_child(page);page.setup(font,Layout.pages(fixture.text,fixture.speaker,fixture.width)[0],fixture.face,"KUANG04",fixture.width);page.set_process(false)
		for h in [1,50,99]:
			page.height=h;page._scroll_step()
			var entry:Dictionary=fixture.duplicate();entry["h"]=h;entry["mode"]="page"
			await shot(fixture.name+str(h),entry)
		page.free()
	var file:=FileAccess.open(out+"manifest.json",FileAccess.WRITE);file.store_string(JSON.stringify(manifest));file.close()
	bg.free();await process_frame;root.get_node("Music").release_playback();OriginalUI.release_native_sfx()
	print("ORIGINAL_STORY_REPORT_QA_COMPLETE");quit()
