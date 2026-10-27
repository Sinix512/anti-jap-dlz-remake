extends SceneTree
# Synthetic launch fixtures. No battle is won; the oracle is the original
# town0 direct-entry path plus Fighter[0..39].stage==0, not Intro's stale count.
const State=preload("res://scripts/m2/GameState.gd")
const Builder=preload("res://scripts/m4/LevelBuilder.gd")
const Campaign=preload("res://tests/helpers/LegalProbeCampaign.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("INTERLUDE_PARTY "+label)
func run() -> void:
	var s=State.new();s.new_game(JSON.parse_string(FileAccess.get_file_as_string("res://data/m2.json")));s.setup_m4(JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json")));s.configure_protagonist(103,4,100)
	# Synthetic lawful roster, including a previously selected named party.
	s.set_person_side(1,0);s.set_person_side(2,0)
	var roster:Array=[]
	for i in range(40):roster.append(s.person(i))
	check(int(s.m4_level(45).max_deploy)==17,"preserves original Intro special_count17")
	check(s.m4_level(45).deploy.size()==17,"preserves all original Special coordinates")
	for idx in [44,45,46]:
		check(not s.m4_level(idx).party_deploy,"direct native interlude does not offer named-party placement L%d"%idx)
		for selection in [[],[-100,1,2]]:
			var level:Dictionary=Builder.build(s.m4_data,s.data,idx,roster,false,-1,selection)
			var low:Array=level.units.filter(func(u):return int(u.slot)<40)
			check(low.is_empty(),"no mainline party insertion L%d selected=%s"%[idx,str(selection)])
			check(level.units.size()==s.m4_level(idx).units.size(),"exact original active Fighter count L%d"%idx)
			check(level.units.map(func(u):return int(u.slot))==s.m4_level(idx).units.map(func(u):return int(u.slot)),"exact original active Fighter identities L%d"%idx)
	var fiction:Dictionary=Builder.build(s.m4_data,s.data,40,roster,false,-1,[-100,1,2])
	check(fiction.units.any(func(u):return int(u.slot)==0),"town17 fiction still performs real party placement")
	var c=Campaign.new();root.add_child(c);c.setup(load("res://assets/font/hzk16.fnt"),{"name":"李勇","face":103,"unit":4,"wuli":100,"difficulty":1});c.qa_mode=true
	c.state.set_person_side(1,0);c.current_deploy_pids=[-100,1]
	c._show_deployment(45);await c.drain_story();await process_frame
	check(not is_instance_valid(c.deployment_screen),"L45 bypasses K00 even with raw count17")
	check(is_instance_valid(c.battle) and c.current_battle_index==45,"direct L45 really launches production Battle")
	if not is_instance_valid(c.battle):c._launch_level(45,false);await c.drain_story()
	check(c.current_deploy_pids.is_empty(),"direct interlude drops stale deployment selection metadata")
	check(c.battle.units.map(func(u):return u.slot)==range(40,66),"actual L45 contains exact original active40..65, no named party")
	check(c.battle.unit_by_slot(40).control and not c.battle.unit_by_slot(41).control,"original rabbit controlled, rival automated")
	check(c.state.campaign_completed.is_empty(),"fixtures manufacture no victory")
	c.queue_free();await process_frame;await process_frame
	root.get_node("Music").release_playback();OriginalUI.release_native_sfx();await create_timer(.2).timeout
	print("INTERLUDE_PARTY checks=",checks," failures=",failures)
	if failures==0:print("INTERLUDE_PARTY PASS")
	quit(1 if failures else 0)
