extends RefCounted

# Pure indexed buffers; no alpha/gamma/nearest-color approximation in the mix.
static var _lut := PackedByteArray()
static var _army := PackedByteArray()
static var _box := PackedByteArray()
static var _mine := PackedByteArray()
static var _maps: Dictionary = {}

static func image_bytes(path:String) -> PackedByteArray:
	var image:Image=(load(path) as Texture2D).get_image()
	image.convert(Image.FORMAT_L8)
	return image.get_data()

static func sources(map_path:String) -> Dictionary:
	if _lut.is_empty():_lut=image_bytes("res://assets/palette/death_lut.png")
	if _army.is_empty():_army=image_bytes("res://assets/palette/army_index.png")
	if _box.is_empty():_box=image_bytes("res://assets/palette/box_index.png")
	if _mine.is_empty():_mine=image_bytes("res://assets/palette/mine_index.png")
	if not _maps.has(map_path):_maps[map_path]=image_bytes(map_path)
	return {"lut":_lut,"army":_army,"box":_box,"mine":_mine,"map":_maps[map_path]}

static func army_frame(state:int,direction:int,counter:int) -> int:
	if state==1:return 2+2*posmod(direction,4)+posmod(counter,2)
	if state==2:return 10+2*posmod(direction,4)+posmod(counter,2)
	if state==3:return 18
	return posmod(direction,2)

static func overlay_indices(dest:PackedByteArray,src:PackedByteArray,width:int,height:int,offset:=Vector2i.ZERO,start:=0,stride:=0) -> void:
	if stride==0:stride=width
	for y in range(height):
		for x in range(width):
			var index:int=src[start+y*stride+x]
			if index!=0:dest[(offset.y+y)*48+offset.x+x]=index

static func tile_buffers(map:PackedByteArray,map_width:int,tile:Vector2i,army:PackedByteArray,group:int,frame:int,layers:Dictionary={}) -> Dictionary:
	var background:=PackedByteArray();background.resize(2304)
	# army_index is a raster 912px wide with one 19-frame group per 48 rows.
	# ARMY.DAT itself is frame-major, so its generator explicitly rearranges it.
	for y in range(48):
		for x in range(48):
			var p:=y*48+x
			background[p]=map[(tile.y*48+y)*map_width*48+tile.x*48+x]
			if layers.get("dark",false):background[p]=layers.dark_lut[background[p]]
	# Only the map is darkened. First matching box, then16px mine, then unit.
	for box in layers.get("chests",[]):
		if int(box.x)!=tile.x or int(box.y)!=tile.y:continue
		var box_frame:=int(box.get("appearance",0))*2+(1 if bool(box.get("opened",false)) or int(box.get("wupin",-1))<0 else 0)
		overlay_indices(background,layers.box,48,48,Vector2i.ZERO,box_frame*2304)
		break
	if layers.get("mine_present",false):overlay_indices(background,layers.mine,16,16,Vector2i(16,16))
	var before:=background.duplicate()
	overlay_indices(before,army,48,48,Vector2i.ZERO,group*48*912+frame*48,912)
	if int(layers.get("behavior",0))==11:
		var glyph:PackedByteArray=layers.get("luan_glyph",PackedByteArray())
		if glyph.size()==32:
			for y in range(16):
				for x in range(16):
					if glyph[y*2+x/8] & (128>>(x%8)):before[(y+16)*48+x+16]=0xB7
	return {"old":before,"new":background}

static func frame_indices(old:PackedByteArray,next:PackedByteArray,frame:int,lut:PackedByteArray) -> PackedByteArray:
	var result:=PackedByteArray();result.resize(old.size())
	for p in range(old.size()):result[p]=lut[frame*65536+int(old[p])*256+int(next[p])]
	return result

static func final_indices(last:PackedByteArray,next:PackedByteArray) -> PackedByteArray:
	var result:=last.duplicate()
	for p in range(next.size()):
		if next[p]!=0:result[p]=next[p]
	return result

static func rgba(indices:PackedByteArray,palette:Array,width:=48,height:=48) -> Image:
	var bytes:=PackedByteArray();bytes.resize(indices.size()*4)
	for p in range(indices.size()):
		var index:int=indices[p]*3
		for c in range(3):bytes[p*4+c]=int(palette[index+c])
		bytes[p*4+3]=255
	return Image.create_from_data(width,height,false,Image.FORMAT_RGBA8,bytes)
