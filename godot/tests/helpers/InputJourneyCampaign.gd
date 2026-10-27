extends "res://tests/helpers/LegalProbeCampaign.gd"
# Integration observation only: actual viewport input and real frame time for
# story, item notifications and victory reports. No _finish/_advance/clock writes.
const Page=preload("res://scripts/ui/OriginalStoryPage.gd")
const Report=preload("res://scripts/ui/OriginalVictoryReport.gd")
const Notice=preload("res://scripts/ui/OriginalNotice.gd")
var input_events:Array=[]
var input_keys:Dictionary={}
var reports_enabled:=false
var next_input_ms:=0

func _process(delta:float) -> void:
	super._process(delta)
	if Time.get_ticks_msec()<next_input_ms:return
	if is_instance_valid(story_player) and is_instance_valid(story_player.native_page):
		pump_page(story_player.native_page,"story")
	elif is_instance_valid(cutscene):
		var id:=str(cutscene.get_instance_id())
		if not input_keys.has(id):
			input_keys[id]=true
			var e:=InputEventKey.new();e.keycode=KEY_ESCAPE;e.pressed=true
			get_tree().root.push_input(e,true);input_events.append({"kind":"movie_escape","frame":Engine.get_process_frames()})
	elif is_instance_valid(battle) and is_instance_valid(battle.action_panel) and battle.action_panel is Notice:
		var key:=str(battle.action_panel.get_instance_id())
		if not input_keys.has(key):
			input_keys[key]=true;release(MOUSE_BUTTON_RIGHT,"item_notice",key)
	elif reports_enabled and is_instance_valid(result_canvas):
		for node in result_canvas.get_children():
			if node is Page:pump_page(node,"victory_notice")
			elif node is Report and node.stage=="wait" and Engine.get_process_frames()>=node.wait_frame:
				var key:=str(node.get_instance_id())
				if not input_keys.has(key):
					input_keys[key]=true
					input_events.append({"kind":"report_values","values":node.displayed.duplicate(),"grade":node.grade})
					release(MOUSE_BUTTON_RIGHT,"report_wait",key)

func release(button:int,kind:String,key:String) -> void:
	next_input_ms=Time.get_ticks_msec()+20
	input_events.append({"kind":kind,"key":key,"frame":Engine.get_process_frames(),"at_ms":Time.get_ticks_msec()})
	var e:=InputEventMouseButton.new();e.position=Vector2(600,440);e.global_position=e.position;e.button_index=button;e.pressed=false
	get_tree().root.push_input(e,true)

func pump_page(page,kind:String) -> void:
	var key:String=str(page.get_instance_id())+":"+str(page.stage)
	if input_keys.has(key):return
	if page.stage=="scroll":
		input_keys[key]=true;release(MOUSE_BUTTON_LEFT,kind+"_fast_request",key)
	elif page.stage=="wait" and Engine.get_process_frames()>=page.wait_frame:
		input_keys[key]=true;acknowledged_texts+=1;release(MOUSE_BUTTON_RIGHT,kind+"_ack",key)

func drain_story() -> void:
	var deadline:=Time.get_ticks_msec()+180000
	while Time.get_ticks_msec()<deadline:
		if battle_story_queue.is_empty() and not is_instance_valid(story_player) and not is_instance_valid(cutscene) and not battle_visual_active and pending_battle_result.is_empty():return
		await get_tree().create_timer(0.01).timeout
	drain_errors.append("real-input story watchdog")
	push_error("INPUT_JOURNEY_STORY_STALL")

func complete_report() -> bool:
	reports_enabled=true
	var deadline:=Time.get_ticks_msec()+120000
	while Time.get_ticks_msec()<deadline:
		if not is_instance_valid(result_canvas) and not is_instance_valid(story_player) and not is_instance_valid(cutscene) and not is_instance_valid(battle):
			reports_enabled=false;return true
		await get_tree().create_timer(0.01).timeout
	reports_enabled=false;drain_errors.append("real-input report watchdog")
	push_error("INPUT_JOURNEY_REPORT_STALL")
	return false
