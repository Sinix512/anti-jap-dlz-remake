extends SceneTree
# Synthetic production-route/settlement fixtures, NOT played wins or fresh
# interlude coverage. RNG is seeded only for repeatable unit-test sampling.
const Town=preload("res://scripts/m4/TownRules.gd")
const State=preload("res://scripts/m2/GameState.gd")
class RouteCampaign extends "res://scripts/m4/Campaign.gd":
	var actions:Array=[]
	func _show_room(_kind:String) -> void:pass
	func _play_story(_ids:Array,cb:Callable) -> void:cb.call()
	func _launch_level(idx:int,standalone:bool,_slots:Array=[]) -> void:
		current_battle_index=idx
		actions.append({"kind":"battle","idx":idx,"standalone":standalone,"state":state.to_dict()})
	func _show_town(town:int) -> void:actions.append({"kind":"town","town":town})
	func _show_finale() -> void:actions.append({"kind":"finale"})
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("ROUTE_TRANSACTION "+label)
func run() -> void:
	seed(259)
	var c=RouteCampaign.new();root.add_child(c);c.setup(load("res://assets/font/hzk16.fnt"));c.qa_mode=true
	for return_index in [1,8,35,40]:
		c.state.new_game(c.m2);c.state.setup_m4(c.m4)
		c.state.campaign_index=return_index;c.state.current_town=0;c.selected_town=0
		Town.set_flag(c.state,0,2)
		for idx in [44,45,46]:
			c.actions.clear()
			for attempt in range(256):
				c._service_heal()
				if not c.actions.is_empty():break
			check(c.actions.size()==1 and c.actions[0].kind=="battle" and c.actions[0].idx==idx,"resident launches next one-shot interlude%d"%idx)
			check(c.state.campaign_index==idx and c.current_battle_index==idx and Town.get_flag(c.state,91)==return_index,"active index and saved return agree before launch%d"%idx)
			check([Town.get_flag(c.state,3),Town.get_flag(c.state,4),Town.get_flag(c.state,9)]==[1,1 if idx>=45 else 0,1 if idx>=46 else 0],"one-shot flags commit in original order%d"%idx)
			var snapshot:Dictionary=c.actions[0].state
			var restored=State.new();restored.new_game(c.m2);restored.setup_m4(c.m4)
			check(restored.from_dict(snapshot) and restored.campaign_index==idx and Town.get_flag(restored,91)==return_index,"battle-entry save preserves active and return indices%d"%idx)
			var old_item:int=c.state.item_count(56)
			c._last_report={"victory":false,"idx":idx,"standalone":false,"score":17,"settlement_pending":true}
			c._commit_victory_result()
			check(c.state.campaign_index==idx and c.state.item_count(56)==old_item,"defeat does not restore index or grant reward%d"%idx)
			c._last_report={"victory":true,"idx":idx,"standalone":false,"score":17,"settlement_pending":true}
			c._commit_victory_result();c._commit_victory_result()
			check(c.state.campaign_index==return_index and c.state.current_town==0 and Town.get_flag(c.state,91)==return_index,"victory restores original route and town without clearing return%d"%idx)
			check(c.state.item_count(56)==old_item+(1 if idx==45 else 0),"only45 grants one item56, no duplicate commit%d"%idx)
			c.actions.clear();c._after_victory(idx)
			check(c.actions==[{"kind":"town","town":0}],"interlude returns town, never next battle/finale%d"%idx)
		c.actions.clear()
		for attempt in range(128):c._service_heal()
		check(c.actions.is_empty() and c.state.campaign_index==return_index,"spent interludes never relaunch at return%d"%return_index)
	# No fiction-only phase write is allowed before the actual option1 click.
	Town.set_flag(c.state,85,7);c.state.apply_phase_state(c.state.m4_level(35).victory_phase)
	check(Town.get_flag(c.state,85)==7,"common L35 result does not precommit fiction flag85")
	for idx in range(36,44):
		var phase:Dictionary=c.state.m4_level(idx).victory_phase
		var threshold:int=int(phase.get("hidden_threshold",{}).get("main_score_snapshot_gte",99999))
		for sufficient in [false,true]:
			c.actions.clear();c.state.score_total=999999;c.state.main_score_snapshot=threshold if sufficient else threshold-1
			c.state.apply_phase_state(phase);c._after_victory(idx)
			var should_stop:bool=not sufficient or idx in [39,43]
			check(c.actions.size()==1 and (c.actions[0].kind=="finale")==should_stop,"hidden%d uses frozen threshold, terminal39/43 always stops (%s)"%[idx,str(sufficient)])
	c.queue_free();await process_frame;await process_frame
	root.get_node("Music").release_playback();OriginalUI.release_native_sfx();await create_timer(.3).timeout
	print("ORIGINAL_ROUTE_TRANSACTION checks=",checks," failures=",failures)
	if failures==0:print("ORIGINAL_ROUTE_TRANSACTION PASS")
	quit(1 if failures else 0)
