extends SceneTree
const State=preload("res://scripts/m2/GameState.gd")
const Builder=preload("res://scripts/m4/LevelBuilder.gd")
const Town=preload("res://scripts/m4/TownRules.gd")
const Forecast=preload("res://tests/helpers/TacticalForecast.gd")
const Rules=preload("res://scripts/battle/CombatRules.gd")
const Planner=preload("res://tests/helpers/TacticalPlanner.gd")
const CandidateSet=preload("res://tests/helpers/ForecastCandidateSet.gd")
const RouteGuard=preload("res://tests/helpers/LegalProbeRouteGuard.gd")
const FirstConfirm=preload("res://scripts/ui/OriginalConfirm.gd")
const Ambush=preload("res://tests/helpers/AmbushPlanner.gd")
var focus_enemy_slot := 40
var bridge_hold:=3
var checkpoint_read_tag:=""
var checkpoint_save_tag:=""

func tactic_enabled(flag:String) -> bool:
	var args:=OS.get_cmdline_user_args()
	return args.has(flag) or (not args.has("--baseline-tactics") and flag in ["--stone-ambush","--stone-cache","--north-lure","--cache-book","--bridge-mines","--bridge-grenades"])

func _initialize() -> void:call_deferred("run")
func run() -> void:
	var m2: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/m2.json"))
	var m4: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json"))
	var campaign=load("res://tests/helpers/LegalProbeCampaign.gd").new();root.add_child(campaign)
	campaign.setup(load("res://assets/font/hzk16.fnt"));campaign.qa_mode=true
	var gs=campaign.state;gs.new_game(m2);gs.setup_m4(m4)
	gs.difficulty=1 # Explicit normal choice: never inherit the player's saved config.
	gs.configure_protagonist(103,4,100) # A legal original character-creation choice, not a level/stat boost.
	var results: Array=[]
	var direct:=false
	var first_level:=-1
	var level_count:=47
	var retry_limit:=0
	var trial_tag:=""
	var evidence_run_id:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--checkpoint-tag="):checkpoint_read_tag="_"+arg.trim_prefix("--checkpoint-tag=").validate_filename()
		if arg.begins_with("--save-checkpoint-tag="):checkpoint_save_tag="_"+arg.trim_prefix("--save-checkpoint-tag=").validate_filename()
		if arg.begins_with("--bridge-hold="):bridge_hold=clampi(int(arg.trim_prefix("--bridge-hold=")),0,8)
		if arg.begins_with("--from="):first_level=int(arg.trim_prefix("--from="))
		if arg.begins_with("--levels="):level_count=int(arg.trim_prefix("--levels="))
		if arg.begins_with("--retries="):retry_limit=maxi(0,int(arg.trim_prefix("--retries=")))
		if arg.begins_with("--tag="):trial_tag="_"+arg.trim_prefix("--tag=").validate_filename()
		if arg.begins_with("--evidence-run-id="):evidence_run_id=arg.trim_prefix("--evidence-run-id=")
	# Development iterations may resume an actual previously played strategic
	# checkpoint. The acceptance runner supplies no --from: it ALWAYS starts new.
	if first_level>=0:
		var path:="res://../out/legal_checkpoint%s_L%02d.json"%[checkpoint_read_tag,first_level]
		if not FileAccess.file_exists(path):push_error("Missing played checkpoint "+path);quit(1);return
		var checkpoint:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
		if not gs.from_dict(checkpoint.state):push_error("Invalid played checkpoint");quit(1);return
		direct=bool(checkpoint.direct)
		results=checkpoint.history
		print("LEGAL_DEV_RESUME L",first_level," prior=",results.size()," (not a fresh-chain acceptance run)")
	for step in range(level_count-results.size()):
		var idx:int=gs.campaign_index
		var launched_auto:bool=is_instance_valid(campaign.battle) and campaign.current_battle_index==idx
		var route:Dictionary=RouteGuard.inspect(idx,is_instance_valid(campaign.ending_layer),campaign.current_battle_index if is_instance_valid(campaign.battle) else -1)
		if not route.can_launch:
			print("LEGAL_ROUTE_STOP ",route)
			if not results.is_empty():results[-1].campaign_flow["route_stop"]=route
			break
		if first_level<0 or not checkpoint_save_tag.is_empty():
			var checkpoint_file=FileAccess.open("res://../out/legal_checkpoint%s_L%02d.json"%[checkpoint_save_tag,idx],FileAccess.WRITE)
			checkpoint_file.store_string(JSON.stringify({"state":gs.to_dict(),"direct":direct,"history":results},"\t"));checkpoint_file.close()
		var visits: Array=[]
		var resident_route_blocked:=false
		for v in range(0 if direct or launched_auto else 1):
			var visit: Dictionary=Town.visit_resident(gs,gs.current_town);visits.append(visit)
			var resident_route:Dictionary=RouteGuard.inspect(idx,false,-1,visit)
			if visit.has("easter") and not resident_route.can_launch:
				print("LEGAL_ROUTE_STOP ",resident_route)
				if not results.is_empty():results[-1].campaign_flow["route_stop"]=resident_route
				resident_route_blocked=true;break
			if bool(visit.get("first_deploy",false)):
				visit["first_departure_input"]=await confirm_first_departure(campaign)
				if not visit.first_departure_input.ok:resident_route_blocked=true
				break
		if resident_route_blocked:break
		var command: Dictionary={"no_choice":true} if direct or launched_auto else Town.prepare_command(gs,gs.current_town)
		if not bool(command.get("no_choice",false)):Town.accept_command(gs,gs.current_town,command)
		var economy:Array=prepare_supplies(gs,idx,campaign) if not direct and not launched_auto else []
		# A real deployment screen makes a fresh selection for each new battle.
		# Passing [] directly to _launch_level instead reuses the previous UI list.
		var deploy_pids:Array=[-100,6,5,1,2,3,4] if idx==6 else gs.deployment_roster(idx).map(func(m):return int(m.pid))
		if launched_auto:deploy_pids=campaign.current_deploy_pids.duplicate()
		else:campaign._launch_level(idx,false,deploy_pids)
		await campaign.drain_story()
		var b=campaign.battle
		b.set_process(false)
		var result:Dictionary={}
		var retry_attempts:Array=[]
		for attempt in range(retry_limit+1):
			result=await play_level(b,idx)
			await campaign.drain_story()
			if result.result=="victory" or attempt>=retry_limit:break
			var previous:Dictionary=capture_observation(b,result,campaign)
			retry_attempts.append(previous)
			print("LEGAL_RETRY L%02d attempt=%d result=%s T%d"%[idx,attempt+1,result.result,result.turn])
			if not await retry_with_original_dialog(campaign):break
			await campaign.drain_story()
			b=campaign.battle;b.set_process(false)
		var observation:Dictionary=capture_observation(b,result,campaign)
		var units:Array=observation.units
		var record: Dictionary={"idx":idx,"result":result,"units":units,"visits":visits,"command":command,"economy":economy,"money":gs.money,"deployment":deploy_pids,"provenance":{"fresh":first_level<0,"difficulty":gs.difficulty,"campaign_path":true,"evidence_run_id":evidence_run_id,"player_policy":{"stone_ambush":tactic_enabled("--stone-ambush"),"stone_cache":tactic_enabled("--stone-cache"),"north_lure":tactic_enabled("--north-lure"),"cache_book":tactic_enabled("--cache-book"),"bridge_mines":tactic_enabled("--bridge-mines"),"bridge_grenades":tactic_enabled("--bridge-grenades"),"bridge_hold":bridge_hold}},"legality":observation.legality,"campaign_flow":observation.campaign_flow,"retry_attempts":retry_attempts,"entry_state":observation.entry_state,"mine_events":observation.mine_events}
		results.append(record)
		print("LEGAL L%02d %s turn=%d | %s | hero=%s"%[idx,result.result,result.turn,result.message,str(units.filter(func(unit):return int(unit.slot)==0))])
		if result.result=="victory":
			direct=bool(gs.m4_level(idx).get("victory_phase",{}).get("direct_next_battle",false))
			var acknowledged:bool=await campaign.drain_result_report()
			record.campaign_flow["result_acknowledged"]=acknowledged
			record.campaign_flow["story_errors"]=campaign.drain_errors.duplicate()
		if is_instance_valid(b):b.queue_free()
		if campaign.battle==b:campaign.battle=null
		await process_frame
		if result.result!="victory":break
	campaign.queue_free();await process_frame
	await create_timer(0.5).timeout
	var output:="res://../out/legal_campaign_probe.json" if first_level<0 else "res://../out/legal_campaign_trial_L%02d%s.json"%[first_level,trial_tag]
	var file=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(results,"\t"));file.close()
	print("LEGAL_PROBE completed=",results.size()," (bot observation; not human play acceptance) output=",output)
	quit()

func confirm_first_departure(campaign) -> Dictionary:
	# Original town0 YES callback owns thephase1->2 write. Do not silently
	# bypass the question or set a story flag from the player-planning probe.
	campaign._show_first_departure()
	if not is_instance_valid(campaign.panel_root) or not (campaign.panel_root is FirstConfirm):
		push_error("LEGAL_FIRST_DEPARTURE missing original confirmation")
		return {"ok":false,"reason":"missing original confirmation"}
	var point:Vector2=campaign.panel_root.origin+Vector2(64,44)
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion,true)
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;root.push_input(event,true)
	await process_frame;await process_frame
	var ok:bool=Town.get_flag(campaign.state,0)==2 and campaign.mode=="deployment" and is_instance_valid(campaign.deployment_screen)
	if not ok:push_error("LEGAL_FIRST_DEPARTURE real input failed")
	return {"ok":ok,"actual_viewport":true,"input":["MOVE","LEFT-DOWN","LEFT-UP"],"point":[point.x,point.y],"resident_phase":Town.get_flag(campaign.state,0)}

func retry_with_original_dialog(campaign) -> bool:
	# Actual native roll -> fresh release -> record-tail -> yes-DOWN.
	# No clock/stage assignment; remains valid when there is no auto notice.
	var fast_requested:=false
	var acknowledged:=false
	for frame in range(600):
		if not is_instance_valid(campaign.result_canvas):break
		var dialog=campaign.result_canvas.get_child(0)
		if dialog.stage=="notice":
			var notice=dialog.notice
			if notice.stage=="scroll" and not fast_requested:
				var up:=InputEventMouseButton.new();up.button_index=MOUSE_BUTTON_LEFT;up.pressed=false;up.position=Vector2(364,244);root.push_input(up,true);fast_requested=true
			elif notice.stage=="wait" and Engine.get_process_frames()>=notice.wait_frame and not acknowledged:
				var up:=InputEventMouseButton.new();up.button_index=MOUSE_BUTTON_RIGHT;up.pressed=false;up.position=Vector2(364,244);root.push_input(up,true);acknowledged=true
		elif dialog.stage=="retry":
			var motion:=InputEventMouseMotion.new();motion.position=Vector2(364,244);motion.global_position=motion.position;root.push_input(motion,true)
			for pressed in [true,false]:
				var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=pressed;click.position=Vector2(364,244);click.global_position=click.position;root.push_input(click,true)
			await process_frame
			return true
		await process_frame
	campaign.drain_errors.append("native retry notification/input stalled")
	push_error("LEGAL_RETRY_INPUT_STALL")
	return false

func capture_observation(b,result:Dictionary,campaign) -> Dictionary:
	result["condition"] = b.last_result_condition
	var units:Array=[]
	for unit in b.units:units.append({"slot":unit.slot,"name":unit.unit_name,"alive":unit.alive,"hp":unit.hp,"level":unit.data.get("level",0),"xp":unit.data.get("xp",0),"xy":[unit.x,unit.y],"items":unit.item_slots.duplicate(),"mines":unit.mine_slots.duplicate(),"attacks":unit.attack_count,"skills":unit.skill_counts.duplicate()})
	return {"idx":int(b.level.index),"result":result,"units":units,"entry_state":b.get_meta("probe_entry",{}),
		"mine_events":b.legal_mine_events.duplicate(true),"legality":{"errors":b.legal_errors.duplicate(true),"moves":b.legal_move_log.duplicate(true),"actions":b.legal_action_log.duplicate(true)},
		"campaign_flow":{"report":campaign._last_report.duplicate(true),"story_errors":campaign.drain_errors.duplicate(),"texts_acknowledged":campaign.acknowledged_texts,"movies_acknowledged":campaign.acknowledged_movies}}

func play_level(b,idx: int) -> Dictionary:
	b.set_meta("probe_entry",b.snapshot()) # Read-only entry evidence for fresh/resume reproducibility.
	if idx==1:return await play_rescue(b)
	if idx==2:return await play_zhao(b)
	if idx==3:return await play_li(b)
	if idx==4:return await play_gao(b)
	if idx==5:return await play_li_village(b)
	if idx==6:return await play_xiao(b)
	if idx==7:return await play_bridge(b)
	if idx!=0:return await play_forecast_group(b)
	# Original L00 briefing teaches waiting for the patrol. This tactic uses only
	# legal waits/moves; no teleports, stat edits, forced triggers, or enemy removal.
	b.fast_sim=true
	var tactic:=0
	var goals:=[Vector2i(7,21),Vector2i(7,17),Vector2i(11,8),Vector2i(17,0)]
	while not b.finished_flag and b.turn<=40:
		var hero=b.unit_by_slot(0)
		if hero==null:break
		if b.turn>=6:
			var goal:Vector2i=goals[tactic]
			await move_legally(b,hero,goal)
			if Vector2i(hero.x,hero.y)==goal and tactic<goals.size()-1:tactic+=1
			if hero.alive and hero.hp < hero.max_hp*3/4 and not b.finished_flag:
				await use_support(b,hero,0)
			await wait_legally(b,hero)
		print("LEGAL_TRACE T%d hero=(%d,%d) hp=%d/%d acted=%s enemies=%d"%[b.turn,hero.x,hero.y,hero.hp,hero.max_hp,hero.acted,b._alive_count(b.enemy_units)])
		if b.turn>=10:
			for e in b.enemy_units:
				if e.alive:print(" ENEMY",e.slot," xy=",e.x,",",e.y," hp=",e.hp)
		if not b.finished_flag:await b._on_end_turn()
	b.fast_sim=false
	return {"result":b.last_result,"message":b.last_message,"turn":b.turn,"stats":b.stats.duplicate(true),"finished":b.finished_flag,"phase":b.phase,"result_trigger":b.last_result_trigger.duplicate(true)}

func play_rescue(b) -> Dictionary:
	b.fast_sim=true
	var goals:=[Vector2i(22,22),Vector2i(14,16),Vector2i(8,9),Vector2i(3,9),Vector2i(3,7)]
	var stage:=0
	while not b.finished_flag and b.turn<=50:
		var actors:Array=b.player_units.duplicate()
		actors.sort_custom(func(a,c):return a.slot<c.slot)
		for u in actors:
			if not u.alive or u.acted or not u.control:continue
			if u.slot==0 and b.unit_by_slot(45)!=null:
				await fight_rescue_unit(b,u)
			elif u.slot==0 and int(b.scenario._global_value("0x583f18"))==0:
				if b.chests[0].get("opened",false):stage=maxi(stage,1)
				var goal:Vector2i=goals[stage]
				var guard=b.unit_by_slot(40)
				if guard==null or not b._in_attack_range(u,guard) or b.unit_by_slot(1).hp==1:await move_legally(b,u,goal)
				if Vector2i(u.x,u.y)==goal and stage<goals.size()-1:stage+=1
				var captive=b.unit_by_slot(1)
				if captive!=null and captive.hp<captive.max_hp/2 and b._skill_targets(u,b.data.skills[0]).has(Vector2i(captive.x,captive.y)):
					await use_support(b,u,0,captive)
				elif u.alive and u.hp<u.max_hp*3/5 and not b.finished_flag:
					await use_support(b,u,0)
				elif u.alive and u.morale<55 and not b.finished_flag:
					await use_support(b,u,1)
				elif guard!=null and b._in_attack_range(u,guard) and not b.finished_flag:
					await b._perform_attack(u,guard)
				elif not b.attack_targets(u).is_empty() and not b.finished_flag:
					await b._perform_attack(u,b._bot_pick_target(u,b.attack_targets(u)))
				await wait_legally(b,u)
			else:await fight_rescue_unit(b,u)
		var h=b.unit_by_slot(0)
		if h!=null:print("RESCUE_TRACE T%d xy=(%d,%d) hp=%d morale=%d"%[b.turn,h.x,h.y,h.hp,h.morale])
		if not b.finished_flag:await b._on_end_turn()
	b.fast_sim=false
	return {"result":b.last_result,"message":b.last_message,"turn":b.turn,"stats":b.stats.duplicate(true),"finished":b.finished_flag,"phase":b.phase,"result_trigger":b.last_result_trigger.duplicate(true)}

func use_support(b,u,sid:int,target=null) -> void:
	if b._skill_count(u,sid)<=0:return
	b.selected=u;b.active_skill_id=sid;b.active_skill=b.data.skills[sid]
	await b._execute_skill_at(Vector2i(u.x,u.y) if target==null else Vector2i(target.x,target.y))

func fight_rescue_unit(b,u) -> void:
	if b._skill_count(u,0)>0:
		var injured=null
		for ally in b.player_units:
			if ally.alive and ally!=u and ally.hp<ally.max_hp/2 and b._skill_targets(u,b.data.skills[0]).has(Vector2i(ally.x,ally.y)):
				if injured==null or ally.hp<injured.hp:injured=ally
		if injured!=null:
			await use_support(b,u,0,injured);return
		if u.hp<u.max_hp*3/5:
			await use_support(b,u,0);return
	if b._skill_count(u,1)>0 and u.morale<55:
		await use_support(b,u,1);return
	if u.slot==1 and u.hp<u.max_hp/3:
		await b._bot_retreat(u);return
	var original:=Vector2i(u.x,u.y)
	var best:=original
	var victim=null
	var value:=-999999
	for station in legal_stations(b,u):
		u.x=station.x;u.y=station.y
		var danger:=0
		for enemy in b.enemy_units:
			if not enemy.alive:continue
			var distance:int=absi(enemy.x-u.x)+absi(enemy.y-u.y)
			if b._in_attack_range(enemy,u):danger+=b.compute_damage(enemy,u)
			elif distance<=enemy.move+2:danger+=b.compute_damage(enemy,u)/2
		for target in b.attack_targets(u).values():
			var damage:int=b.compute_damage(u,target)
			var score:int=damage+200*(1 if damage>=target.hp else 0)-danger*5-absi(station.x-original.x)-absi(station.y-original.y)
			if score>value:value=score;best=station;victim=target
		u.x=original.x;u.y=original.y
	if victim!=null:
		if best!=original:await move_legally(b,u,best)
		if b._in_attack_range(u,victim):await b._perform_attack(u,victim)
		else:await wait_legally(b,u)
	else:
		var nearest=b._nearest_side(u,"enemy")
		if nearest!=null:await move_legally(b,u,Vector2i(nearest.x,nearest.y))
		await wait_legally(b,u)


# Player-only tactical planning. It may inspect the visible battlefield, but
# every committed move/attack/skill/item still goes through the legal resolver.
func threats(b,u) -> Array:
	var result:Array=[]
	for enemy in b.enemy_units:
		if not enemy.alive:continue
		var cells:Dictionary={}
		var stations:Array=[] if int(enemy.behavior)==0 else b.compute_reachable(enemy).keys()
		stations.append(Vector2i(enemy.x,enemy.y))
		var matrix:Array=b.data.select_ranges.get(str(enemy.select),[])
		for station in stations:
			for y in range(-4,5):
				for x in range(-4,5):
					if int(matrix[y+4][x+4])==1:cells[station+Vector2i(x,y)]=true
		result.append({"enemy":enemy,"cells":cells})
	return result

func danger_at(b,u,tile:Vector2i,fields:Array,killed:Array=[]) -> int:
	var old:=Vector2i(u.x,u.y);u.x=tile.x;u.y=tile.y
	var danger:=0
	for field in fields:
		if field.enemy.alive and not killed.has(field.enemy) and field.cells.has(tile):danger+=b.compute_damage(field.enemy,u)
	u.x=old.x;u.y=old.y
	return danger

func safe_station(b,u,stations:Array,fields:Array) -> Vector2i:
	var best:=Vector2i(u.x,u.y)
	var value:=999999
	for station in stations:
		var danger:=danger_at(b,u,station,fields)
		var score:int=danger*20+absi(station.x-u.x)+absi(station.y-u.y)
		if score<value:value=score;best=station
	return best

func fight_unit(b,u) -> void:
	var original:=Vector2i(u.x,u.y)
	var stations:Array=legal_stations(b,u)
	var fields:Array=threats(b,u)
	if int(b.level.index)>=3 and u.hp<u.max_hp*3/5:
		for raw in u.item_slots:
			var iid:=int(raw)-1
			if iid>=0 and iid<21 and int(b.data.items[str(iid)].get("para1",0))>=u.max_hp-u.hp:
				var safe:=safe_station(b,u,stations,fields)
				if safe!=original:await move_legally(b,u,safe)
				b.selected=u;b.active_item_id=iid;await b._execute_item_at(Vector2i(u.x,u.y));return
	# Move out of enemy fire BEFORE spending the action on self support.
	if (u.hp<u.max_hp*3/5 and b._skill_count(u,0)>0) or (u.morale<55 and b._skill_count(u,1)>0):
		var safe:=safe_station(b,u,stations,fields)
		if safe!=original:await move_legally(b,u,safe)
		await use_support(b,u,0 if u.hp<u.max_hp*3/5 and b._skill_count(u,0)>0 else 1);return
	# Original carried foods are finite; never create stock to rescue the bot.
	if u.hp<u.max_hp/2:
		for raw in u.item_slots:
			var iid:=int(raw)-1
			if iid>=0 and iid<21 and int(b.data.items[str(iid)].get("para1",0))>0:
				var safe:=safe_station(b,u,stations,fields)
				if safe!=original:await move_legally(b,u,safe)
				b.selected=u;b.active_item_id=iid;await b._execute_item_at(Vector2i(u.x,u.y));return
	if u.hp<u.max_hp*2/5 and b._skill_count(u,0)<=0:
		var safe:=safe_station(b,u,stations,fields)
		if safe!=original:await move_legally(b,u,safe)
		await wait_legally(b,u);return
	var safe:=safe_station(b,u,stations,fields)
	var choice:Dictionary={"kind":"wait","station":safe}
	var value:int=-danger_at(b,u,safe,fields)*2-200
	if int(b.level.index)==1:choice={};value=-999999
	var can_attack:=false
	for station in stations:
		u.x=station.x;u.y=station.y
		var actions:Array=[]
		for target in b.attack_targets(u).values():actions.append({"kind":"attack","target":target,"tile":Vector2i(target.x,target.y)})
		for sid in [3,4,5,13,14,15]:
			if b._skill_count(u,sid)<=0:continue
			var mask:Dictionary=b._skill_targets(u,b.data.skills[sid])
			if int(b.level.index)>=4:
				for tile in mask:actions.append({"kind":"skill","skill":sid,"tile":tile})
			else:
				for target in b.enemy_units:
					if target.alive and mask.has(Vector2i(target.x,target.y)):actions.append({"kind":"skill","skill":sid,"target":target,"tile":Vector2i(target.x,target.y)})
		for raw in u.item_slots:
			var iid:=int(raw)-1
			if iid<41 or iid>56:continue
			var it:Dictionary=b.data.items[str(iid)]
			var mask:Dictionary=b._item_targets(u,it,"throw")
			if int(b.level.index)>=4:
				for tile in mask:actions.append({"kind":"item","item":iid,"tile":tile})
			else:
				for target in b.enemy_units:
					if target.alive and mask.has(Vector2i(target.x,target.y)):actions.append({"kind":"item","item":iid,"target":target,"tile":Vector2i(target.x,target.y)})
		if int(b.level.index)<4 and not actions.is_empty():can_attack=true
		for action in actions:
			if int(b.level.index)>=4:
				var estimate:Dictionary=area_estimate(b,u,action)
				if estimate.value<=0:continue
				can_attack=true
				var risk:=danger_at(b,u,station,fields,estimate.killed)
				var candidate:int=estimate.value-risk/2-absi(station.x-original.x)-absi(station.y-original.y)
				if risk>=u.hp:candidate-=1500
				if candidate>value:value=candidate;choice=action.duplicate();choice.station=station
				continue
			var killed:Array=[]
			var damage:int=b.compute_damage(u,action.target)
			var probability:=100
			if action.kind=="skill":
				var sid:int=action.skill
				damage=Rules.skill_effect(int(u.data.zhili),int(b.data.skills[sid].para1),b._skill_count(u,sid))
				if sid in [3,4,5]:damage=damage*(100+int(b.data.terrain_modifiers[b._terrain_at(action.tile)][0 if sid==3 else 1]))/100
				if sid!=15:probability=clampi(30+2*(int(u.data.zhili)-int(action.target.data.zhili)),0,100)
			var area_value:=0
			if action.kind=="item":
				var it:Dictionary=b.data.items[str(action.item)]
				for cell in b._apply_tiles(action.tile,int(it.apply_fw),u.direction):
					var target=b._unit_at(cell.tile)
					if target==null or b.same_faction(target,u):continue
					var hp_loss:int=mini(int(target.hp),int(it.para1)*int(cell.pct)/100)
					var morale_loss:int=mini(int(target.morale),int(it.para2)*int(cell.pct)/100)
					area_value+=hp_loss+morale_loss/2
					if hp_loss>0 and (hp_loss>=target.hp or morale_loss>=target.morale):killed.append(target)
				damage=area_value
			if action.kind!="item" and damage>=action.target.hp:killed.append(action.target)
			var danger:=danger_at(b,u,station,fields,killed if probability==100 else [])
			var score:int=((damage if action.kind=="item" else mini(damage,int(action.target.hp)))+150*killed.size())*probability/100-danger/2-absi(station.x-original.x)-absi(station.y-original.y)
			if danger>=u.hp:score-=1500
			if score>value:value=score;choice=action.duplicate();choice.station=station
		u.x=original.x;u.y=original.y
	if not can_attack:choice={};value=-999999
	# Save a wounded teammate when it can be done from a safe legal station.
	if b._skill_count(u,0)>0:
		for ally in b.player_units:
			if not ally.alive or ally==u or ally.hp>=ally.max_hp/2:continue
			for station in stations:
				u.x=station.x;u.y=station.y
				var valid:bool=b._skill_targets(u,b.data.skills[0]).has(Vector2i(ally.x,ally.y))
				u.x=original.x;u.y=original.y
				if not valid:continue
				var score:int=200-danger_at(b,u,station,fields)*3
				if score>value:value=score;choice={"kind":"skill","skill":0,"target":ally,"tile":Vector2i(ally.x,ally.y),"station":station}
	if not choice.is_empty():
		if choice.station!=original:await move_legally(b,u,choice.station)
		if not u.alive or u.acted or b.finished_flag:return
		if choice.kind=="attack" and b._in_attack_range(u,choice.target):await b._perform_attack(u,choice.target)
		elif choice.kind=="skill":
			b.selected=u;b.active_skill_id=int(choice.skill);b.active_skill=b.data.skills[int(choice.skill)];await b._execute_skill_at(choice.tile)
		elif choice.kind=="item":
			b.selected=u;b.active_item_id=int(choice.item);await b._execute_item_at(choice.tile)
		else:await wait_legally(b,u)
	else:
		var nearest=b.unit_by_slot(focus_enemy_slot) if int(b.level.index)==4 else b._nearest_side(u,"enemy")
		if nearest!=null and int(b.level.index)<3 and u.hp>=u.max_hp*4/5:
			await move_legally(b,u,Vector2i(nearest.x,nearest.y))
		elif nearest!=null:
			var route:Array=b._astar(original,Vector2i(nearest.x,nearest.y),u,true)
			var best:=original
			var remaining:=route.size()+danger_at(b,u,original,fields)/2
			for index in range(route.size()):
				var point:Vector2i=route[index]
				if not stations.has(point):continue
				var score:int=route.size()-index-1+danger_at(b,u,point,fields)/2
				if score<remaining:remaining=score;best=point
			if best!=original:await move_legally(b,u,best)
		await wait_legally(b,u)

# Predict all affected cells, including an empty/friendly landing cell. This is
# only a player planner: committing the action still uses the unchanged resolver.
func area_estimate(b,u,action:Dictionary) -> Dictionary:
	return forecast_candidate_set().area_estimate(b,u,action)

func play_general(b) -> Dictionary:
	b.fast_sim=true
	while not b.finished_flag and b.turn<=120:
		if OS.get_cmdline_user_args().has("--trace"):
			for unit in b.units:
				if unit.alive:print("TACTIC T",b.turn," slot",unit.slot," xy",unit.x,",",unit.y," hp",unit.hp," morale",unit.morale," items",unit.item_slots)
		var actors:Array=b.player_units.duplicate()
		actors.sort_custom(func(a,c):return a.slot<c.slot)
		for u in actors:
			if b.finished_flag:break
			if u.alive and u.control and not u.acted:
				if int(b.level.index)==4 and b.turn==1 and u.slot==0 and u.mine_slots.has(1):
					await move_legally(b,u,Vector2i(7,20))
					b.selected=u;b.mine_kind=0
					b._place_mine(Vector2i(6,19))
					if u.acted:continue
				var hero=b.unit_by_slot(0)
				if int(b.level.index)==2 and u.slot in [2,3] and hero!=null and b.turn<5:
					await move_legally(b,u,Vector2i(18,6) if u.slot==2 else Vector2i(19,7));await wait_legally(b,u)
				else:await fight_unit(b,u)
		if not b.finished_flag:await b._on_end_turn()
	b.fast_sim=false
	return {"result":b.last_result,"message":b.last_message,"turn":b.turn,"stats":b.stats.duplicate(true),"finished":b.finished_flag,"phase":b.phase,"result_trigger":b.last_result_trigger.duplicate(true)}

# L02: use the northern safe road and the southern recovery building to join
# the split deployment, rather than feeding two isolated pairs into ten enemies.
func play_zhao(b) -> Dictionary:
	b.fast_sim=true
	var stages:Dictionary={0:0,1:0,2:0,3:0}
	var routes:Dictionary={
		0:[Vector2i(3,17),Vector2i(2,14)],
		1:[Vector2i(3,18),Vector2i(2,15)],
		2:[Vector2i(14,3),Vector2i(10,3),Vector2i(10,0),Vector2i(0,1),Vector2i(0,6),Vector2i(1,11),Vector2i(3,13)],
		3:[Vector2i(15,3),Vector2i(10,4),Vector2i(9,0),Vector2i(1,1),Vector2i(0,7),Vector2i(2,11),Vector2i(3,14)]}
	while not b.finished_flag and b.turn<=30:
		for u in b.player_units:
			if not u.alive or not u.control or u.acted:continue
			if u.slot in [2,3]:
				if b.turn<15:
					await move_legally(b,u,Vector2i(18,6) if u.slot==2 else Vector2i(19,7));await wait_legally(b,u)
				else:await fight_unit(b,u)
				continue
			var route:Array=routes.get(u.slot,[])
			var stage:int=stages.get(u.slot,0)
			if stage<route.size():
				await move_legally(b,u,route[stage])
				if Vector2i(u.x,u.y)==route[stage]:stages[u.slot]=stage+1
				if not u.alive or u.acted or b.finished_flag:continue
				if u.hp<u.max_hp*3/4 and b._skill_count(u,0)>0:await use_support(b,u,0)
				elif not b.attack_targets(u).is_empty():await b._perform_attack(u,b._bot_pick_target(u,b.attack_targets(u)))
				else:await wait_legally(b,u)
			elif u.slot==0 and b.turn<13:
				var injured=null
				for ally in b.player_units:
					if ally.alive and ally.hp<ally.max_hp*4/5 and b._skill_targets(u,b.data.skills[0]).has(Vector2i(ally.x,ally.y)):
						if injured==null or ally.hp<injured.hp:injured=ally
				if injured!=null:await use_support(b,u,0,injured)
				elif not b.attack_targets(u).is_empty():await b._perform_attack(u,b._bot_pick_target(u,b.attack_targets(u)))
				else:await wait_legally(b,u)
			else:await fight_unit(b,u)
		if OS.get_cmdline_user_args().has("--trace"):
			for u in b.units:
				if u.alive:print("RALLY T",b.turn," slot",u.slot," xy",u.x,",",u.y," hp",u.hp," morale",u.morale)
		if not b.finished_flag:await b._on_end_turn()
	b.fast_sim=false
	return {"result":b.last_result,"message":b.last_message,"turn":b.turn,"stats":b.stats.duplicate(true),"finished":b.finished_flag,"phase":b.phase,"result_trigger":b.last_result_trigger.duplicate(true)}

func play_li(b) -> Dictionary:
	b.fast_sim=true
	while not b.finished_flag and b.turn<=20:
		var actors:Array=b.player_units.duplicate();actors.sort_custom(func(a,c):return a.slot<c.slot)
		for u in actors:
			if not u.alive or not u.control or u.acted or b.finished_flag:continue
			var li=b.unit_by_slot(4)
			if li==null:break
			if u.slot==4:
				await move_legally(b,u,Vector2i(20,2))
				if u.hp<u.max_hp*4/5:
					for raw in u.item_slots:
						var iid:=int(raw)-1
						if iid>=0 and iid<21:
							b.selected=u;b.active_item_id=iid;await b._execute_item_at(Vector2i(u.x,u.y));break
				await wait_legally(b,u)
			elif u.slot==0:
				# Cover the rescue's choke with one real carried explosive before
				# withdrawing. Leaving both commander explosives unused let two
				# allies absorb the entire gun line and cost two growth penalties.
				if li.control and b.turn==5:
					if await escort_throw(b,u):continue
				if li.control:
					await move_legally(b,u,Vector2i(23,3))
				else:await move_legally(b,u,Vector2i(11,10))
				if u.hp<u.max_hp*4/5:await use_support(b,u,0)
				elif li.hp<li.max_hp and b._skill_targets(u,b.data.skills[0]).has(Vector2i(li.x,li.y)):await use_support(b,u,0,li)
				elif not b.attack_targets(u).is_empty():await b._perform_attack(u,b._bot_pick_target(u,b.attack_targets(u)))
				else:await wait_legally(b,u)
			else:
				# Cover the contact turn, then withdraw with the rescued officer.
				# Chasing his *old* tile leaves the escort isolated at the choke.
				var withdraw:bool=li.control and b.turn>=(5 if u.slot==3 else 6)
				await move_legally(b,u,(Vector2i(9,3) if u.y>4 else Vector2i(23,3)) if withdraw else Vector2i(li.x,li.y))
				var ate:=false
				if u.hp<u.max_hp*4/5:
					for raw in u.item_slots:
						var iid:=int(raw)-1
						if iid>=0 and iid<21:
							b.selected=u;b.active_item_id=iid;await b._execute_item_at(Vector2i(u.x,u.y));ate=true;break
				if ate:continue
				if await escort_throw(b,u):continue
				if not b.attack_targets(u).is_empty():await b._perform_attack(u,b._bot_pick_target(u,b.attack_targets(u)))
				else:await wait_legally(b,u)
		if OS.get_cmdline_user_args().has("--trace"):
			for u in b.units:
				if u.alive:print("ESCORT T",b.turn," slot",u.slot," xy",u.x,",",u.y," hp",u.hp," control",u.control)
		if not b.finished_flag:await b._on_end_turn()
	b.fast_sim=false
	return {"result":b.last_result,"message":b.last_message,"turn":b.turn,"stats":b.stats.duplicate(true),"finished":b.finished_flag,"phase":b.phase,"result_trigger":b.last_result_trigger.duplicate(true)}

# Plan from the current town's actual catalog; never call global buy_item for
# goods that this town cannot sell, and transfer only stock actually purchased.
func prepare_supplies(gs,idx:int,campaign=null) -> Array:
	var transactions:Array=[]
	if idx==7 and tactic_enabled("--bridge-mines"):
		for slot in range(32):
			var member:Dictionary=gs.person(slot)
			if member.is_empty() or int(member.get("faction",-1))!=0:continue
			for iid in [32,35]:
				var at:int=member.get("item_slots",[]).find(iid+1)
				if at<0:continue
				transactions.append({"return":iid,"slot":slot,"result":gs.return_item(member,at)})
				transactions.append({"sell":iid,"town":gs.current_town,"result":gs.sell_item(iid)})
		if campaign!=null and gs.town_unlocked(2):
			var origin:int=gs.current_town
			campaign._select_town(2);campaign._enter_town()
			transactions.append({"travel":[origin,gs.current_town],"unlocked":gs.town_unlocked(2),"campaign_path":true})
			if gs.current_town==2:
				var recipe:Array=gs.mine(2).recipe
				var catalog:Array=gs.town(2).get("shops",{}).get("material",[])
				for mid in range(recipe.size()):
					if not catalog.any(func(it):return int(it.index)==mid):continue
					for n in range(maxi(0,6*int(recipe[mid])-gs.material_count(mid))):
						transactions.append({"buy_material":mid,"town":2,"result":gs.buy_material(mid)})
				if tactic_enabled("--bridge-grenades"):
					var goods:Array=gs.town(2).get("shops",{}).get("zahuo",[])
					if goods.any(func(it):return int(it.index)==41):
						for slot in [1,4,5,8]:
							var member:Dictionary=gs.person(slot)
							if int(member.get("faction",-1))!=0:continue
							for n in range(5):
								if not member.item_slots.has(0):break
								var bought:Dictionary=gs.buy_item(41)
								transactions.append({"buy":41,"town":2,"result":bought})
								if bought.ok:transactions.append({"carry":41,"slot":slot,"result":gs.give_item(member,41)})
			campaign._select_town(origin);campaign._enter_town()
			transactions.append({"travel":[2,gs.current_town],"unlocked":gs.town_unlocked(origin),"campaign_path":true})
		for slot in [2,3,4,8,5,8]:
			var crafted:Dictionary=gs.craft_mine(2)
			transactions.append({"craft":2,"result":crafted})
			if crafted.ok:transactions.append({"carry_mine":2,"slot":slot,"result":gs.give_mine(gs.person(slot),2)})
		var stock:Array=gs.town(gs.current_town).get("shops",{}).get("zahuo",[])
		for slot in [0,2,3,0,4,8]:
			if not stock.any(func(it):return int(it.index)==7):break
			var bought:Dictionary=gs.buy_item(7)
			transactions.append({"buy":7,"town":gs.current_town,"result":bought})
			if bought.ok:transactions.append({"carry":7,"slot":slot,"result":gs.give_item(gs.person(slot),7)})
		return transactions
	if idx==6:
		# Actual warehouse foods retained when repacking before L04. Xiao is
		# recruited by the real commander entry, so K04 can provision him now.
		for order in [{"iid":6,"slot":8},{"iid":1,"slot":8},{"iid":2,"slot":8},{"iid":12,"slot":6},{"iid":4,"slot":0}]:
			if gs.item_count(int(order.iid))>0:transactions.append({"carry":order.iid,"slot":order.slot,"result":gs.give_item(gs.person(int(order.slot)),int(order.iid))})
		# Independently fresh257 proved this actual captured-gear allocation
		# through L06/L07 with real ordinary losses and original penalties.
		transactions.append_array(prepare_captured_equipment(gs,idx))
		return transactions
	if idx==5:
		if tactic_enabled("--stone-ambush"):
			for slot in ([2,3,2,3] if tactic_enabled("--stone-cache") else [2,3]):
				var crafted:Dictionary=gs.craft_mine(1)
				transactions.append({"craft":1,"result":crafted})
				if crafted.ok:transactions.append({"carry_mine":1,"slot":slot,"result":gs.give_mine(gs.person(slot),1)})
		# Spend actual retained supplies before the hard siege, rather than
		# letting four casualties consume the commander's growth.
		for order in [{"iid":12,"slot":0},{"iid":6,"slot":1},{"iid":1,"slot":2},{"iid":2,"slot":3},{"iid":4,"slot":4}]:
			if gs.item_count(int(order.iid))>0 and int(gs.person(int(order.slot)).faction)==0:
				transactions.append({"carry":order.iid,"slot":order.slot,"result":gs.give_item(gs.person(int(order.slot)),int(order.iid))})
		var stock:Array=gs.town(gs.current_town).get("shops",{}).get("zahuo",[])
		if stock.any(func(it):return int(it.index)==41):
			if OS.get_cmdline_user_args().has("--siege-supplies"):
				# Trade the commander's actual passive equipment for finite
				# explosives. This is an economic choice with a real mobility/
				# attack cost, not a subsidy or a purchase from another town.
				var hero:Dictionary=gs.protagonist_member()
				for iid in [131,81]:
					var at:int=hero.item_slots.find(iid+1)
					if at<0:continue
					transactions.append({"return":iid,"slot":0,"result":gs.return_item(hero,at)})
					transactions.append({"sell":iid,"result":gs.sell_item(iid)})
				for slot in [4,1,2,3,4,1,2,3]:
					var recipient:Dictionary=gs.person(slot)
					if int(recipient.faction)!=0 or not recipient.item_slots.has(0) or gs.money<int(gs.item(41).price):continue
					var bought:Dictionary=gs.buy_item(41)
					transactions.append({"buy":41,"town":gs.current_town,"result":bought})
					if bought.ok:transactions.append({"carry":41,"slot":slot,"result":gs.give_item(recipient,41)})
				return transactions
			var recipient:Dictionary=gs.protagonist_member()
			if recipient.item_slots.has(0):
				var bought:Dictionary=gs.buy_item(41)
				transactions.append({"buy":41,"town":gs.current_town,"result":bought})
				if bought.ok:transactions.append({"carry":41,"slot":0,"result":gs.give_item(recipient,41)})

		return transactions
	if idx==4:
		var shops:Dictionary=gs.town(gs.current_town).get("shops",{})
		if not (shops.get("zahuo",[]) as Array).any(func(it):return int(it.index)==44):return transactions
		# Repack real food into the warehouse to carry enough finite explosives.
		var hero:Dictionary=gs.protagonist_member()
		for raw in hero.item_slots.duplicate():
			var iid:int=int(raw)-1
			if iid>=0 and iid<21:transactions.append({"return_food":iid,"slot":0,"result":gs.return_item(hero,hero.item_slots.find(int(raw)))})
		var stone_plan:bool=tactic_enabled("--stone-ambush")
		if stone_plan:
			if tactic_enabled("--stone-cache") and gs.item_count(12)>0:
				transactions.append({"sell":12,"town":gs.current_town,"result":gs.sell_item(12)})
			# Buy real town1 stock before town2, which does not sell stone.
			var recipe:Array=gs.mine(1).recipe
			var stock:Array=shops.get("material",[])
			for mid in range(recipe.size()):
				if int(recipe[mid])<=0:continue
				if not stock.any(func(it):return int(it.index)==mid):continue
				for n in range(maxi(0,(4 if tactic_enabled("--stone-cache") else 2)*int(recipe[mid])-gs.material_count(mid))):
					var bought:Dictionary=gs.buy_material(mid)
					transactions.append({"buy_material":mid,"town":gs.current_town,"result":bought})
		for slot in [0,4,2,1,3]:
			var recipient:Dictionary=gs.person(slot)
			var count:int=recipient.item_slots.count(45)
			var target:int=(2 if tactic_enabled("--stone-cache") else (3 if slot==0 else 2)) if stone_plan else (2 if slot in [1,3] else 4)
			for n in range(maxi(0,target-count)):
				if not recipient.item_slots.has(0):break
				var bought:Dictionary=gs.buy_item(44)
				transactions.append({"buy":44,"town":gs.current_town,"result":bought})
				if bought.ok:transactions.append({"carry":44,"slot":slot,"result":gs.give_item(recipient,44)})
		return transactions
	if idx!=3:return transactions
	var hero:Dictionary=gs.protagonist_member()
	# Sell the real captured manual, not invented money. This catalog sale is
	# available in Zhao village, and the original normal sale ratio is used.
	var manual_slot:int=hero.item_slots.find(36)
	if manual_slot>=0:
		transactions.append({"return":35,"slot":0,"result":gs.return_item(hero,manual_slot)})
		transactions.append({"sell":35,"result":gs.sell_item(35)})
	var shops:Dictionary=gs.town(gs.current_town).get("shops",{})
	var orders:Array=[{"iid":131,"slot":0}]
	for slot in [1,2,3,4]:
		for n in range(2):orders.append({"iid":5,"slot":slot})
	for slot in [0,1,2,3,4]:
		for n in range(2):orders.append({"iid":44,"slot":slot})
	for order in orders:
		var iid:int=order.iid
		var recipient:Dictionary=gs.person(order.slot)
		if int(recipient.faction)!=0 or not recipient.item_slots.has(0):continue
		var stock:Array=shops.get("junxie" if iid>=81 else "zahuo",[])
		if not stock.any(func(it):return int(it.index)==iid):continue
		if iid>=81 and (not gs.item_compatible(recipient,iid) or recipient.item_slots.has(iid+1)):continue
		var bought:Dictionary=gs.buy_item(iid)
		transactions.append({"buy":iid,"result":bought,"town":gs.current_town})
		if bought.ok:transactions.append({"carry":iid,"slot":order.slot,"result":gs.give_item(recipient,iid)})
	return transactions

func escort_throw(b,u) -> bool:
	var best:Dictionary={};var value:=0
	for raw in u.item_slots:
		var iid:=int(raw)-1
		if iid<41 or iid>56:continue
		var it:Dictionary=b.data.items[str(iid)]
		var mask:Dictionary=b._item_targets(u,it,"throw")
		for tile in mask:
			var score:=0
			for cell in b._apply_tiles(tile,int(it.apply_fw),u.direction):
				var victim=b._unit_at(cell.tile)
				if victim==null or b.same_faction(victim,u):continue
				var loss:int=mini(int(victim.hp),int(it.para1)*int(cell.pct)/100)
				score+=loss+100*(1 if loss>=victim.hp else 0)
			if score>value:value=score;best={"item":iid,"tile":tile}
	if best.is_empty():return false
	b.selected=u;b.active_item_id=int(best.item);await b._execute_item_at(best.tile)
	return true

# L04 is an assassination, not annihilation. March around the police cordon
# via the east side, then converge on the actual gate and target.
func play_gao(b) -> Dictionary:
	b.fast_sim=true
	var stage:=0
	var route:Array=[Vector2i(17,20),Vector2i(16,12),Vector2i(16,7)]
	var staging:Dictionary={0:Vector2i(10,0),1:Vector2i(11,0),2:Vector2i(12,0),3:Vector2i(15,2),4:Vector2i(15,3)}
	while not b.finished_flag and b.turn<=30:
		var actors:Array=b.player_units.duplicate();actors.sort_custom(func(a,c):return a.slot<c.slot)
		var guard=b.unit_by_slot(46)
		var engage:bool=guard!=null and guard.y>=17
		focus_enemy_slot=46 if engage else 40
		if stage==0 and actors.filter(func(u):return u.alive and (u.x<14 or u.y>21)).is_empty():stage=1
		if stage==1 and actors.filter(func(u):return u.alive and (u.x<15 or u.y>13)).is_empty():stage=2
		if stage==2 and actors.filter(func(u):return u.alive and (u.x<15 or u.y>9)).is_empty():stage=3
		if stage==3 and actors.filter(func(u):return u.alive and Vector2i(u.x,u.y)!=staging[u.slot]).is_empty():stage=4
		if stage>=3 and not engage and await gao_burst(b,actors):
			if b.finished_flag:break
		for u in actors:
			if not u.alive or not u.control or u.acted or b.finished_flag:continue
			if engage:
				await fight_unit(b,u)
			else:
				if stage>=3:await gao_stage_move(b,u,staging[u.slot])
				else:await move_legally(b,u,route[stage])
				if not u.alive or u.acted or b.finished_flag:continue
				if u.hp<u.max_hp*3/4 and b._skill_count(u,0)>0:await use_support(b,u,0)
				else:await wait_legally(b,u)
		if OS.get_cmdline_user_args().has("--trace"):
			for u in b.units:
				if u.alive:print("GAO T",b.turn," stage",stage," slot",u.slot," xy",u.x,",",u.y," hp",u.hp," morale",u.morale)
		if not b.finished_flag:await b._on_end_turn()
	b.fast_sim=false
	return {"result":b.last_result,"message":b.last_message,"turn":b.turn,"stats":b.stats.duplicate(true),"finished":b.finished_flag,"phase":b.phase,"result_trigger":b.last_result_trigger.duplicate(true)}

# Coordinate finite carried explosives in one player phase, rather than feed
# isolated damage into the target's real building/supply recovery every round.
func gao_burst(b,actors:Array,target_slot:=40) -> bool:
	var boss=b.unit_by_slot(target_slot)
	if boss==null:return false
	var plans:Array=[];var occupied:Dictionary={};var total:=0
	for u in actors:
		if not u.alive or not u.control or u.acted:continue
		var old:=Vector2i(u.x,u.y)
		var stations:Array=legal_stations(b,u)
		var best:Dictionary={};var value:=-999999
		for station in stations:
			if occupied.has(station):continue
			u.x=station.x;u.y=station.y
			for raw in u.item_slots:
				var iid:=int(raw)-1
				if iid<41 or iid>56:continue
				var it:Dictionary=b.data.items[str(iid)]
				for tile in b._item_targets(u,it,"throw"):
					var hit:=0
					for cell in b._apply_tiles(tile,int(it.apply_fw),u.direction):
						if cell.tile==Vector2i(boss.x,boss.y):hit=int(it.para1)*int(cell.pct)/100
					var score:int=hit*1000-absi(station.x-old.x)-absi(station.y-old.y)
					if hit>0 and score>value:value=score;best={"unit":u,"item":iid,"tile":tile,"station":station,"hit":hit}
			u.x=old.x;u.y=old.y
		if not best.is_empty():plans.append(best);occupied[best.station]=true;total+=int(best.hit)
	print("GAO_BURST T",b.turn," possible=",total," target=",boss.hp," actors=",plans.size())
	if total<boss.hp:return false
	for plan in plans:
		if not boss.alive:return true
		var u=plan.unit
		if Vector2i(u.x,u.y)!=plan.station:await move_legally(b,u,plan.station)
		if not u.alive or u.acted or not b._item_targets(u,b.data.items[str(plan.item)],"throw").has(plan.tile):return false
		b.selected=u;b.active_item_id=int(plan.item);await b._execute_item_at(plan.tile)
		if b.finished_flag:return true
	return true

func gao_stage_move(b,u,goal:Vector2i) -> void:
	if u.moved or u.acted:return
	var original:=Vector2i(u.x,u.y)
	var boss=b.unit_by_slot(40)
	var danger:Dictionary={}
	if boss!=null:
		for cell in b._select_tiles(boss,boss.select):danger[cell]=true
	var route:Array=b._astar(original,goal,u,true)
	var reachable:Dictionary=b.compute_reachable(u)
	var best:=original;var value:=999999
	for index in range(route.size()):
		var point:Vector2i=route[index]
		if not reachable.has(point):continue
		# Cross the gun's sparse ring in one move; do not end a phase on it.
		var score:int=route.size()-index+(1000 if danger.has(point) else 0)
		if score<value:value=score;best=point
	if best!=original:await move_legally(b,u,best)

func play_li_village(b) -> Dictionary:
	b.fast_sim=true
	var staging:Dictionary={0:Vector2i(9,12),1:Vector2i(8,12),2:Vector2i(9,13),3:Vector2i(10,12),4:Vector2i(8,13)}
	while not b.finished_flag and b.turn<=30:
		var actors:Array=b.player_units.filter(func(u):return u.alive and u.control)
		actors.sort_custom(func(a,c):return (100 if a.slot==0 else a.slot)<(100 if c.slot==0 else c.slot))
		if OS.get_cmdline_user_args().has("--ambush") or tactic_enabled("--stone-ambush"):
			for u in actors:
				if not u.acted and not b.finished_flag:await ambush_mine(b,u)
		var guard=b.unit_by_slot(48)
		if guard!=null:await gao_burst(b,actors.filter(func(u):return u.slot>0 and u.slot<5),48)
		if OS.get_cmdline_user_args().has("--joint") and (guard==null or not guard.alive):
			await joint_phase(b,[5,2,1,3,4,6,0])
			if not b.finished_flag:await b._on_end_turn()
			continue
		for attempt in range(3):
			if not await coordinated_kill(b,actors.filter(func(u):return u.slot!=0)):break
		for u in actors:
			if not u.alive or u.acted or b.finished_flag:continue
			if guard!=null and guard.alive and u.slot<5:
				await move_legally(b,u,staging[u.slot])
				if u.hp<u.max_hp*3/4 and b._skill_count(u,0)>0:await use_support(b,u,0)
				else:await wait_legally(b,u)
			else:await forecast_act(b,u)
		if OS.get_cmdline_user_args().has("--trace"):
			for u in b.units:
				if u.alive:print("FORECAST_TRACE T",b.turn," slot",u.slot," xy",u.x,",",u.y," hp",u.hp," morale",u.morale)
		if not b.finished_flag:await b._on_end_turn()
	b.fast_sim=false
	return {"result":b.last_result,"message":b.last_message,"turn":b.turn,"stats":b.stats.duplicate(true),"finished":b.finished_flag,"phase":b.phase,"result_trigger":b.last_result_trigger.duplicate(true)}

func ambush_mine(b,u) -> bool:
	var intention:Dictionary=Ambush.plan(b,u,tactic_enabled("--north-lure") and int(b.level.index)==5 and b.alive_enemies()<=3)
	if intention.is_empty():return false
	var origin:=Vector2i(u.x,u.y)
	if intention.station!=origin:await move_legally(b,u,intention.station)
	if not u.alive or u.acted or b.finished_flag or Vector2i(u.x,u.y)!=intention.station:return false
	if not b._mine_place_tiles(u,int(intention.mine)).has(intention.tile):return false
	b.selected=u;b.mine_kind=int(intention.mine)
	await b._place_mine(intention.tile)
	print("AMBUSH T",b.turn," slot",u.slot," code",intention.mine," tile",intention.tile," value",intention.value," committed=",u.acted)
	return u.acted

func joint_phase(b,slots:Array) -> void:
	var started:=Time.get_ticks_msec()
	var plans:Array=Planner.plan(b,slots)
	print("JOINT T",b.turn," plans=",plans.size()," ms=",Time.get_ticks_msec()-started)
	for entry in plans:
		if b.finished_flag:break
		var u=b.unit_by_slot(int(entry.slot));var a:Dictionary=entry.action
		if u==null or not u.alive or u.acted or not u.control:continue
		var origin:=Vector2i(u.x,u.y)
		if a.station!=origin:
			if not legal_stations(b,u).has(a.station):continue
			await move_legally(b,u,a.station)
		if not u.alive or u.acted or b.finished_flag:continue
		if Vector2i(u.x,u.y)!=a.station:continue
		if OS.get_cmdline_user_args().has("--trace"):print("JOINT_ACTION T",b.turn," slot",u.slot," ",a)
		match a.kind:
			"attack":
				if b._select_tiles(u,u.select).has(a.tile):await b._perform_attack_at(u,a.tile)
			"skill":
				var sid:=int(a.skill)
				if b._skill_count(u,sid)>0 and b._skill_targets(u,b.data.skills[sid]).has(a.tile):
					b.selected=u;b.active_skill_id=sid;b.active_skill=b.data.skills[sid];await b._execute_skill_at(a.tile)
			"item":
				var iid:=int(a.item)
				if u.item_slots.has(iid+1) and b._item_targets(u,b.data.items[str(iid)],"apply" if iid<21 else "throw").has(a.tile):
					b.selected=u;b.active_item_id=iid;await b._execute_item_at(a.tile)
		await wait_legally(b,u)
	if OS.get_cmdline_user_args().has("--trace"):
		for u in b.units:
			if u.alive:print("JOINT_TRACE T",b.turn," slot",u.slot," xy",u.x,",",u.y," hp",u.hp," morale",u.morale)

# A tactical probe is not exempt from player movement/action permissions.
# In particular a failed burst may not move its actor a second time afterwards.
func legal_stations(b,u) -> Array:
	return forecast_candidate_set().legal_stations(b,u)

func wait_legally(b,u) -> void:
	if u==null or not u.alive or u.acted or b.finished_flag:return
	b.selected=u
	await b._on_wait()

func move_legally(b,u,goal:Vector2i) -> bool:
	if u.moved or u.acted or not u.alive or not u.control or b.phase!="player":return false
	return await b._bot_move_to(u,goal)

func forecast_candidate_set():
	var candidate_set=CandidateSet.new();candidate_set.focus_enemy_slot=focus_enemy_slot;candidate_set.bridge_hold=bridge_hold;candidate_set.policy=tactic_enabled
	return candidate_set

func forecast_act(b,u,move_goal:=Vector2i(-1,-1)) -> void:
	var origin:=Vector2i(u.x,u.y)
	var shortlist:Array=forecast_candidate_set().generate(b,u,move_goal).shortlist
	var chosen:Dictionary={};var best:=-999999
	for a in shortlist:
		var forecast:Dictionary=Forecast.evaluate(b,u.slot,a)
		var score:int=int(a.utility)-int(forecast.cost)
		if int(b.level.index)==7 and u.slot not in [0,2,3,6,7]:score=int(a.utility)*2-int(forecast.cost)*2/3
		if score>best:best=score;chosen=a.duplicate();chosen.prediction=forecast
	if chosen.is_empty():await wait_legally(b,u);return
	if OS.get_cmdline_user_args().has("--trace"):print("FORECAST T",b.turn," slot",u.slot," ",chosen.kind," station",chosen.station," tile",chosen.tile," score",best," health",chosen.prediction.units)
	if chosen.station!=origin:await move_legally(b,u,chosen.station)
	if not u.alive or u.acted or b.finished_flag:return
	match chosen.kind:
		"attack":
			var victim=b.unit_by_slot(int(chosen.target))
			if victim!=null and b._in_attack_range(u,victim):await b._perform_attack(u,victim)
		"skill":
			b.selected=u;b.active_skill_id=int(chosen.skill);b.active_skill=b.data.skills[int(chosen.skill)];await b._execute_skill_at(chosen.tile)
		"item":b.selected=u;b.active_item_id=int(chosen.item);await b._execute_item_at(chosen.tile)
	await wait_legally(b,u)

func support_value(b,u,tile:Vector2i,sid:int) -> int:
	return forecast_candidate_set().support_value(b,u,tile,sid)

func coordinated_kill(b,actors:Array) -> bool:
	var choices:Array=[]
	for enemy in b.enemy_units:
		if not enemy.alive:continue
		var plans:Array=[];var occupied:Dictionary={};var total:=0;var risk:=0
		for u in actors:
			if not u.alive or not u.control or u.acted:continue
			var plan:Dictionary=focus_plan(b,u,enemy,occupied)
			if plan.is_empty():continue
			plans.append(plan);occupied[plan.station]=true;total+=int(plan.hit);risk+=int(plan.risk)
		if total>=enemy.hp:
			var actions:Array=[]
			for p in plans:actions.append({"slot":p.unit.slot,"action":p})
			var forecast:Dictionary=Forecast.evaluate_sequence(b,actions)
			if forecast.cost<2000:choices.append({"enemy":enemy,"plans":plans,"score":500-forecast.cost})
	if choices.is_empty():return false
	choices.sort_custom(func(a,c):return a.score>c.score)
	var choice:Dictionary=choices[0]
	print("COORD T",b.turn," target",choice.enemy.slot," plans",choice.plans.size()," score",choice.score)
	choice.plans.sort_custom(func(a,c):return a.hit>c.hit)
	for plan in choice.plans:
		if not choice.enemy.alive or b.finished_flag:break
		var u=plan.unit
		if Vector2i(u.x,u.y)!=plan.station:
			if not legal_stations(b,u).has(plan.station):continue
			await move_legally(b,u,plan.station)
		if not u.alive or u.acted:continue
		if plan.kind=="attack":
			if b._in_attack_range(u,choice.enemy):await b._perform_attack(u,choice.enemy)
		else:
			if not b._item_targets(u,b.data.items[str(plan.item)],"throw").has(plan.tile):continue
			b.selected=u;b.active_item_id=int(plan.item);await b._execute_item_at(plan.tile)
	return true

func focus_plan(b,u,target,occupied:Dictionary) -> Dictionary:
	var original:=Vector2i(u.x,u.y)
	var stations:Array=legal_stations(b,u)
	var fields:Array=threats(b,u)
	var best:Dictionary={};var value:=-999999
	for station in stations:
		if occupied.has(station):continue
		var risk:=danger_at(b,u,station,fields,[target])
		if risk>=u.hp and u.slot==0:continue
		u.x=station.x;u.y=station.y
		var actions:Array=[]
		if b._in_attack_range(u,target):actions.append({"kind":"attack","tile":Vector2i(target.x,target.y),"hit":b.compute_damage(u,target)})
		for raw in u.item_slots:
			var iid:=int(raw)-1
			if iid<41 or iid>56:continue
			var it:Dictionary=b.data.items[str(iid)]
			for tile in b._item_targets(u,it,"throw"):
				for cell in b._apply_tiles(tile,int(it.apply_fw),u.direction):
					if cell.tile==Vector2i(target.x,target.y):actions.append({"kind":"item","item":iid,"tile":tile,"hit":int(it.para1)*int(cell.pct)/100})
		for action in actions:
			var score:int=int(action.hit)*10-risk-absi(station.x-original.x)-absi(station.y-original.y)
			if risk>=u.hp:score-=1000
			if score>value:value=score;best=action.duplicate();best.unit=u;best.station=station;best.risk=risk
		u.x=original.x;u.y=original.y
	return best


# General player-only formation planner for subsequent real campaign battles.
# Rear units commit first so exposed units can see their final support positions.
func play_forecast_group(b) -> Dictionary:
	b.fast_sim=true
	while not b.finished_flag and b.turn<=120:
		var actors:Array=b.player_units.filter(func(u):return u.alive and u.control)
		actors.sort_custom(func(a,c):return (a.y>c.y if a.y!=c.y else a.slot<c.slot) if a.slot!=0 and c.slot!=0 else c.slot==0)
		for attempt in range(4):
			if not await coordinated_kill(b,actors.filter(func(u):return u.slot!=0)):break
		for u in actors:
			if u.alive and not u.acted and not b.finished_flag:await forecast_act(b,u)
		if OS.get_cmdline_user_args().has("--trace"):
			for u in b.units:
				if u.alive:print("GROUP T",b.turn," slot",u.slot," xy",u.x,",",u.y," hp",u.hp," morale",u.morale)
		if not b.finished_flag:await b._on_end_turn()
	b.fast_sim=false
	return {"result":b.last_result,"message":b.last_message,"turn":b.turn,"stats":b.stats.duplicate(true),"finished":b.finished_flag,"phase":b.phase,"result_trigger":b.last_result_trigger.duplicate(true)}

func play_bridge(b) -> Dictionary:
	b.fast_sim=true
	while not b.finished_flag and b.turn<=40:
		var actors:Array=b.player_units.filter(func(u):return u.alive and u.control)
		var order:Array=[1,5,8,4,2,3,6,7,0]
		actors.sort_custom(func(a,c):return order.find(a.slot)<order.find(c.slot))
		if tactic_enabled("--bridge-mines"):
			for u in actors:
				if not u.acted and not b.finished_flag:await ambush_mine(b,u)
		for attempt in range(4):
			if not await coordinated_kill(b,actors.filter(func(u):return u.slot not in [0,6,7])):break
		for u in actors:
			if not u.alive or u.acted or b.finished_flag:continue
			if u.slot in [2,3] and b.turn>=5 and await intercept_mine(b,u):continue
			var goal:=Vector2i(30,31) if u.slot==0 else Vector2i(28,28)
			await forecast_act(b,u,goal if b.turn<=bridge_hold else Vector2i(-1,-1))
		if OS.get_cmdline_user_args().has("--trace"):
			for u in b.units:
				if u.alive:print("BRIDGE T",b.turn," slot",u.slot," xy",u.x,",",u.y," hp",u.hp," morale",u.morale)
		if not b.finished_flag:await b._on_end_turn()
	b.fast_sim=false
	return {"result":b.last_result,"message":b.last_message,"turn":b.turn,"stats":b.stats.duplicate(true),"finished":b.finished_flag,"phase":b.phase,"result_trigger":b.last_result_trigger.duplicate(true)}

func intercept_mine(b,u) -> bool:
	# Plant only an actually carried mine, at a visible pursuer's forecast
	# endpoint. This is a heuristic ambush, not a forced enemy step/detonation.
	if not u.mine_slots.has(1):return false
	var origin:=Vector2i(u.x,u.y)
	var forecast:Dictionary=Forecast.evaluate(b,u.slot,{"kind":"wait","station":origin})
	var chosen:Dictionary={};var best:=999999
	for entry in forecast.plans:
		if int(entry.slot) not in [47,48]:continue
		var enemy=b.unit_by_slot(int(entry.slot))
		if enemy==null:continue
		var tile:Vector2i=entry.choice.station
		if tile==Vector2i(enemy.x,enemy.y) or b._unit_at(tile)!=null or b._mine_at(tile)>=0:continue
		for station in legal_stations(b,u):
			u.x=station.x;u.y=station.y
			var can_plant:bool=b._mine_place_tiles(u,0).has(tile)
			u.x=origin.x;u.y=origin.y
			if not can_plant:continue
			var risk:Dictionary=Forecast.evaluate(b,u.slot,{"kind":"wait","station":station})
			var score:int=int(risk.cost)+absi(station.x-origin.x)+absi(station.y-origin.y)
			if risk.cost<2000 and score<best:best=score;chosen={"station":station,"tile":tile}
	if chosen.is_empty():return false
	if chosen.station!=origin:await move_legally(b,u,chosen.station)
	if u.acted or not u.alive or not b._mine_place_tiles(u,0).has(chosen.tile):return false
	b.selected=u;b.mine_kind=0;await b._place_mine(chosen.tile)
	print("BRIDGE_TRAP T",b.turn," slot",u.slot," tile",chosen.tile," placed=",u.acted)
	return u.acted

# L06: Xiao Fei must withdraw with the officer, not charge north alone.
# The rest of the real deployed party moves to meet the retreating pair.
func play_xiao(b) -> Dictionary:
	b.fast_sim=true
	var collect_book:=tactic_enabled("--cache-book") or tactic_enabled("--bridge-mines")
	while not b.finished_flag and b.turn<=20:
		var actors:Array=b.player_units.filter(func(u):return u.alive and u.control)
		actors.sort_custom(func(a,c):return (a.y>c.y if a.y!=c.y else a.slot<c.slot) if a.slot!=0 and c.slot!=0 else c.slot==0)
		for attempt in range(3):
			if not await coordinated_kill(b,actors.filter(func(u):return u.slot not in [0,8] and not (collect_book and u.slot==3 and not bool(b.chests[0].get("opened",false))))):break
		for u in actors:
			if not u.alive or u.acted or b.finished_flag:continue
			var girl=b.unit_by_slot(7)
			if collect_book and u.slot==3 and not bool(b.chests[0].get("opened",false)):
				await move_legally(b,u,Vector2i(0,31))
				if not u.acted and u.alive:await wait_legally(b,u)
				continue
			var goal:=Vector2i(25,35) if u.slot==8 else Vector2i(girl.x,girl.y) if girl!=null else Vector2i(18,15)
			# Once the pursuers are reduced to the last visible pair, the
			# rendezvous is over: bodyguards must help finish, not escort the
			# rescued officer all the way south while one rifleman hunts alone.
			if collect_book and b.alive_enemies()<=2:goal=Vector2i(-1,-1)
			if (u.slot==0 and b.turn>=17) or (u.slot==5 and b.turn>=10):
				var straggler=b.unit_by_slot(45)
				if straggler!=null:goal=Vector2i(straggler.x,straggler.y)
			await forecast_act(b,u,goal)
		if OS.get_cmdline_user_args().has("--trace"):
			for u in b.units:
				if u.alive:print("XIAO T",b.turn," slot",u.slot," xy",u.x,",",u.y," hp",u.hp," morale",u.morale)
		if not b.finished_flag:await b._on_end_turn()
	b.fast_sim=false
	return {"result":b.last_result,"message":b.last_message,"turn":b.turn,"stats":b.stats.duplicate(true),"finished":b.finished_flag,"phase":b.phase,"result_trigger":b.last_result_trigger.duplicate(true)}

func prepare_captured_equipment(gs,idx:int) -> Array:
	var transactions:Array=[]
	if idx!=6:return transactions
	var roster:Array=gs.deployment_roster(idx)
	# Scripted controlled Xiao8 is a real recruited party member before K00.
	roster.append(gs.person(8))
	roster.sort_custom(func(a,c):return int(a.pid)<int(c.pid))
	var transfers:=0
	for member in roster:
		if int(member.get("faction",1))!=0:continue
		var before:Dictionary=gs.equipment_bonuses(member)
		var chosen:=-1;var best:=0
		for iid in range(81,156):
			if gs.item_count(iid)<=0 or not gs.item_compatible(member,iid):continue
			var it:Dictionary=gs.item(iid)
			var value:int=maxi(0,int(it.para3)-int(before.attack))*2+maxi(0,int(it.para4)-int(before.defense))*3+maxi(0,int(it.para1)-int(before.move))*12
			if value>best:best=value;chosen=iid
		if chosen<0:continue
		# Return at most one obsolete passive, only if replacement keeps every
		# prior bonus. Never discard food, explosives, books, or a mobility bonus.
		var replacement:Dictionary=gs.item(chosen)
		var returned:=-1
		for i in range(member.item_slots.size()):
			var old:int=int(member.item_slots[i])-1
			if old<81 or not gs.item_compatible(member,old):continue
			var it:Dictionary=gs.item(old)
			if int(replacement.para3)>=int(it.para3) and int(replacement.para4)>=int(it.para4) and int(replacement.para1)>=int(it.para1):returned=i;break
		if returned>=0:transactions.append({"gear243_return":int(member.item_slots[returned])-1,"pid":int(member.pid),"result":gs.return_item(member,returned)})
		if not member.item_slots.has(0):continue
		var result:Dictionary=gs.give_item(member,chosen)
		var after:Dictionary=gs.equipment_bonuses(member)
		transactions.append({"gear243_carry":chosen,"pid":int(member.pid),"before":before,"after":after,"result":result})
		print("GEAR243 pid",member.pid," item",chosen," before",before," after",after," result",result.ok)
		if result.ok:transfers+=1
		if transfers>=12:break
	return transactions
