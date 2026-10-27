extends "res://tests/LegalCampaignProbe.gd"
# Independent NEW game only. Development --from/checkpoints are intentionally
# unsupported. A clean partial defeat is not 47-level acceptance.
const RouteDriver=preload("res://tests/helpers/NativeCampaignRoute.gd")

func run() -> void:
	var mode:="simulation"
	var run_id:=""
	var chain_id:=""
	var output_tag:=""
	var limit:=47
	var stop_before:=-1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--route="):mode=arg.trim_prefix("--route=")
		elif arg.begins_with("--evidence-run-id="):run_id=arg.trim_prefix("--evidence-run-id=")
		elif arg.begins_with("--chain-id="):chain_id=arg.trim_prefix("--chain-id=")
		elif arg.begins_with("--output-tag="):output_tag=arg.trim_prefix("--output-tag=")
		elif arg.begins_with("--battle-limit=") and arg.trim_prefix("--battle-limit=").is_valid_int():limit=int(arg.trim_prefix("--battle-limit="))
		elif arg.begins_with("--stop-before=") and arg.trim_prefix("--stop-before=").is_valid_int():stop_before=int(arg.trim_prefix("--stop-before="))
		else:push_error("NATIVE_CAMPAIGN unsupported argument "+arg);quit(1);return
	if mode not in ["simulation","fiction"] or run_id.is_empty() or chain_id.is_empty() or output_tag.is_empty() or output_tag!=output_tag.validate_filename() or limit<1 or limit>47 or (stop_before!=-1 and (stop_before<1 or stop_before>46)):
		push_error("NATIVE_CAMPAIGN invalid route/identity/output/limit");quit(1);return
	var c=preload("res://tests/helpers/LegalProbeCampaign.gd").new();root.add_child(c)
	c.setup(load("res://assets/font/hzk16.fnt"),{"name":"李勇","face":103,"unit":4,"wuli":100,"difficulty":1});c.qa_mode=true
	c.state.story_variant=false
	c.highscore_path="res://../out/native_highscores_"+output_tag+".dat"
	var driver=RouteDriver.new();driver.bind(c,mode)
	driver.before_departure=func(idx):return prepare_supplies(c.state,idx,c)
	var initial:Dictionary=c.state.to_dict()
	var rows:Array=[]
	var unplayed_entry:Dictionary={}
	var stop:Dictionary={"ok":true,"boundary":"battle_limit"}
	for step in range(limit):
		stop=await driver.next_battle(c)
		if not stop.ok or stop.boundary!="battle":break
		var b=c.battle
		var idx:int=c.current_battle_index
		# Optional development observation, still a genuinely new game. The
		# unplayed launch is never a victory row or completion certificate.
		if idx==stop_before:
			unplayed_entry={"idx":idx,"state":c.state.to_dict(),"battle":b.snapshot(),"scope":"observed natural launch only; no battle played or won"}
			stop={"ok":true,"boundary":"observed_launch_only","idx":idx};break
		var state_before:Dictionary=c.state.to_dict()
		var launch_seq:=-1
		for event in c.route_trace:
			if event.kind=="launch" and int(event.extra.idx)==idx:launch_seq=int(event.seq)
		b.set_process(false)
		var result:Dictionary=await play_level(b,idx)
		await c.drain_story()
		var observation:Dictionary=capture_observation(b,result,c)
		var row:Dictionary={"idx":idx,"result":result,"units":observation.units,"entry_state":observation.entry_state,"mine_events":observation.mine_events,"legality":observation.legality,"campaign_flow":observation.campaign_flow,"retry_attempts":[],"state_before":state_before,"route_launch_seq":launch_seq,"provenance":{"fresh":true,"difficulty":c.state.difficulty,"campaign_path":true,"evidence_run_id":run_id,"chain_id":chain_id,"route":mode}}
		if result.result=="victory":
			row.campaign_flow["result_acknowledged"]=await c.drain_result_report()
			row.campaign_flow["settled_report"]=c._last_report.duplicate(true)
			row.campaign_flow["story_errors"]=c.drain_errors.duplicate()
			row["route_commit_seq"]=-1
			for event in c.route_trace:
				if event.kind=="commit" and int(event.extra.idx)==idx:row.route_commit_seq=int(event.seq)
		row["state_after"]=c.state.to_dict()
		rows.append(row)
		print("NATIVE_LEGAL ",mode," L%02d %s T%d"%[idx,result.result,result.turn])
		if result.result!="victory":stop={"ok":true,"boundary":"defeat","idx":idx};break
		stop={"ok":true,"boundary":"battle_limit"}
		# _report_continue owns freeing the old battle and may have already
		# launched the next one. Never clean up c.battle here.
	if rows.size()==limit and not rows.is_empty() and rows[-1].result.result=="victory":
		# Process only an already-active END/JZ. Do not start an unobserved
		# additional battle merely to turn a bounded short run into a finale.
		if is_instance_valid(c.ending_layer):stop=await driver.input.until_boundary(c)
	var envelope:Dictionary={"schema":"dlz-natural-routes-v1","scope":"fresh legal resolver combat; native viewport route/story/report input; economy remains audited resolver planning, not human all-mouse play","run_id":run_id,"chain_id":chain_id,"route":mode,"fresh":true,"creation":{"face":103,"unit":4,"wuli":100,"difficulty":1},"initial_state":initial,"rows":rows,"route_trace":c.route_trace.duplicate(true),"native_inputs":driver.input.events.duplicate(true),"navigation_inputs":driver.actions.duplicate(true),"report_inputs":c.report_inputs.duplicate(true),"final_state":c.state.to_dict(),"ending_flow":c.ending_flow_events.duplicate(),"stop":stop,"errors":c.drain_errors.duplicate(),"interlude_policy":{"at_mainline":driver.interlude_at,"max_visits":driver.interlude_budget,"actual_visits":driver.resident_attempts,"rng_seed_override":false}}
	var path:="res://../out/native_campaign_"+output_tag+".json"
	envelope["unplayed_entry"]=unplayed_entry
	var file=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(envelope,"\t"));file.close()
	var clean:bool=stop.ok and c.drain_errors.is_empty()
	c.queue_free();await process_frame;await process_frame
	root.get_node("Music").release_playback();OriginalUI.release_native_sfx();await create_timer(.3).timeout
	print("NATIVE_CAMPAIGN completed=",rows.size()," clean=",clean," boundary=",stop.boundary," output=",path)
	quit(0 if clean else 1)
