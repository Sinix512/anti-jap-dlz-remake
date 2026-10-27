extends SceneTree
const Choice=preload("res://scripts/ui/OriginalChoice.gd")
const Final=preload("res://scripts/ui/OriginalFinalImage.gd")
const EndPage=preload("res://scripts/ui/OriginalEndingPage.gd")
const Fade=preload("res://scripts/ui/OriginalPaletteFade.gd")
class ProbeCampaign extends "res://scripts/m4/Campaign.gd":
	var launched:Array=[]
	func _launch_level(idx:int,standalone:bool,slots:Array=[]) -> void:
		launched.append({"idx":idx,"standalone":standalone,"slots":slots.duplicate()})
class OrderCampaign extends "res://scripts/m4/Campaign.gd":
	var events:Array=[]
	func _show_ending(_forced:=-1) -> void:events.append("END")
	func _play_chapter(idx:int,_branch:String,cb:Callable) -> void:
		events.append("chapter%d"%idx);cb.call()
class CloseMain extends "res://scripts/Main.gd":
	var close_count:=0
	var title_count:=0
	func _close_campaign_game() -> void:close_count+=1
	func _show_title() -> void:title_count+=1
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("ENDING_FAIL "+label)
func mouse(button:int,down:=false,point:=Vector2(600,440)) -> void:
	var e:=InputEventMouseButton.new();e.button_index=button;e.pressed=down;e.position=point;e.global_position=point;root.push_input(e,true)
func key(down:=false) -> void:
	var e:=InputEventKey.new();e.keycode=KEY_SPACE;e.pressed=down;root.push_input(e,true)
func move(point:Vector2) -> void:
	var e:=InputEventMouseMotion.new();e.position=point;e.global_position=point;root.push_input(e,true)
func run() -> void:
	var c=ProbeCampaign.new();root.add_child(c);c.setup(load("res://assets/font/hzk16.fnt"));c.qa_mode=true
	c.state.hidden_unlocked=true;c.state.main_score_snapshot=3600
	c._show_ending()
	var end_player=c.ending_layer.get_child(0)
	check(c.mode=="ending" and end_player.context.native_palette_key=="KUANG04","END story inherits battle palette, not strategic K00")
	check(c.ending_steps[-1].records==[407],"END05 EB26 jumps over405/406 to W")
	check(c.m5.endings[5].records==[407],"generated END05 keeps407-only contract")
	c._show_hidden_choice()
	var notice=c.ending_layer.get_child(-1);notice.native_page.set_process(false)
	check(c.mode=="hidden_notice" and notice.context.native_palette_key=="KUANG04","original dynamic hidden notice precedes menu")
	check(notice.lines[0].width==46 and notice.lines[0].code==-1,"hidden notice uses native narrator layout")
	check(notice._fmt("GG")=="AA李AA勇","native GG is red protagonist glyphs")
	check(c.ending_layer.find_children("*","BaseButton",true,false).is_empty(),"no score heading or modern third button")
	mouse(MOUSE_BUTTON_LEFT);notice.native_page._advance(.006)
	check(notice.native_page.stage=="wait","notice rolls before independent wait")
	await process_frame;await process_frame
	mouse(MOUSE_BUTTON_RIGHT);notice.native_page._advance(.199)
	check(c.mode=="hidden_notice","notice keeps actual200ms record tail")
	notice.native_page._advance(.002);await process_frame
	var menu=c.ending_layer.get_child(-1)
	check(menu is Choice and c.mode=="hidden_choice","notice completion reaches actual native choice")
	check(menu.frame==Rect2(320,200,88,64) and menu.entries==["模  拟","虚  构"],"original two labels and MENU geometry")
	check(menu.row_rect(0)==Rect2(324,208,80,24) and menu.row_rect(1)==Rect2(324,232,80,24),"two original selection rectangles")
	check(menu.labels[0].position==Vector2(332,212) and menu.labels[1].position==Vector2(332,236),"original text origins")
	check(menu.palette==preload("res://scripts/ui/OriginalPalette.gd").colors("KUANG04") and menu.allow_cancel,"choice uses live battle palette and cancellation")
	check(menu.drawn_heights==range(2,65,4) and menu.raster_root.size.y==262,"synchronous2,6,...62 leaves native bottom2 rows untouched")
	key();mouse(MOUSE_BUTTON_LEFT)
	check(c.mode=="hidden_choice","KEYUP and LEFTUP cannot submit native choice")
	var exits:Array=[];c.game_close_requested.connect(func():exits.append(true))
	var title_exits:Array=[];c.exit_requested.connect(func():title_exits.append(true))
	mouse(MOUSE_BUTTON_RIGHT,true)
	check(c.mode=="finale" and c.ending_layer.get_child(-1) is Final,"RIGHTDOWN cancel enters JZ-1, not town or third menu item")
	check(menu.restore_count==1 and OriginalUI.native_text_index==0x48,"cancel restores saved rect once and font48")
	check(c.ending_layer.get_child(-1).fade_events==[{"entering":true,"increment":1}],"JZ1 enters with step1, no1000ms hold")
	mouse(MOUSE_BUTTON_RIGHT)
	check(c.ending_layer.get_child(-1).get_child(0).texture.resource_path.ends_with("jz1.png"),"old cancel release cannot cross new wait")
	await process_frame;await process_frame
	key(true);mouse(MOUSE_BUTTON_LEFT,true)
	check(exits.is_empty() and not c.ending_layer.get_child(-1).done,"key and mouse DOWN never release finale")
	key()
	check(c.ending_layer.get_child(-1).get_child(0).texture.resource_path.ends_with("jz2.png"),"KEYUP advances first native image")
	check(c.ending_layer.get_child(-1).exit_increment==1,"last JZ has step1 fade-out")
	key();check(exits.is_empty(),"same-frame queued KEYUP cannot cross two images")
	await process_frame;await process_frame
	OriginalUI.native_wait_left_blocked=true;mouse(MOUSE_BUTTON_LEFT)
	check(exits.is_empty() and not OriginalUI.native_wait_left_blocked,"inherited57BD44 swallows one LEFTUP and clears")
	mouse(MOUSE_BUTTON_RIGHT)
	check(exits.size()==1 and title_exits.is_empty(),"fresh RIGHTUP closes application, never returns JZ to title")
	c._show_hidden_menu();menu=c.ending_layer.get_child(-1)
	move(Vector2(1,236));mouse(MOUSE_BUTTON_LEFT,true,Vector2(639,479))
	check(c.state.campaign_index==40 and c.mode=="town" and c.state.current_town==17,"MOVE selects fiction; DOWN confirms current row regardless of click point")
	check(preload("res://scripts/m4/TownRules.gd").get_flag(c.state,85)==2 and c.launched.is_empty(),"fiction enters original town17 phase2 before battle")
	c._show_hidden_menu();mouse(MOUSE_BUTTON_LEFT,true)
	check(c.launched.size()==1 and c.launched[0].idx==36 and not c.launched[0].standalone,"initial row0 starts simulation36 only")
	check(not is_instance_valid(c.ending_layer),"accepted route releases ending overlay")
	await verify_end_pages(c)
	await verify_chapter_order(c)
	var app=CloseMain.new();app.qa_mode=true;root.add_child(app);app._start_campaign()
	var title_before:int=app.title_count
	app.campaign._show_final_image(2)
	check(app.close_count==1 and app.title_count==title_before,"real Main wiring dispatches JZ only to overridable process-close method")
	app.campaign.exit_requested.emit()
	check(app.close_count==1 and app.title_count==title_before+1,"ordinary campaign exit retains original return-to-title wiring")
	app.queue_free();await process_frame;await process_frame
	check(Fade.colors_at([0,63,128,252],128,true,1)==[0,63,128,128],"step1 fade-in clamps palette components")
	check(Fade.colors_at([0,63,128,252],128,false,1)==[0,0,0,124],"step1 fade-out subtracts components")
	check(Fade.colors_at([252],256,false,1)==[0] and Fade.colors_at([252],64,true)==[252],"step1/default4 endpoints preserve old fade API")
	c.queue_free();await process_frame;await process_frame
	root.get_node("Music").release_playback();OriginalUI.release_native_sfx()
	print("ORIGINAL_ENDING checks=",checks," failures=",failures)
	if failures==0:print("ORIGINAL_ENDING PASS")
	quit(1 if failures else 0)

func verify_end_pages(c) -> void:
	# Synthetic one-glyph records isolate actual D/text/W sequencing. This is
	# a UI unit fixture, never a campaign win or natural-route evidence.
	for index in range(6):
		var ids:Array=c.m5.endings[index].records
		var records:Array=[]
		for id in ids:records.append({"n":id,"lines":[{"code":-1,"text":"终"}]})
		var page=EndPage.new();root.add_child(page)
		page.setup(c.font,{"records":records},index,ids,"李勇",{})
		page.set_process(false)
		var completed:Array=[];page.confirmed.connect(func():completed.append(true))
		page._advance(1.0);key();mouse(MOUSE_BUTTON_RIGHT)
		check(page.stage=="hold_pre" and page.story==null,"END%d elapsed1000 and input do not skip D"%index)
		page._advance(.001)
		check(page.stage=="text" and page.story.ids==ids and page.story.context.native_palette_key=="KUANG04","END%d starts exact records only after D"%index)
		for n in range(ids.size()):
			var text_page=page.story.native_page;text_page.set_process(false)
			mouse(MOUSE_BUTTON_LEFT);text_page._advance(.006)
			await process_frame;await process_frame
			mouse(MOUSE_BUTTON_RIGHT);text_page._advance(.199)
			check(page.stage=="text","END%d record%d keeps its own200ms tail"%[index,n])
			text_page._advance(.002)
		if index==3:
			check(page.stage=="hold_post" and page.release_wait==null,"END03 has post-D, not an extra W")
			key();page._advance(1.0)
			check(completed.is_empty(),"END03 post-D cannot be clicked through or expire at1000ms")
			page._advance(.001)
		else:
			check(page.stage=="extra_wait" and page.story==null and page.get_child(0).visible,"END%d preserves image after text for distinct outer W"%index)
			mouse(MOUSE_BUTTON_RIGHT)
			check(completed.is_empty(),"END%d same-frame release cannot cross into outer W"%index)
			await process_frame;await process_frame
			OriginalUI.native_wait_left_blocked=true;mouse(MOUSE_BUTTON_LEFT)
			check(completed.is_empty() and not OriginalUI.native_wait_left_blocked,"END%d outer W inherits57BD44"%index)
			key()
		var expected_fades:Array=[{"entering":true,"increment":1}]
		if index not in [4,5]:expected_fades.append({"entering":false,"increment":4})
		check(completed.size()==1 and page.fade_events==expected_fades,"END%d exact fade1/D/text/outer; only intermediate END owns exit fade"%index)
		page.queue_free();await process_frame

func verify_chapter_order(c) -> void:
	var ordered=OrderCampaign.new();root.add_child(ordered);ordered.setup(c.font);ordered.qa_mode=true
	ordered.highscore_path="user://ending259_isolated_hiscore.dat"
	ordered._last_report={"victory":true,"idx":35,"standalone":false}
	ordered._report_continue()
	check(ordered.events==["END"],"L35 result must not play chapter before END")
	if FileAccess.file_exists(ordered.highscore_path):DirAccess.remove_absolute(ProjectSettings.globalize_path(ordered.highscore_path))
	ordered.queue_free();await process_frame
	c.state.story_variant=true;c.state.hidden_unlocked=true
	c.ending_flow_events.clear();c.ending_preview=false;c.ending_step=c.ending_steps.size()
	c._play_ending_step()
	var chapter=c.ending_layer.get_child(-1)
	check(c.ending_flow_events==["chapter35"] and chapter.ids==[592],"complete END group enters chapter592 before any hidden choice")
	check(chapter.context.native_palette_key=="KUANG04" and not chapter.context.battle_profile,"L35 chapter text preserves native palette on black, not K00")
	chapter._finish();await process_frame
	check(c.ending_flow_events==["chapter35","hidden_notice"],"high-score chapter then native hidden notice")
	c.state.hidden_unlocked=false;c.ending_flow_events.clear();c._play_ending_chapter()
	c.ending_layer.get_child(-1)._finish();await process_frame
	check(c.ending_flow_events==["chapter35","finale"],"low score still plays chapter before JZ")
