extends RefCounted
# Adapter boundary: original five-slot presentation, remake JSON continuation.
# Native 57 strategic files are accepted. Native150 is deliberately not faked.
const GBK=preload("res://scripts/m2/GBK.gd")
static func native_path(state,slot:int) -> String:
	# Isolated QA prefixes must not overwrite user-owned native slots.
	var prefix:String=str(state.meta().get("save_prefix","dlz_m2_save_"))
	return "user://save%d.dat"%slot if prefix=="dlz_m2_save_" else "user://%snative%d.dat"%[prefix,slot]
static func previews(state) -> Array:
	var rows:Array=[]
	for slot in range(5):
		var info:Dictionary=state.slot_info(slot)
		if not info.is_empty():
			var idx:int=int(info.get("campaign_index",0));var level:Dictionary=state.m4_level(idx)
			var intro:=GBK.decode(str(level.get("intro_hex","")).hex_decode().slice(0,32))
			var resume:Dictionary=info.get("battle_resume",{})
			rows.append({"mode":150 if not resume.is_empty() else 57,"level":idx,"difficulty":int(info.get("difficulty",1)),"turn":int(resume.get("snapshot",{}).get("turn",info.get("battle_turn",1))),"intro":intro});continue
		var path:=native_path(state,slot)
		if FileAccess.file_exists(path):
			var f:=FileAccess.open(path,FileAccess.READ)
			var raw:=f.get_buffer(48);f.close()
			if raw.size()>=48:rows.append({"mode":raw.decode_u32(0),"level":raw.decode_u32(4),"difficulty":raw.decode_u32(8),"turn":raw.decode_u32(12),"intro":GBK.decode(raw.slice(16,48))});continue
		rows.append({})
	return rows
static func load_slot(state,slot:int) -> bool:
	if not state.slot_info(slot).is_empty():return state.load_slot(slot)
	return state.load_original(native_path(state,slot))
static func save_strategy_native(state,slot:int) -> bool:
	return state.save_original(native_path(state,slot))
