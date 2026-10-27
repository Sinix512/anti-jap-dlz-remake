extends RefCounted
# Test-player intention only; no resolver, RNG, world/Scenario or state writes.
# One late evacuation stage after early cover, not a safety forecast.
static func decide(turn:int,actor,allies:Array,previous:Dictionary={}) -> Dictionary:
	var out:Dictionary={"active":bool(previous.get("active",false)),"done":bool(previous.get("done",false)),"withdraw":false,"goal":Vector2i(actor.x,actor.y),"support_slot":-1,"distance":-1}
	if out.done or turn<10:return out
	if actor.hp*3<=actor.max_hp*2:out.active=true
	if not out.active:return out
	var nearest=null;var distance:=2147483647
	for ally in allies:
		if not ally.alive or not ally.control or ally.auto or ally.side!="player" or ally.slot<0 or ally.slot>6:continue
		var d:int=absi(actor.x-ally.x)+absi(actor.y-ally.y)
		if d<distance or (d==distance and (nearest==null or ally.slot<nearest.slot)):nearest=ally;distance=d
	if nearest!=null:
		out.support_slot=nearest.slot;out.distance=distance
		if distance<=3:out.active=false;out.done=true;return out
		out.goal=Vector2i(nearest.x,nearest.y)
	out.withdraw=true
	return out
