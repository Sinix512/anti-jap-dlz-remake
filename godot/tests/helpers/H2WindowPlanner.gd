extends RefCounted
# Isolated test-player policy; public model only. Never executes a live action.
const Candidates=preload("res://tests/helpers/ForecastCandidateSet.gd")
const Public=preload("res://tests/helpers/PublicRoundForecast.gd")
const Outcomes=preload("res://tests/helpers/PublicOutcomeTree.gd")
const Legacy=preload("res://tests/helpers/TacticalForecast.gd")
const Geometry=preload("res://tests/helpers/TacticalPlanner.gd")
const DEFAULTS={"first":6,"candidates":24,"branches":64,"actions":2048,"phase_steps":256,
	"h1":256,"collections":256,"preflights":1024}

static func action_key(a:Dictionary) -> String:
	return str([a.get("kind",""),a.get("station"),a.get("tile"),a.get("skill",-1),a.get("item",-1),a.get("target",-1)])

static func _h1_score(b,slot:int,a:Dictionary,cost:int) -> int:
	if int(b.level.index)==7 and slot not in [0,2,3,6,7]:return int(a.get("utility",0))*2-cost*2/3
	return int(a.get("utility",0))-cost

static func _immediate_risk(board,u,tile:Vector2i) -> int:
	# Geometry was written for linear live lookup. PublicBoard caches occupancy;
	# place AND restore that cache locally without changing the legacy policy.
	var old:=Vector2i(u.x,u.y);u.x=tile.x;u.y=tile.y
	board.refresh_occupancy()
	var risk:int=Geometry.immediate_risk(board,u,tile)
	u.x=old.x;u.y=old.y;board.refresh_occupancy()
	return risk

static func _first_candidates(b,u,generator,counts:Dictionary) -> Dictionary:
	var offered:Dictionary=generator.generate(b,u);var ranked:Array=[];var cache:Dictionary={}
	for a in offered.shortlist:
		var key:=action_key(a)
		if not cache.has(key):
			if counts.h1>=counts.max_h1:return {"complete":false,"reason":"H1 ranking cap","ranked":[],"selected":[]}
			cache[key]=Legacy.evaluate(b,u.slot,a);counts.h1+=1
		var prediction:Dictionary=cache[key]
		ranked.append({"action":a.duplicate(true),"h1_score":_h1_score(b,u.slot,a,int(prediction.cost)),"cost":int(prediction.cost),"ordinal":ranked.size()})
	ranked.sort_custom(func(a,c):return a.h1_score>c.h1_score or (a.h1_score==c.h1_score and a.ordinal<c.ordinal))
	var selected:Array=[];var seen:Dictionary={}
	for row in ranked.slice(0,4):
		var key:=action_key(row.action)
		if not seen.has(key):selected.append(row);seen[key]=true
	var origin:=Vector2i(u.x,u.y)
	var wait:Dictionary={"kind":"wait","station":origin,"tile":origin,"utility":0}
	var all_waits:Array=offered.candidates.filter(func(a):return a.kind=="wait")
	all_waits.append(wait);var lowest:Dictionary={};var lowest_cost:=2147483647
	for a in all_waits:
		var key:=action_key(a)
		if not cache.has(key):
			if counts.h1>=counts.max_h1:return {"complete":false,"reason":"H1 retreat cap","ranked":ranked,"selected":[]}
			cache[key]=Legacy.evaluate(b,u.slot,a);counts.h1+=1
		if int(cache[key].cost)<lowest_cost:
			lowest_cost=int(cache[key].cost);lowest={"action":a.duplicate(true),"h1_score":_h1_score(b,u.slot,a,lowest_cost),"cost":lowest_cost,"ordinal":ranked.size()}
	for row in [{"action":wait,"h1_score":_h1_score(b,u.slot,wait,int(cache[action_key(wait)].cost)),"cost":int(cache[action_key(wait)].cost),"ordinal":ranked.size()},lowest]:
		var key:=action_key(row.action)
		if not seen.has(key):selected.append(row);seen[key]=true
	return {"complete":true,"ranked":ranked,"selected":selected}

static func _second_plans(public,generator,counts:Dictionary) -> Array:
	var plans:Array=[];var seen:Dictionary={}
	for mode in ["recover","retreat","utility","wait"]:
		var board=Public.clone_branch(public);var actions:Array=[];var valid:=true
		var actors:Array=board.player_units.filter(func(u):return u.alive and u.control and not u.auto and not u.acted)
		actors.sort_custom(func(a,c):return (a.y>c.y if a.y!=c.y else a.slot<c.slot) if a.slot!=0 and c.slot!=0 else c.slot==0)
		for u in actors:
			if not u.alive or u.acted:continue
			if counts.collections>=counts.max_collections:
				counts.truncated=true;valid=false;break
			counts.collections+=1
			var offered:Dictionary=generator.generate(board,u)
			var available:Array=[];var origin:=Vector2i(u.x,u.y)
			for a in offered.candidates+offered.shortlist:
				var supported:bool=a.kind in ["wait","attack","skill","item"]
				if mode in ["retreat","wait"]:supported=a.kind=="wait" and (mode!="wait" or a.station==origin)
				if not supported:continue
				var support:bool=(a.kind=="skill" and int(a.get("skill",-1)) in [0,1,2]) or (a.kind=="item" and int(a.get("item",-1))<21)
				var risk:int=_immediate_risk(board,u,a.station) if mode in ["recover","retreat"] else 0
				var priority:int=(1000000 if support else 0)+int(a.get("utility",0))-risk*100 if mode=="recover" else (-risk*100+int(a.get("utility",0)) if mode=="retreat" else int(a.get("utility",0)))
				available.append({"action":a,"priority":priority,"ordinal":available.size()})
			available.sort_custom(func(a,c):return a.priority>c.priority or (a.priority==c.priority and a.ordinal<c.ordinal))
			var chosen:Dictionary={};var used:Dictionary={}
			for row in available:
				var a:Dictionary=row.action;var key:=action_key(a)
				if used.has(key):continue
				used[key]=true
				if counts.preflights>=counts.max_preflights:counts.truncated=true;break
				counts.preflights+=1
				# Strict transaction: uncertain player rolls cannot be used to
				# invent the intermediate board used to generate later actions.
				var applied:=Public.apply_action(board,u,a)
				if applied.complete:chosen=a;break
			if chosen.is_empty():valid=false;break
			actions.append({"slot":u.slot,"action":chosen.duplicate(true)})
		board.free()
		if valid:
			var key:=str(actions)
			if not seen.has(key):plans.append(actions);seen[key]=true;counts.plans+=1
		if counts.truncated:break
	return plans

static func _metrics(evaluation:Dictionary,initial_losses:int) -> Dictionary:
	var losses:=initial_losses;var critical_ratio:=1000000
	for witness in evaluation.witnesses:
		var states:Array=[witness.first_state,witness.boundary]
		for leaf in witness.second_leaves:states.append(leaf.state)
		for state in states:
			losses=maxi(losses,int(state.stats.get("losses",0)))
			for slot in state.units:
				var u:Dictionary=state.units[slot]
				if int(slot)==0 or u.protected:critical_ratio=mini(critical_ratio,int(u.hp)*1000000/maxi(1,int(u.max_hp)))
	return {"losses":losses-initial_losses,"critical_ratio":critical_ratio}

static func choose(source,slot:int,limits:Dictionary={},known_mine_tiles:Array=[]) -> Dictionary:
	var started:=Time.get_ticks_usec();var caps:Dictionary=DEFAULTS.duplicate(true);caps.merge(limits,true)
	for key in DEFAULTS:caps[key]=clampi(int(caps[key]),0,int(DEFAULTS[key]))
	var output:Dictionary={"status":"invalid","conditional_survival":false,"candidates":[],"choice":{},"elapsed_usec":0,
		"scope":"L08 T1-8 isolated policy only; no future scripts; public mines only; no original RNG"}
	var valid:=Public.validate_public_source(source)
	if not valid.complete:output.merge(valid,true);return output
	if int(source.level.get("index",-1))!=8 or source.turn<1 or source.turn>8:
		output.reason="outside predetermined H2 window";return output
	var b=Public.clone_public_board(source,known_mine_tiles);var u=b.unit_by_slot(slot)
	if u==null or u.acted or not u.control or u.auto or u.side!="player":b.free();output.reason="actor unavailable";return output
	var generator=Candidates.new()
	var generated:Dictionary={"h1":0,"collections":0,"preflights":0,"plans":0,"truncated":false,
		"max_h1":maxi(0,int(caps.h1)),"max_collections":maxi(0,int(caps.collections)),"max_preflights":maxi(0,int(caps.preflights))}
	var offered:=_first_candidates(b,u,generator,generated)
	if not offered.ranked.is_empty():output.choice=offered.ranked[0].action.duplicate(true)
	if not offered.complete:
		b.free();output.status="incomplete";output.reason=offered.reason;output.generation=generated;output.elapsed_usec=Time.get_ticks_usec()-started;return output
	var totals:Dictionary={"branches":0,"actions":0,"candidates":0};var best:Dictionary={}
	for index in range(offered.selected.size()):
		var row:Dictionary=offered.selected[index]
		if index>=maxi(0,int(caps.first)):
			output.candidates.append({"status":"incomplete","reason":"first candidate cap","action":row.action});continue
		var remaining:Dictionary={"branches":maxi(0,int(caps.branches)-int(totals.branches)),"actions":maxi(0,int(caps.actions)-int(totals.actions)),
			"candidates":maxi(0,int(caps.candidates)-int(totals.candidates)),"phase_steps":maxi(0,int(caps.phase_steps))}
		if remaining.branches==0 or remaining.actions==0 or remaining.candidates==0 or generated.truncated:
			output.candidates.append({"status":"incomplete","reason":"shared decision budget","action":row.action});continue
		var factory:=func(public):return _second_plans(public,generator,generated)
		var evaluation:=Outcomes.evaluate_two_phases_adaptive(b,[{"slot":slot,"action":row.action}],factory,known_mine_tiles,remaining)
		var used:Dictionary=evaluation.get("budget",{})
		totals.branches+=int(used.get("branches_created",0));totals.actions+=int(used.get("actions_expanded",0));totals.candidates+=int(used.get("candidates_expanded",0))
		if generated.truncated:evaluation.status="incomplete";evaluation.complete=false;evaluation.conditional_survival=false;evaluation.reason="second plan generation cap"
		var candidate:Dictionary={"action":row.action,"h1_score":row.h1_score,"h1_cost":row.cost,"status":evaluation.status,
			"conditional_survival":evaluation.conditional_survival,"reason":evaluation.get("reason",""),"used":used.duplicate(true)}
		if evaluation.complete and evaluation.conditional_survival:
			candidate.metrics=_metrics(evaluation,int(source.stats.get("losses",0)))
			if best.is_empty() or candidate.metrics.losses<best.metrics.losses or (candidate.metrics.losses==best.metrics.losses and
				(candidate.metrics.critical_ratio>best.metrics.critical_ratio or (candidate.metrics.critical_ratio==best.metrics.critical_ratio and candidate.h1_score>best.h1_score))):best=candidate
		output.candidates.append(candidate)
	b.free()
	if not best.is_empty():output.choice=best.action.duplicate(true);output.status="complete";output.conditional_survival=true;output.metrics=best.metrics
	else:output.status="no-witness";output.reason="fallback old H1; no complete conditional continuation witness"
	output.totals=totals;output.generation=generated;output.elapsed_usec=Time.get_ticks_usec()-started
	return output
