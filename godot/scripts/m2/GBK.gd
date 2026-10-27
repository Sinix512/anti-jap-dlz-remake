extends RefCounted

static var forward: Dictionary = {}
static var reverse: Dictionary = {}

static func _init_tables() -> void:
	if not forward.is_empty(): return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/gbk_codec.json"))
	if parsed is Dictionary: forward = parsed
	for char in forward: reverse[str(forward[char])] = char

static func encode(text: String, limit: int = 16) -> PackedByteArray:
	_init_tables()
	var out := PackedByteArray()
	for char in text:
		var raw := PackedByteArray()
		if char.unicode_at(0) < 128: raw.append(char.unicode_at(0))
		elif forward.has(char): raw = str(forward[char]).hex_decode()
		else:
			push_warning("原版GBK不支持字符：" + char)
			raw.append(63)
		if out.size() + raw.size() >= limit: break
		out.append_array(raw)
	out.resize(limit)
	return out

static func decode(raw: PackedByteArray) -> String:
	_init_tables()
	var out := ""
	var index := 0
	while index < raw.size() and raw[index] != 0:
		if raw[index] < 128:
			out += String.chr(raw[index])
			index += 1
		elif index + 1 < raw.size():
			out += str(reverse.get(raw.slice(index,index+2).hex_encode(),"？"))
			index += 2
		else: break
	return out
