extends RefCounted
# 42CFEA / 40E4DA: ten interleaved {char name[16], int32 score} records.
const GBK=preload("res://scripts/m2/GBK.gd")
const PATH="user://hiscore.dat"
static func defaults() -> Array:
	var rows:Array=[]
	for i in range(10):rows.append({"name":"英  雄","score":3600-50*i})
	return rows
static func read_table(path:=PATH) -> Array:
	var rows:=defaults()
	if not FileAccess.file_exists(path):return rows
	var raw:=FileAccess.get_file_as_bytes(path)
	# A corrupt/truncated external file is not an original valid table. Keep
	# safe defaults rather than displaying uninitialized memory as native data.
	if raw.size()!=200:return rows
	for i in range(10):
		var name:=raw.slice(i*20,i*20+16);name[15]=0
		rows[i]={"name":GBK.decode(name),"score":raw.decode_s32(i*20+16)}
	return rows
static func encode_table(rows:Array) -> PackedByteArray:
	var raw:=PackedByteArray();raw.resize(200)
	for i in range(10):
		var name:=GBK.encode(str(rows[i].name),16)
		for j in range(16):raw[i*20+j]=name[j]
		raw.encode_s32(i*20+16,int(rows[i].score))
	return raw
static func insert_result(rows:Array,player_name:String,score:int) -> Array:
	var result:=rows.duplicate(true)
	var index:=9
	for i in range(10):
		if (int(rows[i].score)&0xFFFFFFFF)<(score&0xFFFFFFFF):index=i;break
	for i in range(9,index,-1):result[i]=result[i-1].duplicate(true)
	result[index]={"name":player_name,"score":int(((score&0xFFFFFFFF)+0x80000000)&0xFFFFFFFF)-0x80000000}
	return result
static func record_result(player_name:String,score:int,path:=PATH) -> bool:
	var rows:=insert_result(read_table(path),player_name,score)
	var f:=FileAccess.open(path,FileAccess.WRITE)
	if f==null:return false
	f.store_buffer(encode_table(rows));f.close()
	return true
