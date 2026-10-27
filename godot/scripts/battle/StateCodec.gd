extends RefCounted

# Godot JSON represents every number as float; Array.has/find use strict types.
# All original DAT counters/IDs/slots are integral. Normalize at every JSON boundary,
# otherwise a loaded [0.0,...] bag is incorrectly considered full by find(0).
static func integers(value: Variant) -> Variant:
	if value is float and value == int(value): return int(value)
	if value is Dictionary:
		for key in value: value[key] = integers(value[key])
	elif value is Array:
		for index in range(value.size()): value[index] = integers(value[index])
	return value

# JSON cannot preserve Vector2i or integer dictionary keys. Only tag those values;
# ordinary resource dictionaries remain readable and are never stringified as code.
static func pack(value: Variant) -> Variant:
	if value is Vector2i: return {"@dlz":"v2i","xy":[value.x,value.y]}
	if value is Vector2: return {"@dlz":"v2","xy":[value.x,value.y]}
	if value is Dictionary:
		var has_keys := false
		for key in value:
			if not key is String:
				has_keys = true
				break
		if has_keys:
			var pairs: Array = []
			for key in value:pairs.append([pack(key),pack(value[key])])
			return {"@dlz":"pairs","values":pairs}
		var out := {}
		for key in value:out[key] = pack(value[key])
		return out
	if value is Array:
		var out: Array = []
		for item in value: out.append(pack(item))
		return out
	return value

static func unpack(value: Variant) -> Variant:
	if value is float and value == int(value): return int(value)
	if value is Dictionary:
		match str(value.get("@dlz","")):
			"v2i": return Vector2i(int(value.xy[0]),int(value.xy[1]))
			"v2": return Vector2(float(value.xy[0]),float(value.xy[1]))
			"pairs":
				var out := {}
				for pair in value.values:
					var key: Variant = unpack(pair[0])
					if key is float and key == int(key): key = int(key)
					out[key] = unpack(pair[1])
				return out
		var out := {}
		for key in value: out[key] = unpack(value[key])
		return out
	if value is Array:
		var out: Array = []
		for item in value: out.append(unpack(item))
		return out
	return value
