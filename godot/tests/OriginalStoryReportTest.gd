extends SceneTree
# Synthetic UI/state-machine vectors; never campaign completion evidence.
const Layout=preload("res://scripts/ui/OriginalStoryLayout.gd")
const Page=preload("res://scripts/ui/OriginalStoryPage.gd")
const Report=preload("res://scripts/ui/OriginalVictoryReport.gd")
var checks:=0
var failures:=0
var font:Font
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("STORY_REPORT_FAIL "+label)
func mouse(button:int,down:=false) -> void:
	var e:=InputEventMouseButton.new();e.position=Vector2(600,10);e.button_index=button;e.pressed=down;root.push_input(e,true)
func key(down:=false) -> void:
	var e:=InputEventKey.new();e.keycode=KEY_Q;e.pressed=down;root.push_input(e,true)
func make_page(record_end:=true,battle_profile:=false):
	var page=Page.new();root.add_child(page);page.setup(font,Layout.pages("战斗胜利！","",46)[0],-1,"KUANG04",46)
	page.set_process(false);page.record_end=record_end;page.battle_profile=battle_profile;return page
func to_wait(page) -> void:
	page.height=99;page._scroll_step();await process_frame;await process_frame
func remove(node:Node) -> void:node.queue_free();await process_frame
func run() -> void:
	font=load("res://assets/font/hzk16.fnt")
	var p:Array=Layout.pages("战斗胜利！","",46)
	check(p.size()==1 and p[0][4].text=="战" and p[0][4].x==32,"fixed narrator has four-space prefix")
	p=Layout.pages("一".repeat(100),"李  勇",36)
	check(p.size()==2,"five-row byte pages")
	check(p[0].filter(func(g):return g.y==20 and g.text=="一")[0].x==32,"name padding leaves first-body indent")
	check(p[1][0].text=="一" and p[1][0].x==0 and p[1][0].y==0,"continuation does not repeat name or indent")
	p=Layout.pages("一".repeat(15)+"。二","",36)
	check(p[0].filter(func(g):return g.text=="。")[0].y==0,"five exact punctuation pairs may occupy final cell")
	p=Layout.pages("一".repeat(15)+"三二","",36)
	check(p[0].filter(func(g):return g.text=="三")[0].y==20,"non-punctuation stays on next row")
	p=Layout.pages("AA甲BB乙CC丙DD丁戊","",36)
	check(p[0].filter(func(g):return g.text in ["甲","乙","丙","丁","戊"]).map(func(g):return g.color)==[0xB7,0x85,0x89,0x4F,0x48],"ABCD controls color exactly next glyph")
	check(Layout.plain_rows("AA甲")[0]=="AA甲","43D56B plain notification does not interpret markers or prefix")
	var player=load("res://scripts/m5/StoryPlayer.gd").new();root.add_child(player)
	player.setup(font,{"records":[{"n":1,"lines":[{"code":-1,"text":"一".repeat(100)}]}]},[1],"李勇",Callable(),{"battle_profile":true,"level_name":"平阳"})
	check(player.lines[0].width==36 and not player.lines[0].record_end and player.lines[-1].record_end,"battle narrator staysW36 and record tail only on final page")
	check(player._fmt("GG在TT")=="AA李AA勇在AA平AA阳","GG and TT expand red glyph by glyph")
	check(player._indicator==null,"no invented fixed down arrow")
	await remove(player)
	OriginalUI.native_wait_left_blocked=false
	var page=make_page()
	page._advance(0.006);check(page.shown_height==1 and page.raster.position.y==98,"h1 crop begins at98")
	page.height=50;page._scroll_step();check(page.shown_height==50 and page.raster.position.y==49,"h50 crop begins at49")
	mouse(MOUSE_BUTTON_LEFT);check(page.height==99 and page.shown_height==50 and page.stage=="scroll","roll leftUP only requests99")
	page._advance(0.006);check(page.stage=="wait" and page.shown_height==99 and page.raster.position.y==0,"next animation step draws99 and starts independent wait")
	mouse(MOUSE_BUTTON_RIGHT);check(page.stage=="wait","same-frame queued release cannot exit wait")
	await process_frame;await process_frame
	page._advance(10);check(page.stage=="wait" and not page.done,"short message never auto-closes")
	key(true);check(page.stage=="wait","keyDOWN does not acknowledge")
	key();check(page.stage=="tail","arbitrary keyUP acknowledges")
	page._advance(0.199);check(not page.done and page.visible,"general record preserves frame during200ms")
	page._advance(0.002);check(page.done,"record tail completes")
	await remove(page)
	page=make_page(false);await to_wait(page);mouse(MOUSE_BUTTON_RIGHT);page._advance(0);check(page.done,"internal page has no200ms tail");await remove(page)
	page=make_page(true,true);await to_wait(page);mouse(MOUSE_BUTTON_RIGHT);check(not page.visible and page.stage=="tail","battle record restores frame before200ms tail");await remove(page)
	page=make_page();OriginalUI.native_wait_left_blocked=true;await to_wait(page);key();check(OriginalUI.native_wait_left_blocked and page.stage=="tail","keyUP leaves inherited57BD44 set");await remove(page)
	page=make_page();await to_wait(page);mouse(MOUSE_BUTTON_LEFT);check(not OriginalUI.native_wait_left_blocked and page.stage=="wait","inherited left gate clears and swallows exactly once");mouse(MOUSE_BUTTON_LEFT);check(page.stage=="tail","next release acknowledges without resetting gate per page");await remove(page)
	var report=Report.new();root.add_child(report);OriginalUI.native_text_index=0x48
	report.setup(font,{"kills_by_mine":2,"kills_by_gun":1,"kills":999,"losses":1,"captured_items":4},76,126);report.set_process(false)
	var events:Array=[];report.counter_step.connect(func(index,value):events.append([index,value]))
	report._advance(.999);check(report.stage=="background" and report.displayed==[-1,-1,-1,-1,-1,-1,-1],"MENU10 holds background1000ms before counters")
	mouse(MOUSE_BUTTON_RIGHT);check(not report.done,"input cannot skip hold")
	report._advance(.001);check(report.counter==0 and report.displayed[0]==1,"first counter starts at1 after hold")
	report._advance(.04);check(report.displayed[0]==2 and report.displayed[1]==-1,"counter increments serially")
	key();check(not report.done and report.stage=="counter","input cannot skip counts")
	for i in range(30):report._advance(1)
	check(report.displayed==[2,1,3,1,4,76,126],"report kill total is gun+mine, not arbitrary kills")
	check(report.grade_visible and report.grade=="  合  格" and report.stage=="wait","exact spaced grade precedes cumulative counter")
	check(events.find([5,76])<events.find([6,1]),"six numeric counters precede cumulative")
	check(report._interval(100)==.03 and report._interval(4000)==0,"native floor3000/value cap40ms")
	mouse(MOUSE_BUTTON_LEFT);check(not report.done,"count completion flushes pending release in same frame")
	await process_frame;await process_frame
	OriginalUI.native_wait_left_blocked=true;mouse(MOUSE_BUTTON_LEFT);check(not report.done and not OriginalUI.native_wait_left_blocked,"report inherits flag rather than setting it on open")
	mouse(MOUSE_BUTTON_LEFT);check(report.done,"report accepts any-position fresh leftUP")
	await remove(report)
	var camp=preload("res://tests/helpers/LegalProbeCampaign.gd").new();root.add_child(camp);camp.setup(font)
	camp._launch_level(0,true,[-100]);await camp.drain_story();camp.battle.set_process(false)
	camp.battle.stats={"kills_by_mine":2,"kills_by_gun":3,"kills":999,"loot_count":1,"losses":0}
	camp.battle.battle_context["temporary_loot"]={"1":3,"5":2}
	camp._show_report(true,"not displayed condition",0,100,{"total":234},false)
	var notice=camp.result_canvas.get_child(0);notice.set_process(false)
	check(notice.get_script()==Page and root.get_node("Music").current_scene!=43,"Campaign victory first keeps battle BGM and native fixed notice")
	check(notice.raster.glyphs[4].text=="战" and notice.raster.glyphs[4].x==32,"Campaign fixed victory is original four-space narration")
	await to_wait(notice);mouse(MOUSE_BUTTON_RIGHT);notice._advance(.201);await process_frame
	var report_page=camp.result_canvas.get_child(-1);report_page.set_process(false)
	check(report_page.get_script()==Report and root.get_node("Music").current_scene==43,"native report starts scene43 before hold and counts")
	check(report_page.values==[2,3,5,0,5,100,234],"Campaign uses temporary-loot quantities, never chest-count")
	check(camp.result_canvas.get_child_count()==1,"no modern level-up summary, title, joined row or report buttons")
	camp.queue_free();await process_frame;await process_frame
	root.get_node("Music").release_playback();OriginalUI.release_native_sfx()
	print("ORIGINAL_STORY_REPORT checks=",checks," failures=",failures)
	if failures==0:print("ORIGINAL_STORY_REPORT PASS")
	quit(1 if failures else 0)
