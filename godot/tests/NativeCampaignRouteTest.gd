extends SceneTree
# Synthetic strategic boundary fixtures, actual production viewport inputs.
# No battle is won here; these must never be supplied as fresh play evidence.
const Campaign=preload("res://tests/helpers/LegalProbeCampaign.gd")
const Driver=preload("res://tests/helpers/NativeCampaignRoute.gd")
const Town=preload("res://scripts/m4/TownRules.gd")
var checks:=0
var failures:=0
var observations:Array=[]
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("NATIVE_CAMPAIGN_ROUTE "+label)
func make_campaign():
	var c=Campaign.new();root.add_child(c)
	c.setup(load("res://assets/font/hzk16.fnt"),{"name":"李勇","face":103,"unit":4,"wuli":100,"difficulty":1});c.qa_mode=true
	return c
func dispose(c) -> void:
	c.queue_free();await process_frame;await process_frame
func run() -> void:
	var c=make_campaign()
	var driver=Driver.new();driver.bind(c,"simulation")
	var result:Dictionary=await driver.next_battle(c,60000)
	check(result.ok and result.boundary=="battle" and result.idx==0,"fresh world/resident/YES/K00 reaches actual L00")
	check(Town.get_flag(c.state,0)==2,"only original YES callback writes phase2")
	check(driver.actions.map(func(e):return e.kind).has("deployment_submit"),"actual GO input, not submit signal")
	check(c.state.campaign_completed.is_empty(),"fresh navigation does not manufacture a win")
	check(c.route_trace.filter(func(e):return e.kind=="launch").size()==1,"one launch witness")
	observations.append({"synthetic":true,"case":"fresh_navigation_only","result":result,"trace":c.route_trace.duplicate(true),"inputs":driver.actions.duplicate(true)})
	await dispose(c)
	# Freeze is explicitly synthetic. The hidden flag and actual L40 launch
	# must still come only from real END/choice/town17/resident/command input.
	c=make_campaign();c.state.campaign_index=36;c.state.main_score_snapshot=3600;c.state.score_total=3600;c.state.hidden_unlocked=true
	driver=Driver.new();driver.bind(c,"fiction");c._show_ending()
	result=await driver.next_battle(c,60000)
	check(result.ok and result.boundary=="battle" and result.idx==40,"fiction choice through town17 really launches L40")
	check(Town.get_flag(c.state,85)==3,"fiction resident advances native phase2 to3")
	check(c.state.main_score_snapshot==3600,"navigation does not change frozen score")
	check(driver.input.events.filter(func(e):return e.kind=="hidden_choice_input" and e.mode=="fiction").size()==1,"actual hidden choice input once")
	check(driver.actions.filter(func(e):return e.kind=="mission_command").size()==1,"actual fiction command input")
	check(c.state.campaign_completed.is_empty(),"synthetic fiction fixture is not a played win")
	observations.append({"synthetic":true,"case":"fiction_navigation_only","result":result,"trace":c.route_trace.duplicate(true),"inputs":driver.actions.duplicate(true)})
	await dispose(c)
	for idx in [44,45,46]:
		c=make_campaign();c.state.campaign_index=1;Town.set_flag(c.state,0,2)
		for old in range(44,idx):
			Town.set_flag(c.state,[3,4,9][old-44],1)
			# Prior wins are explicitly synthetic in this navigation fixture.
			c.state.campaign_completed.append(old)
		# No seed, forced randi result, direct launch, or victory callback.
		c._show_town(0);driver=Driver.new();driver.bind(c,"simulation")
		result=await driver.next_battle(c,60000)
		check(result.ok and result.boundary=="battle" and result.idx==idx,"natural resident RNG launches one-shot %d"%idx)
		check(Town.get_flag(c.state,91)==1 and Town.get_flag(c.state,[3,4,9][idx-44])==1,"early flag/return saved before actual interlude %d"%idx)
		check(driver.resident_attempts>=1 and driver.resident_attempts<=64,"bounded real resident visits %d"%idx)
		check(c.route_trace.filter(func(e):return e.kind=="launch" and int(e.extra.idx)==idx).size()==1,"single genuine interlude launch %d"%idx)
		check(c.state.campaign_completed==range(44,idx),"navigation adds no interlude victory %d"%idx)
		observations.append({"synthetic":true,"case":"natural_rng_entry_only_%d"%idx,"result":result,"visits":driver.resident_attempts,"trace":c.route_trace.duplicate(true),"inputs":driver.actions.duplicate(true)})
		await dispose(c)
	c=make_campaign();c.state.campaign_index=8;Town.set_flag(c.state,0,2);Town.set_flag(c.state,3,8);Town.set_flag(c.state,4,4)
	c._show_town(0);driver=Driver.new();driver.bind(c,"simulation")
	var before:Dictionary=c.state.to_dict()
	result=await driver.next_battle(c,60000)
	check(result.ok and result.boundary=="interlude_window_lost","shared counters cannot masquerade as completed interludes")
	check(result.lost==[{"idx":44,"flag":3,"value":8},{"idx":45,"flag":4,"value":4}],"records exact lost window, not a boolean reinterpretation")
	check(c.state.to_dict()==before and driver.actions.is_empty(),"lost-window stop does not mutate state or attempt a forced entry")
	check(c.route_trace.is_empty() and not is_instance_valid(c.battle),"no phantom launch/win for lost shared counters")
	observations.append({"synthetic":true,"case":"shared_counter_lost_window","result":result,"inputs":driver.actions.duplicate(true)})
	await dispose(c)
	var out=FileAccess.open("res://../out/native_campaign_route_test.json",FileAccess.WRITE)
	out.store_string(JSON.stringify({"scope":"synthetic states plus real viewport route inputs, NO played wins or natural47 certificate","checks":checks,"failures":failures,"observations":observations},"\t"));out.close()
	root.get_node("Music").release_playback();OriginalUI.release_native_sfx();await create_timer(.3).timeout
	print("NATIVE_CAMPAIGN_ROUTE checks=",checks," failures=",failures)
	if failures==0:print("NATIVE_CAMPAIGN_ROUTE PASS")
	quit(1 if failures else 0)
