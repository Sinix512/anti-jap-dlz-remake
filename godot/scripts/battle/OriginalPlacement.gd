extends RefCounted

# 447390, shared by 43B3E2 deployment and 429CC8 reinforcements.
# Occupancy/bounds only: neither terrain nor a wider/global fallback is native.
const OFFSETS := [Vector2i(0,0),Vector2i(0,-1),Vector2i(0,1),Vector2i(-1,0),Vector2i(1,0),Vector2i(-1,-1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(1,1),Vector2i(0,-2),Vector2i(0,2),Vector2i(-2,0),Vector2i(2,0),Vector2i(-1,-2),Vector2i(1,-2),Vector2i(-2,-1),Vector2i(2,-1),Vector2i(-2,1),Vector2i(2,1),Vector2i(-1,2),Vector2i(1,2),Vector2i(-2,-2),Vector2i(2,-2),Vector2i(-2,2),Vector2i(2,2)]

static func find_cell(origin: Vector2i, size: Vector2i, occupied: Dictionary) -> Vector2i:
	for offset in OFFSETS:
		var tile: Vector2i = origin + offset
		if tile.x >= 0 and tile.y >= 0 and tile.x < size.x and tile.y < size.y and not occupied.has(tile):
			return tile
	return Vector2i(-1,-1)
