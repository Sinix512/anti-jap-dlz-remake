extends RefCounted

## block13每镇五字段的原版民房/指挥部状态机。数据附REA证据。
static func get_flag(state, index: int) -> int:
	return int(state.script_globals.get("0x%x" % (0x7d06c8 + index * 4), 0))

static func set_flag(state, index: int, value: int) -> void:
	state.script_globals["0x%x" % (0x7d06c8 + index * 4)] = value

static func apply_rewards(state, rule: Dictionary) -> void:
	for item in rule.get("reward_items", {}):
		state.add_item(int(item), int(rule["reward_items"][item]))
	for kind in rule.get("unlock_mine_types", []):
		state.script_globals["0x%x" % (0x95eb08 + int(kind) * 4)] = 1
	for mode in rule.get("unlock_fuses", []):
		state.script_globals["0x%x" % (0x95eaf8 + int(mode) * 4)] = 1

static func visit_resident(state, town: int) -> Dictionary:
	var scripts: Dictionary = state.m4_data.get("town_scripts", {})
	var messages: Array = []
	var groups := {}
	for rule in scripts.get("resident", {}).get(str(town), []):
		var phase := get_flag(state, town * 5)
		if int(rule["phase"]) != phase:
			continue
		var group := str(rule.get("else_if_group", ""))
		if group != "" and groups.has(group):
			continue
		groups[group] = true
		messages.append_array(rule.get("messages", []))
		set_flag(state, town * 5, int(rule["set_phase"]))
		apply_rewards(state, rule)
	var phase := get_flag(state, town * 5)
	if town == 0:
		if phase == 1:
			return {"messages": messages, "first_deploy": true}
		if randi_range(0, 99) < 30:
			var slots := [3,4,9]
			for i in range(slots.size()):
				if get_flag(state, slots[i]) == 0:
					set_flag(state, slots[i], 1)
					set_flag(state, 91, state.campaign_index)
					state.campaign_index=44+i
					return {"messages": messages, "easter": 44 + i}
	return {"messages": messages}

static func prepare_command(state, town: int) -> Dictionary:
	var phase := get_flag(state, town * 5 + 1)
	var resident := get_flag(state, town * 5)
	var scripts: Dictionary = state.m4_data.get("town_scripts", {})
	for raw in scripts.get("commander", {}).get(str(town), []):
		var rule: Dictionary = raw.duplicate(true)
		if rule.has("phase_in") and not phase in rule["phase_in"]:
			continue
		if rule.has("phase_not_in") and phase in rule["phase_not_in"]:
			continue
		if rule.has("resident_in") and not resident in rule["resident_in"]:
			continue
		if resident in rule.get("resident_not_in", []):
			continue
		var messages: Array = rule.get("messages", []).duplicate()
		messages.append_array(rule.get("messages_if_phase", {}).get(str(phase), []))
		messages.append_array(rule.get("messages_always", []))
		for slot in rule.get("messages_if_block13", {}):
			messages.append_array(rule["messages_if_block13"][slot].get(str(get_flag(state, int(slot))), []))
		for slot in rule.get("enter_recruit", []):
			state.set_person_side(int(slot), 0)
		if rule.get("set_phase_before_choice") != null:
			set_flag(state, town * 5 + 1, int(rule["set_phase_before_choice"]))
		rule["messages"] = messages
		return rule
	return {"no_choice": true, "messages": []}

static func accept_command(state, town: int, rule: Dictionary, choice := 0) -> Dictionary:
	var accept: Dictionary = rule.get("accept", {})
	if accept.has("set_phase"):
		set_flag(state, town * 5 + 1, int(accept["set_phase"]))
	for slot in accept.get("recruit", []):
		state.set_person_side(int(slot), 0)
	if rule.get("accept_extra", {}).has("set_resident_phase"):
		set_flag(state, town * 5, int(rule["accept_extra"]["set_resident_phase"]))
	if bool(accept.get("direct_solo_battle", false)):
		set_flag(state, 2, choice)
		var options: Array = rule.get("choice_options", [])
		return {"solo": int(options[clampi(choice,0,options.size()-1)]["battle_slot"])}
	return {"deploy": bool(accept.get("deploy", false))}
