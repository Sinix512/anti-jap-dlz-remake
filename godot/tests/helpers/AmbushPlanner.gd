extends RefCounted
const Forecast=preload("res://tests/helpers/TacticalForecast.gd")

static func plan(source,actor,explore_lures:=false) -> Dictionary:
	if actor.acted or not actor.alive or not actor.control:return {}
	var codes:Array=[]
	for raw in actor.mine_slots:
		var code:int=int(raw)-1
		if code>=0 and code<10 and not codes.has(code):codes.append(code)
	if codes.is_empty():return {}
	var origin:=Vector2i(actor.x,actor.y)
	var baseline:Dictionary=Forecast.evaluate(source,actor.slot,{"kind":"wait","station":origin})
	var routes:Dictionary={}
	for entry in baseline.plans:
		var enemy=source.unit_by_slot(int(entry.slot))
		if enemy==null or source.same_faction(actor,enemy):continue
		for tile in entry.path:
			if source._unit_at(tile)==null and source._mine_at(tile)<0:routes[tile]=true
	if routes.is_empty() and not explore_lures:return {}
	# Work only on a disposable board; candidate occupancy must not move the
	# actual actor or corrupt the source's movement/predecessor/range workspaces.
	var board=Forecast.copy_board(source)
	var clone=board.unit_by_slot(actor.slot)
	var stations:Array=[] if actor.moved else board.compute_reachable(clone).keys()
	stations.push_front(origin)
	var candidates:Array=[]
	for station in stations:
		var station_routes:Dictionary=routes
		if explore_lures:
			# A waiting gun line has no baseline path. Relocating the planter can
			# invite a real pursuit; predict that visible move before choosing the
			# mine, rather than forcing an enemy to step onto a preselected tile.
			station_routes={}
			var lure:Dictionary=Forecast.evaluate(source,actor.slot,{"kind":"wait","station":station})
			for entry in lure.plans:
				var enemy=source.unit_by_slot(int(entry.slot))
				if enemy==null or source.same_faction(actor,enemy):continue
				for tile in entry.path:
					if source._unit_at(tile)==null and source._mine_at(tile)<0:station_routes[tile]=true
		clone.x=station.x;clone.y=station.y;board.refresh_occupancy()
		for code in codes:
			for tile in board._mine_place_tiles(clone,code):
				if station_routes.has(tile):candidates.append({"kind":"mine","mine":code,"station":station,"tile":tile})
	clone.x=origin.x;clone.y=origin.y;board.refresh_occupancy()
	board.free()
	var chosen:Dictionary={}
	var best:=80 # finite ammunition should achieve more than idle decoration
	for action in candidates:
		var forecast:Dictionary=Forecast.evaluate(source,actor.slot,action)
		if forecast.mine_events.is_empty():continue
		# A different ally already predicted to die while everyone waits must
		# not veto an ambush that saves another life. Do not introduce a new
		# casualty, and never accept the commander's death even in the baseline.
		if not no_new_casualties(baseline.units,forecast.units):continue
		var value:int=int(baseline.cost)-int(forecast.cost)+2*(int(forecast.enemy_loss)-int(baseline.enemy_loss))-int(origin.distance_to(action.station))
		if value>best:best=value;chosen=action.duplicate();chosen.value=value;chosen.prediction=forecast
	return chosen

static func no_new_casualties(baseline:Dictionary,predicted:Dictionary) -> bool:
	for slot in predicted:
		if bool(predicted[slot].alive):continue
		if int(slot)==0 or bool(baseline.get(slot,{"alive":true}).alive):return false
	return true
