extends RefCounted
# UI index rasters always use the caller's live palette.
static var palettes:Dictionary={}
static func colors(key:String) -> Array:
	if palettes.is_empty():palettes=JSON.parse_string(FileAccess.get_file_as_string("res://data/native_ui_palettes.json"))
	return palettes.get(key,palettes.KUANG04)
static func color_at(palette:Array,index:int) -> Color:
	return Color8(int(palette[index*3]),int(palette[index*3+1]),int(palette[index*3+2]))
static func texture(raw:PackedByteArray,width:int,height:int,palette:Array,key:=-1) -> ImageTexture:
	var rgba:=PackedByteArray();rgba.resize(width*height*4)
	for i in range(width*height):
		var index:int=raw[i]*3
		rgba[i*4]=int(palette[index]);rgba[i*4+1]=int(palette[index+1]);rgba[i*4+2]=int(palette[index+2]);rgba[i*4+3]=0 if raw[i]==key else 255
	return ImageTexture.create_from_image(Image.create_from_data(width,height,false,Image.FORMAT_RGBA8,rgba))

static func asset(name:String,width:int,height:int,palette:Array,key:=-1) -> ImageTexture:
	return texture(FileAccess.get_file_as_bytes("res://assets/ui/"+name+"_indices.bin"),width,height,palette,key)

static func selected(raw:PackedByteArray,width:int,rect:Rect2i,palette:Array) -> ImageTexture:
	var lut:=FileAccess.get_file_as_bytes("res://assets/ui/native_menu_lut.bin")
	var pixels:=PackedByteArray();pixels.resize(rect.size.x*rect.size.y)
	for y in range(rect.size.y):
		for x in range(rect.size.x):pixels[y*rect.size.x+x]=lut[raw[(rect.position.y+y)*width+rect.position.x+x]]
	return texture(pixels,rect.size.x,rect.size.y,palette)
