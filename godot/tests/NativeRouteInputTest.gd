extends SceneTree
# Real-time/viewport fixture of route input, NOT played victories or fresh47.
const Campaign=preload("res://scripts/m4/Campaign.gd")
const Driver=preload("res://tests/helpers/NativeRouteInput.gd")
const Town=preload("res://scripts/m4/TownRules.gd")
var checks:=0
var failures:=0
var observations:Array=[]
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("NATIVE_ROUTE_INPUT "+label)
func run() -> void:
	for spec in [{"score":2799,"choice":"simulation","boundary":"process_close"},{"score":3600,"choice":"simulation","boundary":"battle"},{"score":3600,"choice":"fiction","boundary":"town"},{"score":2800,"choice":"cancel","boundary":"process_close"}]:
		var c=Campaign.new();root.add_child(c);c.setup(load("res://assets/font/hzk16.fnt"));c.qa_mode=true
		c.state.new_game(c.m2);c.state.setup_m4(c.m4);c.state.configure_protagonist(103,4,100);c.state.difficulty=1
		# Explicit synthetic L35-after-settlement state. Never put this in a
		# campaign acceptance file or claim that its high score was earned.
		c.state.campaign_index=36;c.state.main_score_snapshot=spec.score;c.state.score_total=spec.score
		c.state.hidden_unlocked=spec.score>=2800
		var driver=Driver.new();driver.bind(c,spec.choice)
		c._show_ending()
		var result:Dictionary=await driver.until_boundary(c,60000)
		check(result.ok and result.boundary==spec.boundary,"actual input reaches expected boundary "+spec.choice+str(spec.score))
		check(c.ending_flow_events.slice(0,2)==["END","chapter35"],"complete END before chapter35")
		var choices:Array=driver.events.filter(func(e):return e.kind=="hidden_choice_input")
		check(choices.size()==(0 if spec.score<2800 else 1),"hidden selection only at qualifying notice")
		check(c.state.main_score_snapshot==spec.score,"no input changes frozen score")
		if spec.choice=="simulation" and spec.score>=2800:
			check(is_instance_valid(c.battle) and c.current_battle_index==36 and c.state.campaign_index==36,"simulation actual native launch is L36")
			check(Town.get_flag(c.state,85)==0,"simulation does not write fiction flag")
		elif spec.choice=="fiction":
			check(not is_instance_valid(c.battle) and c.state.campaign_index==40 and c.state.current_town==17,"fiction reaches town17 before battle40")
			check(Town.get_flag(c.state,85)==2,"fiction flag only after actual click")
		else:
			check(driver.events.filter(func(e):return e.kind=="process_close_requested").size()==1,"two actual JZ waits request process close once")
		check(c.state.campaign_completed.is_empty(),"fixture never manufactures a played win")
		observations.append({"synthetic":true,"spec":spec,"flow":c.ending_flow_events.duplicate(),"result":result})
		c.queue_free();await process_frame;await process_frame
	var out=FileAccess.open("res://../out/native_route_input.json",FileAccess.WRITE)
	out.store_string(JSON.stringify({"scope":"synthetic production UI and actual viewport input only; NOT played wins or fresh acceptance","checks":checks,"failures":failures,"observations":observations},"\t"));out.close()
	root.get_node("Music").release_playback();OriginalUI.release_native_sfx();await create_timer(.3).timeout
	print("NATIVE_ROUTE_INPUT checks=",checks," failures=",failures)
	if failures==0:print("NATIVE_ROUTE_INPUT PASS")
	quit(1 if failures else 0)
