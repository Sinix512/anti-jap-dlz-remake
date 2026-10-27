extends RefCounted

# 833418: one byte per WORLD tile; zero is both bright and selectable.
# Independent of overlay colors, occupied targets, camera, and current viewport.
static func cleared(width:int,height:int) -> PackedByteArray:
	var mask:=PackedByteArray();mask.resize(width*height);mask.fill(0)
	return mask

static func selection(width:int,height:int,center:Vector2i,matrix:Array,force_self:=false) -> PackedByteArray:
	var mask:=cleared(width,height);mask.fill(1)
	if matrix.size()>=9:
		for dy in range(-4,5):
			for dx in range(-4,5):
				var tile:=center+Vector2i(dx,dy)
				if tile.x>=0 and tile.y>=0 and tile.x<width and tile.y<height:
					mask[tile.y*width+tile.x]=(1-int(matrix[dy+4][dx+4]))&255
	if force_self and center.x>=0 and center.y>=0 and center.x<width and center.y<height:
		mask[center.y*width+center.x]=0
	return mask

static func movement(width:int,height:int,center:Vector2i,reachable:Dictionary) -> PackedByteArray:
	# reachable is the native terrain/ZOC traversal's empty stopping cells, not
	# the visual overlay. Same-faction occupied cells are traversable but dark.
	var mask:=cleared(width,height);mask.fill(1)
	for tile in reachable:
		if tile.x>=0 and tile.y>=0 and tile.x<width and tile.y<height:
			mask[tile.y*width+tile.x]=0
	if center.x>=0 and center.y>=0 and center.x<width and center.y<height:
		mask[center.y*width+center.x]=0
	return mask


static func from_cells(width:int,height:int,bright:Array) -> PackedByteArray:
	var mask:=cleared(width,height);mask.fill(1)
	for tile in bright:
		if tile.x>=0 and tile.y>=0 and tile.x<width and tile.y<height:mask[tile.y*width+tile.x]=0
	return mask

static func mine_geometry(width:int,height:int,center:Vector2i,remote:=false) -> PackedByteArray:
	var bright:Array=[]
	var radius:=5 if remote else 1
	for dy in range(-radius,radius+1):
		for dx in range(-radius,radius+1):
			if dx==0 and dy==0:continue
			if remote and absi(dx)+absi(dy)>5:continue
			bright.append(center+Vector2i(dx,dy))
	return from_cells(width,height,bright)

static func allows(mask:PackedByteArray,width:int,height:int,tile:Vector2i) -> bool:
	return tile.x>=0 and tile.y>=0 and tile.x<width and tile.y<height and mask.size()==width*height and mask[tile.y*width+tile.x]==0

static func cells(mask:PackedByteArray,width:int,height:int) -> Array:
	var out:Array=[]
	for y in range(height):
		for x in range(width):
			if allows(mask,width,height,Vector2i(x,y)):out.append(Vector2i(x,y))
	return out
