extends "res://tests/LegalCampaignProbe.gd"
const SavePicker=preload("res://scripts/ui/OriginalSavePicker.gd")
const Deployment=preload("res://scripts/ui/OriginalDeployment.gd")

# Real L00-L01 new-game progression plus UI save/load/story/report input.
# NOT a 47-level/human-play certificate. Battle planning still uses the audited
# legal resolver facade; only UI waits/acks and save/load are viewport driven.
var checks:=0
var failures:=0
var viewport_events:Array=[]

func check(ok:bool,label:String) -> void:
	checks+=1
	print("JOURNEY ","PASS " if ok else "FAIL ",label)
	if not ok:failures+=1;push_error("JOURNEY "+label)

func click_at(point:Vector2) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion,true)
	viewport_events.append({"kind":"ui_motion","point":[point.x,point.y],"frame":Engine.get_process_frames(),"at_ms":Time.get_ticks_msec()})
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;root.push_input(event,true)
		viewport_events.append({"kind":"ui_left_down" if down else "ui_left_up","point":[point.x,point.y],"frame":Engine.get_process_frames(),"at_ms":Time.get_ticks_msec()})
	await process_frame;await process_frame

func run() -> void:
	var campaign=load("res://tests/helpers/InputJourneyCampaign.gd").new();root.add_child(campaign)
	campaign.setup(load("res://assets/font/hzk16.fnt"));campaign.qa_mode=true
	var gs=campaign.state
	gs.new_game(campaign.m2);gs.setup_m4(campaign.m4);gs.difficulty=1;gs.configure_protagonist(103,4,100)
	gs.data=gs.data.duplicate(true);gs.data.meta.save_prefix="dlz_qa_journey_"
	var results:Array=[]
	for idx in range(2):
		if idx==0:
			var visit:Dictionary=Town.visit_resident(gs,gs.current_town)
			var receipt:Dictionary=await confirm_first_departure(campaign) if visit.get("first_deploy",false) else {"ok":false}
			viewport_events.append({"kind":"native_first_departure_sequence","receipt":receipt})
			check(receipt.ok and Town.get_flag(gs,0)==2 and is_instance_valid(campaign.deployment_screen),"first resident uses actual native YES input to K00 and phase2")
			var command:Dictionary=Town.prepare_command(gs,gs.current_town)
			if not bool(command.get("no_choice",false)):Town.accept_command(gs,gs.current_town,command)
			var deploy:Array=gs.deployment_roster(idx).map(func(m):return int(m.pid))
			campaign._launch_level(idx,false,deploy)
		else:
			# L00's direct continuation is K00 for L01, NOT a town. Enter the
			# next battle through its actual native DOWN/UP confirmation.
			await click_at(Vector2(546,402))
		await campaign.drain_story()
		check(campaign.drain_errors.is_empty() and not campaign.battle.busy,"L%d real opening pages restore player control"%idx)
		if idx==0:
			var before:Dictionary=campaign.battle.snapshot()
			await click_at(Vector2(158,16))
			check(campaign.panel_root is SavePicker,"toolbar opens native save picker")
			await click_at(Vector2(20,170))
			check(not gs.slot_info(0).get("battle_resume",{}).is_empty() and not campaign.battle.busy,"mouse save writes isolated battle snapshot and unlocks input")
			await click_at(Vector2(186,16));await click_at(Vector2(20,170))
			for i in range(4):await process_frame
			var restored:Dictionary=campaign.battle.snapshot()
			check(restored.level==before.level and restored.scenario==before.scenario and restored.turn==before.turn and restored.rng_state==before.rng_state,"real mouse load preserves live units, trigger state, turn and RNG")
			check(not campaign.battle.busy and not is_instance_valid(campaign.panel_root),"load restores modal and player control")
		var b=campaign.battle;b.set_process(false)
		var result:Dictionary=await play_level(b,idx)
		await campaign.drain_story()
		var observation:Dictionary=capture_observation(b,result,campaign)
		results.append(observation)
		check(result.result=="victory","L%d real legal victory"%idx)
		check(observation.legality.errors.is_empty() and observation.campaign_flow.story_errors.is_empty(),"L%d no permission/story errors"%idx)
		check(await campaign.complete_report(),"L%d native victory roll, counters and fresh release finish"%idx)
		for frame in range(4):await process_frame
		if idx==0:
			var screen=campaign.deployment_screen
			check(gs.campaign_index==1 and campaign.mode=="deployment" and is_instance_valid(screen) and screen is Deployment and not screen.is_queued_for_deletion() and screen.is_visible_in_tree() and screen.level_index==1 and not screen.done,"L00 result reaches live L01 K00, not a stale town node")
			var before_page:int=screen.pages[0]
			await click_at(Vector2(266,367))
			check(int(screen.pages[0])!=before_page and campaign.deploy_pages[0]==screen.pages[0],"L01 K00 responds to real page-release input")
		else:
			var screen=campaign.strategic_screen
			check(gs.campaign_index==2 and campaign.mode=="town" and is_instance_valid(screen) and not screen.is_queued_for_deletion() and screen.is_visible_in_tree() and screen.mode=="town" and screen.enabled and not campaign._strategic_input_blocked(),"L01 result reaches live enabled town after deferred frees")
			var exit_rect:Array=screen.contract.towns[screen.town_index].buildings[4].rect
			await click_at(Vector2(exit_rect[0]+exit_rect[2]/2,exit_rect[1]+exit_rect[3]/2))
			for frame in range(4):await process_frame
			check(campaign.mode=="world" and is_instance_valid(campaign.strategic_screen) and campaign.strategic_screen.mode=="world" and campaign.strategic_screen.enabled,"post-L01 town exit accepts real input and opens world")
	var output:Dictionary={"scope":"two-level legal automated integration, not human or47 acceptance","checks":checks,"failures":failures,"observations":results,"input_events":campaign.input_events.duplicate(true),"direct_viewport_events":viewport_events.duplicate(true),"story_errors":campaign.drain_errors.duplicate()}
	var file=FileAccess.open("res://../out/input_journey.json",FileAccess.WRITE);file.store_string(JSON.stringify(output,"\t"));file.close()
	gs.delete_slot(0)
	campaign.queue_free();await process_frame;await process_frame
	var music=root.get_node_or_null("Music")
	if music!=null:music.release_playback()
	OriginalUI.release_native_sfx();await create_timer(.3).timeout
	print("ORIGINAL_JOURNEY checks=",checks," failures=",failures)
	quit(1 if failures else 0)
