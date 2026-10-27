extends RefCounted

## 403F8E/402DDC 原版16行为、31原子命令。只规划，不偷偷改胜负/平衡。
## 证据及已知安全差异见 tools/ai_decision_blueprint.md。
const TABLE = [[2,12,21,31,41,51,61,71,3,13,8,18,0],[1,11,22,42,52,72,61,31,6,16,7,17,0],[1,11,23,22,42,52,72,61,31,5,15,33,0],[23,5,15,33,0],[1,11,22,42,52,72,31,4,14,32,0],[4,14,32,31,41,71,0],[1,11,23,22,42,52,72,61,31,5,15,33,0],[1,11,22,42,52,72,61,31,6,16,7,17,0],[32,0],[2,12,31,61,41,51,21,71,3,13,8,18,0],[1,11,22,31,42,52,72,4,14,32,0],[0],[31,2,12,61,41,51,21,71,3,13,8,18,0],[0],[0],[0]]

static func plan(b, u) -> Dictionary:
	# 行为改变在行动规划前反复执行；不耗行动。
	for iteration in range(8):
		if not b.scenario.ai_prepare(u):
			break
	var reachable: Dictionary = b.compute_reachable(u)
	var stations: Array = reachable.keys()
	stations.sort_custom(func(a, c): return a.y < c.y or (a.y == c.y and a.x < c.x))
	for command in TABLE[int(u.behavior) & 15]:
		var choice := _command(b, u, int(command), stations)
		if not choice.is_empty():
			if int(u.behavior) == 7 and str(choice["kind"]) == "attack":
				u.behavior = 2
				u.target_slot = int(choice["target"])
			return choice
	return {"kind": "wait", "station": Vector2i(u.x, u.y)}


static func _has(b, u, skill: int) -> bool:
	return b._skill_count(u, skill) > 0


static func _heal_skill(b, u, morale: bool) -> int:
	var first := 1 if morale else 0
	if _has(b,u,first): return first
	return 2 if _has(b,u,2) else -1


static func _toward(u, goal: Vector2i, stations: Array) -> Dictionary:
	var current := Vector2i(u.x,u.y)
	var best := absi(current.x-goal.x) + absi(current.y-goal.y)
	var point := current
	for t in stations:
		var d := absi(t.x-goal.x) + absi(t.y-goal.y)
		if d < best:
			best = d
			point = t
	return {"station": point, "improved": point != current}


static func _retreat(b, u, stations: Array) -> Vector2i:
	var attacker = b.unit_by_slot(int(u.data.get("last_attacker_slot", -1)))
	var point := Vector2i(u.x,u.y)
	var best := -1
	if attacker == null: return point
	for t in stations:
		var score := absi(t.x-int(attacker.x)) + absi(t.y-int(attacker.y))
		if b._terrain_at(t) in [9,10,11]: score += 9
		if score > best:
			best = score
			point = t
	return point


static func _targets(b, u, station: Vector2i, skill: int) -> Dictionary:
	# 401708/418A70: the hypothetical station centers only the selection
	# matrix; occupancy still describes the actual, unmoved battlefield. Moving
	# u.x/y here falsely relocates the caster in support/duty target queries.
	var definition:Dictionary={} if skill<0 else b.data["skills"][skill]
	var select_id:int=int(u.select) if skill<0 else int(definition.get("select_fw",1))
	var tid:int=-1 if skill<0 else int(definition.get("type",0))
	var support:bool=tid in [0,1,2,10]
	var force_center:bool=tid in [0,1,2]
	var matrix:Array=b.data.get("select_ranges",{}).get(str(select_id),[])
	var out:Dictionary={}
	if matrix.size()<9:return out
	for y in range(-4,5):
		for x in range(-4,5):
			if int(matrix[y+4][x+4])!=1 and not (force_center and x==0 and y==0):continue
			var tile:=station+Vector2i(x,y)
			if not b._in_bounds(tile):continue
			var target=b._unit_at(tile)
			if target==null or not target.alive:continue
			if support==b.same_faction(target,u):out[tile]=target
	return out


static func _skill_plan(station: Vector2i, sid: int, target) -> Dictionary:
	return {"kind": "skill", "station": station, "skill": sid, "target": int(target.slot)}


static func _command(b, u, command: int, stations: Array) -> Dictionary:
	var current := Vector2i(u.x,u.y)
	if command == 0: return {"kind": "wait", "station": current}
	if (command >= 1 and command <= 6) or (command >= 11 and command <= 16):
		var morale := command >= 11
		var n := command - (10 if morale else 0)
		var sid := _heal_skill(b,u,morale)
		if sid < 0: return {}
		var value: int = u.morale if morale else u.hp
		var maximum: int = 100 if morale else u.max_hp
		if n == 1 and value >= maximum / 4: return {}
		if n == 2 and value >= maximum * 3 / 5: return {}
		if n >= 3 and value == maximum: return {}
		var station := current
		if n in [1,6]: station = _retreat(b,u,stations)
		elif n == 4: station = _toward(u,Vector2i(u.target_x,u.target_y),stations)["station"]
		elif n == 5:
			var target = b.unit_by_slot(u.target_slot)
			if target != null: station = _toward(u,Vector2i(target.x,target.y),stations)["station"]
		return _skill_plan(station,sid,u)
	if command in [7,8,17,18,41,42,51,52,61,62,71,72]:
		var sid := -1
		if command in [7,8,17,18]: sid = _heal_skill(b,u,command >= 17)
		elif command in [41,42]: sid = 13
		elif command in [51,52]: sid = 14
		elif command in [61,62]: sid = 12
		else: sid = 6
		if sid < 0 or not _has(b,u,sid): return {}
		var search: Array = stations if command in [7,17,42,52,62,72] else [current]
		for station in search:
			for target in _targets(b,u,station,sid).values():
				var eligible := true
				if command in [7,8]: eligible = int(target.hp) <= int(target.max_hp) * 4 / 5
				elif command in [17,18]: eligible = int(target.morale) < 81
				elif sid == 12: eligible = bool(target.acted)
				else: eligible = int(target.data.get("zhili",0)) + 5 <= int(u.data.get("zhili",0))
				if eligible: return _skill_plan(station,sid,target)
		return {}
	if command in [21,22,23,31]:
		if command == 31 and not _has(b,u,15): return {}
		var search: Array = stations.duplicate() if command in [22,23] else [current]
		if command == 22: search.append(current)
		var candidates := {}
		for station in search:
			for target in _targets(b,u,station,15 if command == 31 else -1).values():
				if command == 23:
					if int(target.slot) == int(u.target_slot):
						return {"kind":"attack","station":station,"target":int(target.slot)}
					continue
				var power: int = b._effective_attack(u) - b._effective_defense(target)
				if command == 31: power = int(b.data["skills"][15].get("para1",0)) * int(u.data.get("zhili",0)) / 100
				candidates[int(target.slot)] = {"score":maxi(1,power)*10000/maxi(1,int(target.hp)),"station":station,"target":target}
		var slots := candidates.keys()
		slots.sort()
		var best := -1
		var chosen := {}
		for slot in slots:
			var record: Dictionary = candidates[slot]
			if int(record["score"]) > best:
				best = int(record["score"])
				chosen = record
			if int(record["score"]) > 9999: break
		if chosen.is_empty(): return {}
		if command == 31: return _skill_plan(chosen["station"],15,chosen["target"])
		return {"kind":"attack","station":chosen["station"],"target":int(chosen["target"].slot)}
	if command in [32,33]:
		var goal := Vector2i(u.target_x,u.target_y)
		if command == 33:
			var target = b.unit_by_slot(u.target_slot)
			if target == null: return {"kind":"move","station":current}
			goal = Vector2i(target.x,target.y)
		var result := _toward(u,goal,stations)
		if command == 32 and not result["improved"]: return {}
		return {"kind":"move","station":result["station"]}
	return {}
