extends SceneTree
# Serialization fixtures only. No battle commands, wins, or new save format.
const Codec=preload("res://scripts/battle/StateCodec.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("STATE_CODEC_PACK "+label)
# Frozen prior implementation is an independent byte/order oracle for bounded
# fixtures. Never use it for a deep payload: its duplicate recursion is the bug.
func legacy_pack(value:Variant) -> Variant:
	if value is Vector2i:return {"@dlz":"v2i","xy":[value.x,value.y]}
	if value is Vector2:return {"@dlz":"v2","xy":[value.x,value.y]}
	if value is Dictionary:
		var out:={};var pairs:Array=[];var has_keys:=false
		for key in value:
			if not key is String:has_keys=true
			pairs.append([legacy_pack(key),legacy_pack(value[key])])
			if key is String:out[key]=legacy_pack(value[key])
		return {"@dlz":"pairs","values":pairs} if has_keys else out
	if value is Array:
		var out:Array=[]
		for item in value:out.append(legacy_pack(item))
		return out
	return value
func run() -> void:
	var mixed:Dictionary={1:"int",false:Vector2(2.0,5.5),"string":{3:[4,5]}}
	var named:Dictionary={StringName("slot"):7,StringName("position"):Vector2i(29,8)}
	var samples:Array=[{},[],null,true,false,42,-99,3.5,"plain",Vector2i(-2,7),Vector2(3.5,-4.0),{"empty":{},"nested":{"one":[Vector2i(8,9),{"key":7}]},"@dlz":"ordinary"},mixed,named,[{},mixed,named,Vector2.ZERO]]
	for n in range(samples.size()):
		var before:Variant=samples[n].duplicate(true) if samples[n] is Array or samples[n] is Dictionary else samples[n]
		var prior:Variant=legacy_pack(samples[n]);var actual:Variant=Codec.pack(samples[n])
		check(actual==prior,"packed equality %d"%n)
		check(JSON.stringify(actual)==JSON.stringify(prior),"byte and order equality %d"%n)
		check(Codec.unpack(actual)==Codec.unpack(prior),"roundtrip equality %d"%n)
		check(before==samples[n],"immutable source %d"%n)
	check(Codec.pack({"a":1}).has("a"),"ordinary string-key dictionaries stay ordinary")
	check(Codec.pack(mixed).get("@dlz")=="pairs","numeric keys preserve pair tag")
	check(Codec.pack(named).get("@dlz")=="pairs","StringName keys preserve prior pair tag")
	check(Codec.unpack(JSON.parse_string(JSON.stringify(Codec.pack(mixed)))).has(1),"numeric JSON keys restore as integral variants")
	var deep:Variant=Vector2i(17,-9)
	for i in range(48):deep={"nested":deep}
	var decoded:Variant=Codec.unpack(Codec.pack(deep))
	for i in range(48):decoded=decoded.nested
	check(decoded==Vector2i(17,-9),"48-layer linear pack preserves vector leaf")
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json"))
	var m2:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/m2.json"))
	var level:Dictionary=preload("res://scripts/m4/LevelBuilder.gd").build(data,m2,44,[],false)
	var b=preload("res://scripts/Battle.gd").new();root.add_child(b);b.setup(data,level,load("res://assets/font/hzk16.fnt"));b.set_process(false)
	var snapshot:Dictionary=b.snapshot();var immutable:Dictionary=snapshot.duplicate(true)
	var prior:=JSON.stringify(legacy_pack(snapshot));var actual:=JSON.stringify(Codec.pack(snapshot))
	check(prior==actual,"full original44 synthetic launch snapshot byte-identical")
	check(Codec.unpack(JSON.parse_string(prior))==Codec.unpack(JSON.parse_string(actual)),"full snapshot JSON decode equality")
	var start:=Time.get_ticks_usec()
	for i in range(3):legacy_pack(snapshot)
	var old_usec:=Time.get_ticks_usec()-start
	start=Time.get_ticks_usec()
	for i in range(3):Codec.pack(snapshot)
	var new_usec:=Time.get_ticks_usec()-start
	check(snapshot==immutable,"actual snapshot immutability")
	check(b.turn==1 and not b.finished_flag,"fixture ran no turn or manufactured win")
	var report:Dictionary={"checks":checks,"failures":failures,"scope":"codec format/equivalence fixtures, NOT play acceptance","snapshot_bytes":actual.length(),"old_three_pack_usec":old_usec,"new_three_pack_usec":new_usec}
	var f=FileAccess.open("res://../out/state_codec_pack_test.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close()
	b.queue_free();await process_frame;await process_frame
	root.get_node("Music").release_playback();OriginalUI.release_native_sfx();await create_timer(.2).timeout
	print("STATE_CODEC_PACK checks=",checks," failures=",failures)
	if failures==0:print("STATE_CODEC_PACK PASS")
	quit(1 if failures else 0)
