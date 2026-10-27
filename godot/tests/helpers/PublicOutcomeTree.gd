extends RefCounted
# Exhaustive, bounded PUBLIC conditional outcomes. Not a live resolver, RNG
# oracle, future-script predictor, or proof of campaign success.
const Forecast=preload("res://tests/helpers/PublicRoundForecast.gd")
const Base=preload("res://tests/helpers/TacticalForecast.gd")

static func budget(limits:Dictionary={}) -> Dictionary:
	return {"max_branches":clampi(int(limits.get("branches",64)),0,4096),
		"max_actions":clampi(int(limits.get("actions",2048)),0,65536),
		"max_steps":clampi(int(limits.get("phase_steps",256)),0,4096),
		"max_candidates":clampi(int(limits.get("candidates",4)),0,64),
		"branches_created":1,"actions_expanded":0,"candidates_expanded":0}

static func _entry(b) -> Dictionary:
	return {"board":b,"trace":[],"phases":[],"boundaries":[],"phase_steps":0,"terminal":Forecast.critical_lost(b)}

# All returned branch boards are owned by the caller. No board is ever shared
# between entries or with the input. Failures return no owned boards.
static func dispose(entries:Array) -> void:
	for entry in entries:entry.board.free()
	entries.clear()

static func _failure(status:String,reason:String,entries:Array,limits:Dictionary) -> Dictionary:
	var count:=entries.size();dispose(entries)
	return {"status":status,"reason":reason,"complete":false,"branches":[],
		"discarded_frontier":count,"budget":limits.duplicate(true),"conditional_survival":false}

static func _expand(entry:Dictionary,slot:int,action:Dictionary,limits:Dictionary) -> Dictionary:
	var b=entry.board;var u=b.unit_by_slot(slot)
	var inspected:Dictionary=Forecast.inspect_action_outcomes(b,u,action)
	if inspected.status not in ["complete","needs_outcomes"]:
		return {"status":inspected.status,"reason":inspected.reason,"complete":false,"branches":[]}
	var keys:Array=[]
	for op in inspected.opportunities:
		if op.requires_outcome:keys.append(op.key)
	# Saturate before any exponential allocation. A cap is NOT a low-risk leaf.
	var needed:=1
	for key in keys:
		needed*=2
		if int(limits.branches_created)+needed-1>int(limits.max_branches):
			return {"status":"incomplete","reason":"outcome branch cap","complete":false,"branches":[],"unexpanded_at_least":needed}
	if int(limits.branches_created)+needed-1>int(limits.max_branches):
		return {"status":"incomplete","reason":"outcome branch cap","complete":false,"branches":[],"unexpanded_at_least":needed}
	if int(limits.actions_expanded)+needed>int(limits.max_actions):
		return {"status":"incomplete","reason":"outcome action cap","complete":false,"branches":[],"unexpanded_at_least":needed}
	var children:Array=[]
	for mask in range(needed):
		var mapping:Dictionary={}
		for i in range(keys.size()):mapping[keys[i]]=(mask&(1<<i))!=0
		var child=Forecast.clone_branch(b)
		var applied:Dictionary=Forecast.apply_action_with_outcomes(child,child.unit_by_slot(slot),action,mapping)
		if not applied.complete:
			child.free();dispose(children)
			return {"status":applied.status,"reason":applied.reason,"complete":false,"branches":[]}
		var next:Dictionary=entry.duplicate(false);next.board=child
		next.trace=entry.trace.duplicate(true);next.phases=entry.phases.duplicate(true);next.boundaries=entry.boundaries.duplicate(true)
		next.trace.append({"slot":slot,"choice":action.duplicate(true),"outcomes":mapping,"applied":applied})
		next.terminal=Forecast.critical_lost(child);children.append(next)
	limits.branches_created+=needed-1;limits.actions_expanded+=needed
	return {"status":"complete","complete":true,"branches":children}

static func action_variants(b,slot:int,action:Dictionary,limits:Dictionary={}) -> Dictionary:
	var counts:=budget(limits)
	var out:=_expand(_entry(b),slot,action,counts)
	out["budget"]=counts;out["conditional"]=true
	return out

# Takes ownership of entries. Each child re-plans from its own public state;
# renewed lower slots and killed actors change the actual dispatch sequence.
static func _drain_ai(entries:Array,limits:Dictionary) -> Dictionary:
	var pending:Array=entries;var done:Array=[]
	for entry in pending:
		if entry.terminal:continue
		entry.phase_steps=0;entry.board.forecast_meta.phase="ai"
		for u in entry.board.player_units:
			if u.alive and u.control and not u.auto:u.acted=true
	while not pending.is_empty():
		var entry:Dictionary=pending.pop_back();var b=entry.board
		var u=Forecast.next_ai(b)
		if entry.terminal or u==null:
			done.append(entry);continue
		if int(entry.phase_steps)>=int(limits.max_steps):
			pending.append(entry);pending.append_array(done)
			return _failure("incomplete","AI branch step cap",pending,limits)
		# Base.plan changes behavior/home/target, but only on this owned branch.
		var choice:Dictionary=Base.plan(b,u)
		var expanded:=_expand(entry,u.slot,choice,limits)
		if not expanded.complete:
			pending.append(entry);pending.append_array(done)
			var failed:=_failure(expanded.status,expanded.reason,pending,limits)
			failed["unexpanded_at_least"]=expanded.get("unexpanded_at_least",1);return failed
		for child in expanded.branches:
			child.phase_steps=int(entry.phase_steps)+1;pending.append(child)
		b.free()
	return {"status":"complete","complete":true,"branches":done,"budget":limits.duplicate(true)}

static func drain_ai_variants(b,limits:Dictionary={}) -> Dictionary:
	var counts:=budget(limits)
	if counts.max_branches<1:return _failure("incomplete","outcome branch cap",[],counts)
	return _drain_ai([_entry(Forecast.clone_branch(b))],counts)

static func _players(entries:Array,actions:Array,limits:Dictionary) -> Dictionary:
	var current:Array=entries
	for command in actions:
		if not (command is Dictionary) or not (command.get("action",{}) is Dictionary):
			return _failure("invalid","malformed player command",current,limits)
		var next:Array=[]
		while not current.is_empty():
			var entry:Dictionary=current.pop_back()
			if entry.terminal:next.append(entry);continue
			var u=entry.board.unit_by_slot(int(command.get("slot",-1)))
			if u==null or u.side!="player" or not u.control or u.auto:
				current.append(entry);current.append_array(next)
				return _failure("invalid","player permissions/actor unavailable",current,limits)
			var expanded:=_expand(entry,u.slot,command.get("action",{}),limits)
			if not expanded.complete:
				current.append(entry);current.append_array(next)
				var failed:=_failure(expanded.status,expanded.reason,current,limits)
				failed["unexpanded_at_least"]=expanded.get("unexpanded_at_least",1);return failed
			next.append_array(expanded.branches);entry.board.free()
		current=next
	return {"status":"complete","complete":true,"branches":current}

# A fixed second plan is a STRONGER witness than adaptive forall/exists search.
# Invalid in any reachable branch => not a witness. This API does not pretend
# one favorable branch or an unexpanded candidate demonstrates survival.
static func evaluate_two_phases_fixed(source,first:Array,second:Array,known_mine_tiles:Array=[],limits:Dictionary={}) -> Dictionary:
	var out:Dictionary={"complete":false,"status":"invalid","conditional":true,"conditional_survival":false,
		"assumption":"no-future-script-change; supplied-public-mines-only; no-loot-or-relationship-lookahead",
		"policy":"fixed-first-and-second; universal-conditional-outcomes","leaves":[]}
	var valid:=Forecast.validate_public_source(source)
	if not valid.complete:out.merge(valid,true);return out
	var counts:=budget(limits)
	if counts.max_branches<1:out.status="incomplete";out["reason"]="outcome branch cap";return out
	var entries:Array=[_entry(Forecast.clone_public_board(source,known_mine_tiles))]
	for actions in [first,second]:
		var played:=_players(entries,actions,counts)
		if not played.complete:out.merge(played,true);return out
		var drained:=_drain_ai(played.branches,counts)
		if not drained.complete:out.merge(drained,true);return out
		entries=drained.branches
		for entry in entries:
			if entry.get("terminal_recorded",false):continue
			entry.phases.append(Forecast.snapshot(entry.board))
			if entry.terminal:entry["terminal_recorded"]=true
			if entry.phases.size()==1 and not entry.terminal:
				var advanced:=Forecast.advance_public_round(entry.board)
				if not advanced.complete:
					var failed:=_failure(advanced.status,advanced.reason,entries,counts);out.merge(failed,true);return out
				entry.boundaries.append(Forecast.snapshot(entry.board));entry.terminal=Forecast.critical_lost(entry.board)
				if entry.terminal:entry["terminal_recorded"]=true
	var all_alive:=true
	for entry in entries:
		all_alive=all_alive and not entry.terminal
		out.leaves.append({"terminal":entry.terminal,"phases":entry.phases,"boundaries":entry.boundaries,"trace":entry.trace,
			"state":Forecast.snapshot(entry.board)})
	dispose(entries);out.status="complete";out.complete=true;out["all_critical_alive"]=all_alive
	out.conditional_survival=all_alive;out["budget"]=counts
	return out

static func _clone_entry(entry:Dictionary) -> Dictionary:
	var cloned:Dictionary=entry.duplicate(false)
	cloned.board=Forecast.clone_branch(entry.board)
	for field in ["trace","phases","boundaries"]:cloned[field]=entry[field].duplicate(true)
	return cloned

# forall(first outcomes) exists(second supplied candidate) forall(its outcomes).
# The generator receives a DISPOSABLE public branch, never the search-owned
# node or the live source. It may generate different finite plans per result.
# Failure is scoped to that candidate set, not all legal game strategies.
static func evaluate_two_phases_adaptive(source,first:Array,candidate_generator:Callable,known_mine_tiles:Array=[],limits:Dictionary={}) -> Dictionary:
	var out:Dictionary={"complete":false,"status":"invalid","conditional":true,"conditional_survival":false,
		"assumption":"no-future-script-change; supplied-public-mines-only; no-loot-or-relationship-lookahead",
		"policy":"forall-first-outcomes/exists-finite-second-plan/forall-second-outcomes", "witnesses":[],"rejected":[]}
	var valid:=Forecast.validate_public_source(source)
	if not valid.complete:out.merge(valid,true);return out
	if not candidate_generator.is_valid():out["reason"]="no candidate generator";return out
	var counts:=budget(limits)
	if counts.max_branches<1:out.status="incomplete";out["reason"]="outcome branch cap";return out
	var played:=_players([_entry(Forecast.clone_public_board(source,known_mine_tiles))],first,counts)
	if not played.complete:out.merge(played,true);return out
	var drained:=_drain_ai(played.branches,counts)
	if not drained.complete:out.merge(drained,true);return out
	var entries:Array=drained.branches
	for entry in entries:
		entry.phases.append(Forecast.snapshot(entry.board))
		if not entry.terminal:
			var advanced:=Forecast.advance_public_round(entry.board)
			if not advanced.complete:
				out.merge(_failure(advanced.status,advanced.reason,entries,counts),true);return out
			entry.boundaries.append(Forecast.snapshot(entry.board));entry.terminal=Forecast.critical_lost(entry.board)
	for ordinal in range(entries.size()):
		var entry:Dictionary=entries[ordinal]
		if entry.terminal:
			out["counterexample"]={"first_outcome":ordinal,"state":Forecast.snapshot(entry.board),"trace":entry.trace}
			out.merge(_failure("infeasible","critical casualty before second decision",entries,counts),true);return out
		var public_input=Forecast.clone_branch(entry.board)
		var candidates=candidate_generator.call(public_input)
		public_input.free()
		if not (candidates is Array):
			out.merge(_failure("invalid","candidate generator must return an array of action sequences",entries,counts),true);return out
		var witnessed:=false;var unknown_status:="";var unknown_reason:=""
		for candidate_index in range(candidates.size()):
			if int(counts.candidates_expanded)>=int(counts.max_candidates):
				unknown_status="incomplete";unknown_reason="second candidate cap";break
			counts.candidates_expanded+=1
			var actions=candidates[candidate_index]
			if not (actions is Array):
				out.merge(_failure("invalid","candidate is not an action sequence",entries,counts),true);return out
			var next_played:=_players([_clone_entry(entry)],actions,counts)
			var next_drained:Dictionary=next_played
			if next_played.complete:next_drained=_drain_ai(next_played.branches,counts)
			if not next_drained.complete:
				out.rejected.append({"first_outcome":ordinal,"candidate":candidate_index,"status":next_drained.status,"reason":next_drained.reason})
				if next_drained.status in ["incomplete","unsupported"]:
					unknown_status=next_drained.status;unknown_reason=next_drained.reason
				if next_drained.status=="incomplete":break # global work budget cannot be reset by another candidate
				continue
			var all_alive:=true
			for leaf in next_drained.branches:all_alive=all_alive and not leaf.terminal
			if all_alive:
				var leaves:Array=[]
				for leaf in next_drained.branches:leaves.append({"trace":leaf.trace,"state":Forecast.snapshot(leaf.board)})
				out.witnesses.append({"first_outcome":ordinal,"candidate":candidate_index,"actions":actions.duplicate(true),
					"first_state":entry.phases[0],"boundary":entry.boundaries[0],"second_leaves":leaves})
				witnessed=true
			else:out.rejected.append({"first_outcome":ordinal,"candidate":candidate_index,"status":"critical-casualty","terminal_leaves":next_drained.branches.filter(func(leaf):return leaf.terminal).size()})
			dispose(next_drained.branches)
			if witnessed:break # unused candidates are not reachable outcomes of this witness
		if not witnessed:
			var status:="infeasible";var reason:="no witness in supplied finite candidate set"
			if unknown_status!="":status=unknown_status;reason=unknown_reason
			out.merge(_failure(status,reason,entries,counts),true);return out
	dispose(entries);out.status="complete";out.complete=true;out.conditional_survival=true;out["budget"]=counts
	return out
