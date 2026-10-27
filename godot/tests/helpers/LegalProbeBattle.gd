extends "res://scripts/Battle.gd"

# Test-only facade around the unchanged game resolver. It refuses an action a
# real player's UI could not commit, and retains auditable per-turn permissions.
var legal_action_log:Array=[]
var legal_move_log:Array=[]
var legal_errors:Array=[]
var legal_mine_events:Array=[]
var _probe_actions:Dictionary={}
var _probe_moves:Dictionary={}
var _probe_epochs:Dictionary={}
var report_violations:=true

func _probe_drain() -> void:
	var owner=get_parent()
	if (phase=="player" or finished_flag) and owner!=null and owner.has_method("drain_story"):await owner.drain_story()

func _on_end_turn(from_bot := false) -> void:
	await _probe_drain()
	await super._on_end_turn(from_bot)
	await _probe_drain()

func _probe_key(u) -> String:
	return "%d:%d:%d"%[turn,u.slot,int(_probe_epochs.get(u.slot,0))]

func _probe_actor(u) -> bool:
	return not busy and not finished_flag and u!=null and u.alive and u.is_player() and u.control and not u.acted

func _probe_reject(reason:String,u) -> void:
	var record:Dictionary={"turn":turn,"slot":-1 if u==null else u.slot,"reason":reason}
	legal_errors.append(record)
	if report_violations:push_error("LEGAL_PERMISSION "+str(record))

func _probe_action(u,kind:String,tile:Vector2i) -> bool:
	if phase!="player":return true
	if not _probe_actor(u):_probe_reject("actor "+kind,u);return false
	var key:String=_probe_key(u)
	if _probe_actions.has(key):_probe_reject("second action "+kind,u);return false
	_probe_actions[key]=true
	legal_action_log.append({"turn":turn,"slot":u.slot,"epoch":int(_probe_epochs.get(u.slot,0)),"kind":kind,"tile":[tile.x,tile.y]})
	return true

func _bot_move_to(u:Node2D,goal:Vector2i,pass_allies:=false) -> bool:
	if phase=="player" and (not _probe_actor(u) or u.moved):
		_probe_reject("move permission",u);return false
	var before:=Vector2i(u.x,u.y)
	var was_player_move:bool=phase=="player"
	var moved:bool=await super._bot_move_to(u,goal,pass_allies)
	if was_player_move and Vector2i(u.x,u.y)!=before:
		var key:String=_probe_key(u)
		if _probe_moves.has(key):_probe_reject("second movement",u)
		_probe_moves[key]=true
		legal_move_log.append({"turn":turn,"slot":u.slot,"epoch":int(_probe_epochs.get(u.slot,0)),"from":[before.x,before.y],"to":[u.x,u.y]})
	await _probe_drain()
	return moved

func _perform_attack_at(u:Node2D,tile:Vector2i) -> void:
	if phase=="player":
		if not _select_tiles(u,u.select).has(tile):_probe_reject("attack range",u);return
		if not _probe_action(u,"attack",tile):return
	await super._perform_attack_at(u,tile)
	await _probe_drain()

func _on_wait() -> void:
	if phase=="player" and not _probe_action(selected,"wait",Vector2i(-1,-1)):return
	await super._on_wait()
	await _probe_drain()

func _execute_skill_at(tile:Vector2i) -> void:
	var prior_acted:Dictionary={}
	if active_skill_id==12:
		for u in player_units:
			if u.alive:prior_acted[u.slot]=u.acted
	if phase=="player":
		if selected==null or _skill_count(selected,active_skill_id)<=0 or not _skill_targets(selected,active_skill).has(tile):
			_probe_reject("skill availability/range",selected);return
		if not _probe_action(selected,"skill:%d"%active_skill_id,tile):return
	await super._execute_skill_at(tile)
	# Original duty/supervise legitimately grants another action and movement.
	# Do not mistake this earned renewal for an illicit second player action.
	for u in player_units:
		if u.alive and prior_acted.get(u.slot,false) and not u.acted:
			_probe_epochs[u.slot]=int(_probe_epochs.get(u.slot,0))+1
	await _probe_drain()

func _execute_item_at(tile:Vector2i) -> void:
	if phase=="player":
		if selected==null or not selected.item_slots.has(active_item_id+1):_probe_reject("item not carried",selected);return
		if active_item_id>=61 or active_item_id in [31,32]:_probe_reject("item not actively usable",selected);return
		var it:Dictionary=data.items.get(str(active_item_id),{})
		if it.is_empty() or not _item_targets(selected,it,_item_kind(active_item_id)).has(tile):_probe_reject("item range",selected);return
		if not _probe_action(selected,"item:%d"%active_item_id,tile):return
	await super._execute_item_at(tile)
	await _probe_drain()

func _place_mine(tile:=Vector2i(-1,-1),rounds:=1) -> void:
	# Opening the submenu with an invalid/default tile is not a committed act.
	if selected==null:_probe_reject("mine actor",null);return
	if not _mine_place_tiles(selected,mine_kind).has(tile):
		super._place_mine(tile,rounds);return
	if phase=="player":
		if selected==null or not selected.mine_slots.has(mine_kind+1):_probe_reject("mine not carried",selected);return
		if not _probe_action(selected,"mine:%d"%mine_kind,tile):return
	super._place_mine(tile,rounds)
	await _probe_drain()

func _detonate_mines(tile:Vector2i) -> void:
	var before:Dictionary={}
	for u in units:
		if u.alive:before[u.slot]={"hp":u.hp,"morale":u.morale,"xy":[u.x,u.y]}
	var at:=_mine_at(tile)
	var code:int=int(mines[at].get("code",mines[at].get("mine_id",0))) if at>=0 else -1
	await super._detonate_mines(tile)
	var changes:Array=[]
	for u in units:
		if before.has(u.slot) and (int(before[u.slot].hp)!=u.hp or int(before[u.slot].morale)!=u.morale or not u.alive):
			changes.append({"slot":u.slot,"before":before[u.slot],"hp":u.hp,"morale":u.morale,"alive":u.alive})
	var event:Dictionary={"turn":turn,"phase":phase,"tile":[tile.x,tile.y],"code":code,"changes":changes}
	legal_mine_events.append(event)
	print("LEGAL_MINE_EVENT ",event)

func _discard_item(id:int) -> void:
	if phase=="player":
		if selected==null or not selected.item_slots.has(id+1):_probe_reject("discard not carried",selected);return
		if not _probe_action(selected,"discard:%d"%id,Vector2i(selected.x,selected.y)):return
	await super._discard_item(id)
	await _probe_drain()

func _execute_item_transfer(tile:Vector2i) -> void:
	if phase=="player":
		if selected==null or not selected.item_slots.has(active_item_id+1):_probe_reject("give item not carried",selected);return
		if not preload("res://scripts/battle/OriginalRangeMask.gd").allows(native_dark_mask,map_w,map_h,tile) or _unit_at(tile)==null:return
		if not _probe_action(selected,"give-item:%d"%active_item_id,tile):return
	await super._execute_item_transfer(tile)
	await _probe_drain()

func _use_manual_item(id:int) -> void:
	if phase=="player":
		if selected==null or id<61 or id>80 or not selected.item_slots.has(id+1):_probe_reject("manual not carried",selected);return
		if not _probe_action(selected,"manual:%d"%id,Vector2i(selected.x,selected.y)):return
	await super._use_manual_item(id)
	await _probe_drain()
