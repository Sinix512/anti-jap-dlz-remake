extends RefCounted
# 43CC96 +43CFE1/43D82F byte-width wrapping. The first page alone contains
# the padded name. A/B/C/D bytes do not count towards line width.
const GBK=preload("res://scripts/m2/GBK.gd")
const COLORS={65:0xB7,66:0x85,67:0x89,68:0x4F}
static func raw(text:String) -> PackedByteArray:
	var out:=GBK.encode(text,text.length()*2+1)
	var end:=out.find(0)
	return out.slice(0,end) if end>=0 else out

static func pages(text:String,speaker:="",width:=36) -> Array:
	var source:=raw(text)
	var prefix:=raw(speaker+"：") if speaker!="" else raw("    ")
	if speaker!="":
		while prefix.size()<width+2:prefix.append(32)
	source=prefix+source
	var result:Array=[];var page:Array=[];var cursor:=0;var row:=0
	while cursor<source.size():
		var line:=PackedByteArray();var count:=0
		while cursor<source.size() and count<width-2:
			var value:int=source[cursor];cursor+=1;line.append(value)
			if not COLORS.has(value):count+=1
		if count<width-2:pass
		elif cursor+1<source.size() and GBK.decode(source.slice(cursor,cursor+2)) in ["、","。","！","，","？"]:
			line.append_array(source.slice(cursor,cursor+2));cursor+=2
		else:line.append_array(raw("　"))
		page.append_array(glyphs(line,row*20))
		row+=1
		if row==5:result.append(page);page=[];row=0
	if row>0 or result.is_empty():result.append(page)
	return result

static func glyphs(line:PackedByteArray,y:int) -> Array:
	var out:Array=[];var i:=0;var x:=0;var color:=0x48
	while i<line.size():
		var value:int=line[i]
		if COLORS.has(value):color=int(COLORS[value]);i+=2;continue
		var size:=1 if value<128 else 2
		var text:=GBK.decode(line.slice(i,i+size))
		out.append({"text":text,"x":x,"y":y,"color":color})
		x+=size*8;i+=size;color=0x48
	return out

static func plain_rows(text:String) -> Array:
	var source:=raw(text);var rows:Array=[];var cursor:=0
	while cursor<source.size() and rows.size()<5:
		var line:=source.slice(cursor,mini(cursor+44,source.size()));cursor+=line.size()
		if line.size()==44:
			if cursor+1<source.size() and GBK.decode(source.slice(cursor,cursor+2)) in ["、","。","！","，","？"]:
				line.append_array(source.slice(cursor,cursor+2));cursor+=2
			else:line.append_array(raw("　"))
		rows.append(GBK.decode(line))
	return rows
