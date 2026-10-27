extends SceneTree
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("INFO_LAYOUT_FAIL "+label)
func at(info,point:Vector2) -> String:
	for node in info.canvas.get_children():
		if node is Label and node.position==point:return node.text
	return ""
func run() -> void:
	var data:Dictionary=preload("res://scripts/battle/StateCodec.gd").integers(JSON.parse_string(FileAccess.get_file_as_string("res://data/m2.json")))
	var font_ref=load("res://assets/font/hzk16.fnt")
	for id in range(156):
		var info=load("res://scripts/ui/OriginalInfo.gd").new();root.add_child(info)
		info.setup(font_ref,data,"item",id);await process_frame
		var labels:Array=[]
		for node in info.canvas.get_children():
			if node is Label and not node.text.is_empty():labels.append(node)
		var conflicts:Array=[]
		for index in range(labels.size()):
			var first=labels[index]
			var first_size:Vector2=font_ref.get_string_size(first.text,HORIZONTAL_ALIGNMENT_LEFT,-1,16)
			var rect:=Rect2(first.position,Vector2(first_size.x,16)).grow(-0.5)
			if not Rect2(80,60,480,360).encloses(rect):conflicts.append("outside "+first.text)
			for other in labels.slice(index+1):
				var size_:Vector2=font_ref.get_string_size(other.text,HORIZONTAL_ALIGNMENT_LEFT,-1,16)
				if rect.intersects(Rect2(other.position,Vector2(size_.x,16)).grow(-0.5)):conflicts.append(first.text+" / "+other.text)
		check(conflicts.is_empty(),"item%d text bounds and overlap: %s"%[id,str(conflicts)])
		if id>=68 and id<=80:
			var source:Dictionary={}
			for key in data.units:
				var cls:Dictionary=data.units[key]
				if int(key)>=1 and int(key)<=22 and int(cls.get("zhuanzhidaoju",-1))==id:source=cls;break
			check(at(info,Vector2(204,156))==str(source.get("name","")) and at(info,Vector2(308,156))==str(data.units[str(source.zhuanzhi)].name),"upgrade%d original source/target class labels"%id)
		if id in [1,31,36,61,75,81]:
			var y:=192 if id in [61,75] else (228 if id in [1,31] else 260)
			check(at(info,Vector2(184,y))=="适用兵种：","item%d original compatibility heading"%id)
		info.close();await process_frame
	print("ORIGINAL_INFO_LAYOUT checks=",checks," failures=",failures)
	quit(1 if failures else 0)
