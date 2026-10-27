extends "res://scripts/m4/Campaign.gd"

# Same launch/story queue/settlement/retry as the playable Campaign. The only
# injected component audits player permissions; it still calls every resolver.
# Advancing text/movie controls below is a test click, not a scenario shortcut.
var acknowledged_texts:=0
var acknowledged_movies:=0
var drain_errors:Array=[]
var report_inputs:Array=[]
var native_route_input
var route_trace:Array=[]

func route_state() -> Dictionary:
	var flags:Dictionary={}
	for index in [0,3,4,9,85,91]:flags[str(index)]=TownRules.get_flag(state,index)
	return {"index":state.campaign_index,"town":state.current_town,"completed":state.campaign_completed.duplicate(),"hidden_done":state.hidden_done.duplicate(),"score":state.score_total,"scores":state.level_scores.duplicate(true),"frozen":state.main_score_snapshot,"unlocked":state.hidden_unlocked,"flags":flags,"money":state.money,"item56":state.item_count(56)}

func trace_route(kind:String,before:Dictionary,extra:Dictionary={}) -> void:
	if native_route_input==null:return
	route_trace.append({"seq":route_trace.size(),"kind":kind,"before":before.duplicate(true),"after":route_state(),"extra":extra.duplicate(true),"frame":Engine.get_process_frames()})

func _service_heal() -> void:
	var before:=route_state()
	super._service_heal()
	trace_route("resident",before,{"town":selected_town})

func _launch_level(idx:int,standalone:bool,deploy_pids:Array=[]) -> void:
	var before:=route_state()
	super._launch_level(idx,standalone,deploy_pids)
	trace_route("launch",before,{"idx":idx,"standalone":standalone,"deploy":current_deploy_pids.duplicate()})

func _commit_victory_result() -> void:
	var before:=route_state()
	var already:=bool(_last_report.get("result_committed",false))
	super._commit_victory_result()
	if not already:trace_route("commit",before,{"idx":int(_last_report.get("idx",-1)),"report":_last_report.duplicate(true)})

func _start_hidden(mode:String) -> void:
	var before:=route_state()
	super._start_hidden(mode)
	trace_route("hidden",before,{"mode":mode})

func _create_battle() -> Node2D:
	var next=preload("res://tests/helpers/LegalProbeBattle.gd").new()
	next.fast_sim=true
	return next

func drain_story() -> void:
	if native_route_input!=null:
		var deadline:=Time.get_ticks_msec()+180000
		while Time.get_ticks_msec()<deadline:
			if battle_story_queue.is_empty() and not is_instance_valid(story_player) and not is_instance_valid(cutscene) and not battle_visual_active and pending_battle_result.is_empty():return
			native_route_input.pump(self)
			await get_tree().create_timer(.01).timeout
		drain_errors.append("native viewport story input stalled")
		push_error("LEGAL_CAMPAIGN_NATIVE_STORY_STALL")
		return
	for frame in range(4096):
		if is_instance_valid(story_player):
			acknowledged_texts+=1
			story_player._finish()
		if is_instance_valid(cutscene):
			acknowledged_movies+=1
			cutscene._finish()
		if battle_story_queue.is_empty() and not is_instance_valid(story_player) and not is_instance_valid(cutscene) and not battle_visual_active and pending_battle_result.is_empty():return
		await get_tree().process_frame
	drain_errors.append("story queue failed to drain")
	push_error("LEGAL_CAMPAIGN_STORY_STALL")

func drain_result_report() -> bool:
	# Never bypass the report callback: temporary loot is committed only after
	# the real roll/counters and a fresh viewport release. No clock/stage writes.
	var sent:Dictionary={}
	var deadline:=Time.get_ticks_msec()+180000
	while Time.get_ticks_msec()<deadline:
		if not is_instance_valid(result_canvas):
			await drain_story()
			return true
		for node in result_canvas.get_children():
			var key:String=str(node.get_instance_id())+":"+str(node.get("stage"))
			if sent.has(key):continue
			var button:=-1
			if node.get_script()==preload("res://scripts/ui/OriginalStoryPage.gd"):
				if node.stage=="scroll":button=MOUSE_BUTTON_LEFT
				elif node.stage=="wait" and Engine.get_process_frames()>=node.wait_frame:button=MOUSE_BUTTON_RIGHT
			elif node.get_script()==preload("res://scripts/ui/OriginalVictoryReport.gd") and node.stage=="wait" and Engine.get_process_frames()>=node.wait_frame:button=MOUSE_BUTTON_RIGHT
			if button<0:continue
			sent[key]=true
			report_inputs.append({"kind":node.get_script().resource_path,"stage":node.stage,"frame":Engine.get_process_frames()})
			var event:=InputEventMouseButton.new();event.button_index=button;event.pressed=false;event.position=Vector2(600,440);event.global_position=event.position
			get_tree().root.push_input(event,true)
		await get_tree().create_timer(0.01).timeout
	drain_errors.append("report input/counters failed to complete")
	push_error("LEGAL_CAMPAIGN_REPORT_STALL")
	return false
