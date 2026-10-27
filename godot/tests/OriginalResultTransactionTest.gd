extends SceneTree
# Synthetic result-boundary fixtures, NOT played campaign/fresh evidence.
const State=preload("res://scripts/m2/GameState.gd")
const Report=preload("res://scripts/ui/OriginalVictoryReport.gd")
const OriginalUI=preload("res://scripts/ui/OriginalUI.gd")
class ResultCampaign extends "res://tests/helpers/LegalProbeCampaign.gd":
	var continued_indices:Array=[]
	func _after_victory(idx:int) -> void:continued_indices.append(idx)
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	print("RESULT_TRANSACTION ","PASS " if ok else "FAIL ",label)
	if not ok:failures+=1;push_error("RESULT_TRANSACTION "+label)
func release(button:int) -> void:
	var event:=InputEventMouseButton.new();event.button_index=button;event.pressed=false;event.position=Vector2(600,440);root.push_input(event,true)
func fixture(idx:int):
	var camp=ResultCampaign.new();root.add_child(camp);camp.setup(load("res://assets/font/hzk16.fnt"));camp.qa_mode=true
	var gs=camp.state;gs.new_game(camp.m2);gs.setup_m4(camp.m4)
	gs.data=gs.data.duplicate(true);gs.data.meta.save_prefix="dlz_qa_result_transaction_"
	gs.delete_slot(7);gs.delete_slot(8);gs.campaign_index=idx
	camp._launch_level(idx,false,[-100]);await camp.drain_story();camp.battle.set_process(false)
	# Isolate and observe the actual remake autosave, never a user's slot.
	camp.qa_mode=false
	gs.items={"81":65535};gs.score_total=230;gs.kills_by_gun=5;gs.kills_by_mine=4
	camp.battle.battle_context.temporary_loot={"81":2,"1":3,"156":9}
	camp.battle.turn=3;camp.battle.stats={"kills_by_gun":3,"kills_by_mine":2,"losses":1,"enemies_total":9}
	return camp
func dispose(camp) -> void:
	camp.state.delete_slot(7);camp.state.delete_slot(8);camp.queue_free();await process_frame;await process_frame
func run() -> void:
	for idx in [1,6]:
		var camp=await fixture(idx);var gs=camp.state;var day:int=gs.day
		var phase:Dictionary=gs.m4_level(idx).victory_phase
		var old_flags:Dictionary=gs.script_globals.duplicate(true)
		var old_class:int=gs.person(7).bingzhong
		camp._settle_battle("victory","synthetic boundary")
		var score:int=camp._last_report.score
		check(gs.score_total==230 and gs.campaign_index==idx and gs.campaign_completed.is_empty(),"L%d notice has no score or completion yet"%idx)
		check(gs.kills_by_gun==5 and gs.kills_by_mine==4 and gs.item_count(81)==65535 and gs.day==day,"L%d notice has no totals, loot or day advancement"%idx)
		check(gs.script_globals==old_flags and gs.person(7).bingzhong==old_class and not FileAccess.file_exists(gs.save_path(7)),"L%d notice has no phase/autosave"%idx)
		var notice=camp.result_canvas.get_child(0);notice.set_process(false)
		release(MOUSE_BUTTON_LEFT);notice._advance(.006);await process_frame;await process_frame
		release(MOUSE_BUTTON_RIGHT);notice._advance(.201);await process_frame
		var report=camp.result_canvas.get_child(-1);report.set_process(false)
		check(report is Report and gs.score_total==230+score and report.values[-1]==gs.score_total,"L%d report entry adds score and displays new total"%idx)
		camp._commit_victory_score()
		check(gs.score_total==230+score and gs.campaign_index==idx and gs.campaign_completed.is_empty(),"L%d report score is once-only, index remains old"%idx)
		check(gs.kills_by_gun==5 and gs.kills_by_mine==4 and gs.item_count(81)==65535 and int(camp.battle.battle_context.temporary_loot["81"])==2,"L%d report keeps old accumulated kills and unmerged temp"%idx)
		check(gs.script_globals==old_flags and gs.person(7).bingzhong==old_class and gs.day==day and not FileAccess.file_exists(gs.save_path(7)),"L%d report does not apply phase or save a half-result"%idx)
		report._advance(100);await process_frame;await process_frame
		release(MOUSE_BUTTON_RIGHT);await process_frame;await camp.drain_story()
		check(gs.campaign_index==idx+1 and gs.campaign_completed==[idx] and gs.score_total==230+score and gs.day==day+1,"L%d fresh report release commits completion once"%idx)
		check(gs.kills_by_gun==8 and gs.kills_by_mine==6 and gs.item_count(81)==1 and gs.item_count(1)==3,"L%d result accumulates kills and WORD loot"%idx)
		check(gs.current_town==int(phase.town_index) and (int(gs.script_globals.get("0x7d0704",0))==2 and gs.person(7).bingzhong==77 if idx==6 else gs.person(2).faction==0 and gs.person(3).faction==0),"L%d phase hook applies after battle progress, including class/side writes"%idx)
		var saved:Dictionary=gs.slot_info(7)
		check(not saved.is_empty() and saved.campaign_index==idx+1 and saved.kills_by_gun==8 and saved.score_total==gs.score_total and int(saved.items["81"])==1 and saved.battle_resume.is_empty(),"L%d autosave contains the complete transaction"%idx)
		var restored=State.new();restored.new_game(camp.m2);restored.setup_m4(camp.m4)
		check(restored.from_dict(saved) and restored.campaign_index==gs.campaign_index and restored.items==gs.items and restored.script_globals==gs.script_globals and restored.person(7).bingzhong==gs.person(7).bingzhong,"L%d completed autosave restores progression, inventory and phase together"%idx)
		var saved_bytes:=FileAccess.get_file_as_string(gs.save_path(7))
		camp._report_continue();await process_frame
		check(camp.continued_indices==[idx] and gs.kills_by_gun==8 and gs.item_count(81)==1 and gs.day==day+1 and FileAccess.get_file_as_string(gs.save_path(7))==saved_bytes,"L%d repeated continuation neither saves, commits nor dispatches twice"%idx)
		await dispose(camp)
	var camp=await fixture(6);var gs=camp.state;var old:Dictionary=gs.to_dict()
	camp._settle_battle("defeat","synthetic boundary");camp._commit_victory_score();camp._commit_victory_result()
	check(gs.score_total==old.score_total and gs.campaign_index==6 and gs.campaign_completed.is_empty() and gs.day==old.day,"defeat adds no score, completion or day")
	check(gs.kills_by_gun==old.kills_by_gun and gs.items==old.items and int(camp.battle.battle_context.temporary_loot["81"])==2 and not FileAccess.file_exists(gs.save_path(7)),"defeat has no cumulative stats, warehouse commit or completed-result save")
	await dispose(camp)
	root.get_node("Music").release_playback();OriginalUI.release_native_sfx();await create_timer(.3).timeout
	print("ORIGINAL_RESULT_TRANSACTION checks=",checks," failures=",failures)
	if failures==0:print("ORIGINAL_RESULT_TRANSACTION PASS")
	quit(1 if failures else 0)
