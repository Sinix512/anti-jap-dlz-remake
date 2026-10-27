extends RefCounted
# Test-only player navigation. Every transition uses the production viewport;
# no launch/confirmed callback, phase write, RNG seed or score mutation here.
const InputDriver=preload("res://tests/helpers/NativeRouteInput.gd")
const Confirm=preload("res://scripts/ui/OriginalConfirm.gd")
const Choice=preload("res://scripts/ui/OriginalChoice.gd")
const Town=preload("res://scripts/m4/TownRules.gd")
var input=InputDriver.new()
var actions:Array=[]
var visited:Dictionary={}
var supplied:Dictionary={}
var mission_towns:Dictionary={}
var resident_attempts:=0
# D4/D8 are also relationship counters in the original. Waiting until the
# late campaign can lose44/45 even when they were never played. Seek at the
# first post-L00 strategic window, without changing either shared DWORD.
var interlude_at:=1
var interlude_budget:=64
var last_action_ms:=0
var answered:Dictionary={}
var before_departure:Callable

func interlude_plan(campaign) -> Dictionary:
	var pending:Array=[]
	var lost:Array=[]
	for idx in [44,45,46]:
		if campaign.state.campaign_completed.has(idx):continue
		pending.append(idx)
		var flag:int=[3,4,9][idx-44]
		if Town.get_flag(campaign.state,flag)!=0:lost.append({"idx":idx,"flag":flag,"value":Town.get_flag(campaign.state,flag)})
	var idx:int=campaign.state.campaign_index
	return {"active":idx>=interlude_at and idx<36 and not pending.is_empty(),"pending":pending,"lost":lost}

func bind(campaign,mode:String) -> void:
	input.bind(campaign,mode)
	campaign.native_route_input=input
	campaign.game_close_requested.connect(func():campaign.trace_route("close",campaign.route_state(),{"ending_flow":campaign.ending_flow_events.duplicate(),"input_count":input.events.size()}))

func click(campaign,point:Vector2,label:String,double:=false) -> void:
	var before:Dictionary=campaign.route_state()
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point
	campaign.get_tree().root.push_input(motion,true)
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.global_position=point
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.double_click=double and down
		campaign.get_tree().root.push_input(event,true)
	actions.append({"kind":label,"point":[point.x,point.y],"input":["MOVE","LEFT-DOUBLE-DOWN" if double else "LEFT-DOWN","LEFT-UP"],"before":before,"after":campaign.route_state(),"frame":Engine.get_process_frames()})
	last_action_ms=Time.get_ticks_msec()

func building_point(campaign,slot:int) -> Vector2:
	var screen=campaign.strategic_screen
	# Native hit priority includes overlapping rectangles. Use a verified pixel
	# inside the intended hit region, not an assumed rectangle centre.
	var raw:Array=screen.contract.towns[campaign.state.current_town].buildings[slot].rect
	for y in range(int(raw[1])+1,int(raw[1]+raw[3]),2):
		for x in range(int(raw[0])+1,int(raw[0]+raw[2]),2):
			if screen.building_at(Vector2(x,y))==slot:return Vector2(x,y)
	return Vector2(-1,-1)

func navigate(campaign,town:int) -> bool:
	match campaign.mode:
		"resident":click(campaign,Vector2(572,56),"resident_exit")
		"command":click(campaign,Vector2(550,40),"command_exit")
		"town":
			if campaign.state.current_town==town:return true
			var point:=building_point(campaign,4)
			if point.x>=0:click(campaign,point,"world_exit")
		"world":
			if not campaign.state.town_unlocked(town):return false
			for record in campaign.strategic_screen.contract.world.towns:
				if int(record.index)==town:
					var r:Array=record.rect
					click(campaign,Vector2(r[0]+r[2]/2.0,r[1]+r[3]/2.0),"town_enter")
	return false

func deploy(campaign) -> void:
	var screen=campaign.deployment_screen
	var idx:int=screen.level_index
	var desired:Array=[-100,6,5,1,2,3,4] if idx==6 else campaign.state.deployment_roster(idx).map(func(m):return int(m.pid))
	for pid in desired:
		if screen.selected_slots().has(pid) or screen.count()>=screen.limit:continue
		for slot in range(32):
			var member:Dictionary=screen.member(0,slot)
			if member.is_empty() or int(member.pid)!=pid:continue
			if int(screen.pages[0])!=slot/16:
				click(campaign,Vector2(270,365),"deployment_page");return
			var i:=slot%16
			click(campaign,Vector2(56+72*(i%4),98+64*(i/4)),"deployment_transfer",true);return
	click(campaign,screen.GO.get_center(),"deployment_submit")

func next_battle(campaign,timeout_ms:=180000) -> Dictionary:
	var start:=Time.get_ticks_msec()
	while Time.get_ticks_msec()-start<timeout_ms:
		if input.closed:return {"ok":true,"boundary":"process_close"}
		if is_instance_valid(campaign.battle) and not campaign.battle.finished_flag:
			await campaign.drain_story()
			if not campaign.battle.busy:return {"ok":true,"boundary":"battle","idx":campaign.current_battle_index}
		if input.pump(campaign):
			await campaign.get_tree().process_frame;continue
		if is_instance_valid(campaign.ending_layer) or is_instance_valid(campaign.story_player) or is_instance_valid(campaign.cutscene) or Time.get_ticks_msec()-last_action_ms<30:
			await campaign.get_tree().create_timer(.01).timeout;continue
		var panel=campaign.panel_root
		if is_instance_valid(panel) and not panel.is_queued_for_deletion():
			var key:=str(panel.get_instance_id())
			if not answered.has(key):
				if panel is Confirm and not panel.done:
					answered[key]=true;click(campaign,panel.origin+Vector2(64,44),"departure_yes")
				elif panel is Choice and panel.interactive and not panel.done and campaign.mode!="hidden_choice":
					answered[key]=true;click(campaign,panel.row_rect(0).get_center(),"solo_choice")
		elif is_instance_valid(campaign.deployment_screen) and campaign.deployment_screen.is_visible_in_tree() and not campaign.deployment_screen.done:
			deploy(campaign)
		else:
			var idx:int=campaign.state.campaign_index
			if idx<44 and not mission_towns.has(idx):mission_towns[idx]=campaign.state.current_town
			var plan:=interlude_plan(campaign)
			# A nonzero shared counter is NOT a played-win witness. Record a
			# clean incomplete policy boundary, never clear it or silently skip.
			if plan.active and not plan.lost.is_empty():return {"ok":true,"boundary":"interlude_window_lost","lost":plan.lost,"state":campaign.route_state()}
			var seek_interlude:bool=plan.active
			if seek_interlude and resident_attempts>=interlude_budget:return {"ok":false,"boundary":"interlude_visit_budget","attempts":resident_attempts}
			var town:int=0 if seek_interlude else campaign.state.current_town
			# After an interlude the native return is town0. Re-enter the actual
			# mission town; never repair campaign_index or a return flag directly.
			# Hidden fiction's real entry is town17 even though the generic
			# level resource says town0. Preserve the native strategic return;
			# never infer it from the level ID/static resource town field.
			if not seek_interlude:town=int(mission_towns.get(idx,campaign.state.current_town))
			if navigate(campaign,town):
				var key:="%d:%d"%[idx,town]
				if seek_interlude or not visited.has(key):
					var point:=building_point(campaign,0)
					if point.x>=0:
						visited[key]=true
						if seek_interlude:resident_attempts+=1
						click(campaign,point,"interlude_resident" if seek_interlude else "mission_resident")
				elif not supplied.has(idx) and before_departure.is_valid():
					supplied[idx]=before_departure.call(idx)
				else:
					var point:=building_point(campaign,1)
					if point.x>=0:click(campaign,point,"mission_command")
		await campaign.get_tree().create_timer(.01).timeout
	return {"ok":false,"boundary":"watchdog","state":campaign.route_state(),"mode":campaign.mode}
