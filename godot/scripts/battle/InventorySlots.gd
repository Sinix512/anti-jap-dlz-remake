extends RefCounted

## Original eight-byte bags: 428F8B/4290F8 preserve nonzero order.
## Removal receives an ID, not the UI slot, even for duplicate entries.
static func compact(slots:Array) -> void:
	var write:=0
	for read in range(slots.size()):
		if int(slots[read])!=0:
			slots[write]=int(slots[read]);write+=1
	for index in range(write,slots.size()):slots[index]=0

static func remove_id(slots:Array,stored_id:int) -> bool:
	var index:=slots.find(stored_id)
	if stored_id<=0 or index<0:return false
	slots[index]=0
	compact(slots)
	return true

static func add_id(slots:Array,stored_id:int) -> bool:
	var index:=slots.find(0)
	if stored_id<=0 or index<0:return false
	slots[index]=stored_id
	compact(slots)
	return true
