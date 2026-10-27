extends "res://tests/LegalCampaignProbe.gd"
const Guard=preload("res://tests/helpers/LegalProbeRouteGuard.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("ROUTE_GUARD "+label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	for idx in [0,8,35]:check(Guard.inspect(idx,false).can_launch,"ordinary mainline %d"%idx)
	for idx in range(36,47):check(not Guard.inspect(idx,false).can_launch,"cannot manufacture hidden/interlude %d"%idx)
	for idx in [36,39,40,43,44,46]:check(Guard.inspect(idx,false,idx).can_launch,"already launched genuine Campaign route %d"%idx)
	for idx in [35,36,40]:check(not Guard.inspect(idx,true,idx).can_launch,"ending blocks even live stale battle %d"%idx)
	for idx in [-1,47]:check(not Guard.inspect(idx,false).can_launch,"invalid index %d"%idx)
	check(not Guard.inspect(8,false,7).can_launch,"stale battle cannot establish route")
	for idx in [44,45,46]:
		var event:Dictionary={"easter":idx,"messages":[1,2]};var before:=event.duplicate(true)
		check(not Guard.inspect(8,false,-1,event).can_launch and event==before,"one-shot interlude fails closed without changing event %d"%idx)
	var c=preload("res://tests/helpers/LegalProbeCampaign.gd").new();root.add_child(c);c.setup(load("res://assets/font/hzk16.fnt"));c.qa_mode=true
	c.state.new_game(c.m2);c.state.setup_m4(c.m4);c.state.difficulty=1;c.state.configure_protagonist(103,4,100)
	var visit:Dictionary=Town.visit_resident(c.state,0)
	check(visit.get("first_deploy",false) and Town.get_flag(c.state,0)==1,"native resident prepares first question, not automatic departure")
	var receipt:Dictionary=await confirm_first_departure(c)
	check(receipt.ok and receipt.actual_viewport and Town.get_flag(c.state,0)==2,"real native YES input commits original phase2")
	check(c.mode=="deployment" and is_instance_valid(c.deployment_screen) and not is_instance_valid(c.battle),"first YES reaches actual K00 before any battle launch")
	c.queue_free();await process_frame;await process_frame
	root.get_node("Music").release_playback();OriginalUI.release_native_sfx();await create_timer(.3).timeout
	print("LEGAL_PROBE_ROUTE checks=",checks," failures=",failures)
	if failures==0:print("LEGAL_PROBE_ROUTE PASS")
	quit(1 if failures else 0)
