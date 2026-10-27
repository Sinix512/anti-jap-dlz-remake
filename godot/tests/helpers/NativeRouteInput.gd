extends RefCounted
# Actual viewport input adapter. Does not launch a battle, write state, change
# clocks/stages or acknowledge a signal directly. Synthetic callers remain
# synthetic; this adapter alone is NOT a fresh/natural route certificate.
const Page=preload("res://scripts/ui/OriginalStoryPage.gd")
const Report=preload("res://scripts/ui/OriginalVictoryReport.gd")
const Wait=preload("res://scripts/ui/OriginalReleaseWait.gd")
const Choice=preload("res://scripts/ui/OriginalChoice.gd")
var sent:Dictionary={}
var events:Array=[]
var closed:=false
var next_input_ms:=0
var choice_mode:="simulation"

func bind(campaign,requested_mode:String) -> void:
	choice_mode=requested_mode
	campaign.game_close_requested.connect(func():closed=true;events.append({"kind":"process_close_requested","frame":Engine.get_process_frames()}))

func _key(node,stage:String) -> String:
	return str(node.get_instance_id())+":"+stage

func _release(campaign,node,kind:String,stage:String,button:=MOUSE_BUTTON_RIGHT) -> bool:
	var key:=_key(node,stage)
	if sent.has(key):return false
	sent[key]=true;next_input_ms=Time.get_ticks_msec()+20
	events.append({"kind":kind,"stage":stage,"node":node.get_script().resource_path,"frame":Engine.get_process_frames(),"at_ms":Time.get_ticks_msec()})
	var event:=InputEventMouseButton.new();event.position=Vector2(600,440);event.global_position=event.position
	event.button_index=button;event.pressed=false
	campaign.get_tree().root.push_input(event,true)
	return true

func _visible_controls(node:Node) -> Array:
	var found:Array=[]
	if node.is_queued_for_deletion() or node.process_mode==Node.PROCESS_MODE_DISABLED:return found
	if node is CanvasItem and not node.is_visible_in_tree():return found
	# Visit descendants first: an END page owns its own StoryPlayer/page, not
	# Campaign.story_player. A nested wait must not be bypassed by its parent.
	for child in node.get_children():found.append_array(_visible_controls(child))
	if node is Control:found.append(node)
	return found

func pump(campaign) -> bool:
	if closed or Time.get_ticks_msec()<next_input_ms:return false
	if is_instance_valid(campaign.cutscene) and not campaign.cutscene._finished:
		var key:=_key(campaign.cutscene,"escape")
		if sent.has(key):return false
		sent[key]=true;next_input_ms=Time.get_ticks_msec()+20
		events.append({"kind":"movie_escape_down","frame":Engine.get_process_frames()})
		var event:=InputEventKey.new();event.keycode=KEY_ESCAPE;event.pressed=true
		campaign.get_tree().root.push_input(event,true);return true
	for node in _visible_controls(campaign):
		if node is Page:
			if node.stage=="scroll":return _release(campaign,node,"page_fast_request","scroll",MOUSE_BUTTON_LEFT)
			if node.stage=="wait" and Engine.get_process_frames()>=node.wait_frame:return _release(campaign,node,"page_ack","wait")
		elif node is Report:
			if node.stage=="wait" and Engine.get_process_frames()>=node.wait_frame:return _release(campaign,node,"report_ack","wait")
		elif node is Wait:
			if not node.done and Engine.get_process_frames()>=node.wait_frame:return _release(campaign,node,"release_wait_ack","wait")
		elif node is Choice and campaign.mode=="hidden_choice" and node.interactive and not node.done:
			if choice_mode not in ["simulation","fiction","cancel"]:return false
			var key:=_key(node,"choice")
			if sent.has(key):return false
			sent[key]=true;next_input_ms=Time.get_ticks_msec()+20
			var option:=1 if choice_mode=="fiction" else 0
			var point:Vector2=node.row_rect(option).get_center()
			var before:Dictionary={"campaign_index":campaign.state.campaign_index,"frozen_score":campaign.state.main_score_snapshot,"hidden_unlocked":campaign.state.hidden_unlocked}
			var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point
			campaign.get_tree().root.push_input(motion,true)
			for pressed in [true,false]:
				var click:=InputEventMouseButton.new();click.position=point;click.global_position=point;click.pressed=pressed
				click.button_index=MOUSE_BUTTON_RIGHT if choice_mode=="cancel" else MOUSE_BUTTON_LEFT
				campaign.get_tree().root.push_input(click,true)
			events.append({"kind":"hidden_choice_input","mode":choice_mode,"option":option,"point":[point.x,point.y],"input":["MOVE","RIGHT-DOWN","RIGHT-UP"] if choice_mode=="cancel" else ["MOVE","LEFT-DOWN","LEFT-UP"],"before":before,"after":{"campaign_index":campaign.state.campaign_index,"frozen_score":campaign.state.main_score_snapshot,"hidden_unlocked":campaign.state.hidden_unlocked},"frame":Engine.get_process_frames()})
			return true
	return false

func until_boundary(campaign,timeout_ms:=120000) -> Dictionary:
	var started:=Time.get_ticks_msec()
	while Time.get_ticks_msec()-started<timeout_ms:
		if closed:return {"ok":true,"boundary":"process_close","events":events.duplicate(true)}
		if not is_instance_valid(campaign.ending_layer):
			# Campaign.mode names strategic pages, not the live battle. A genuine
			# simulation launch can retain "hidden_choice" in that UI-only field.
			if is_instance_valid(campaign.battle) and campaign.current_battle_index==campaign.state.campaign_index and campaign.battle_story_queue.is_empty() and not is_instance_valid(campaign.story_player) and not is_instance_valid(campaign.cutscene) and not campaign.battle_visual_active and not campaign.battle.busy:
				return {"ok":true,"boundary":"battle","events":events.duplicate(true)}
			if not is_instance_valid(campaign.battle) and campaign.mode in ["town","deployment"]:
				return {"ok":true,"boundary":campaign.mode,"events":events.duplicate(true)}
		pump(campaign)
		await campaign.get_tree().create_timer(.01).timeout
	return {"ok":false,"boundary":"watchdog","mode":campaign.mode,"events":events.duplicate(true)}
