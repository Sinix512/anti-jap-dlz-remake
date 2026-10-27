extends RefCounted
# Conservative probe boundary, NOT the implementation of hidden-route play.
# Never invent the next battle from an incremented index after a native ending.
static func inspect(index:int,ending_active:bool,live_index:=-1,visit:Dictionary={}) -> Dictionary:
	var reason:=""
	if ending_active:reason="native ending/choice/finale requires real input; no synthetic next level"
	elif index<0 or index>=47:reason="level index outside original resources"
	elif visit.has("easter"):reason="resident interlude requires its real launch; do not ignore one-shot event"
	elif live_index>=0 and live_index!=index:reason="live battle and persistent route index disagree"
	elif index>=36 and live_index!=index:reason="hidden/interlude entry not established by live Campaign route"
	return {"can_launch":reason.is_empty(),"index":index,"live_index":live_index,"reason":reason,"resident":visit.duplicate(true)}
