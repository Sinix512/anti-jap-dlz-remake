extends CanvasLayer

## 419CDF/41A53D/41B00E: MENU02 information overlay (person entry stably compacts both bags).
signal closed
const UI=preload("res://scripts/ui/OriginalUI.gd")
const InventorySlots=preload("res://scripts/battle/InventorySlots.gd")
const Rules=preload("res://scripts/battle/CombatRules.gd")
const KEYS=["buji","jili","yiliao","huogong","gunmu","leishi","weishe","saorao","pohuai","lueduo","fanjian","yibing","duzhan","ansha","shidu","kongxi"]
const INK=Color("#a4fcfc")
var canvas:Control
var font:Font
var tables:Dictionary
var _armed:=false
var _closed:=false
var _opening_release=preload("res://scripts/ui/OpeningReleaseGuard.gd").new()

func setup(f:Font, data:Dictionary, kind:String, id:int, person:Dictionary={}) -> void:
	layer=130;font=f;tables=data
	_opening_release.capture()
	canvas=Control.new();canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter=Control.MOUSE_FILTER_STOP;add_child(canvas)
	var panel=TextureRect.new();panel.texture=load("res://assets/ui/menu02.png")
	panel.position=Vector2(80,60);panel.size=Vector2(480,360);panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	canvas.add_child(panel)
	match kind:
		"person":_person(person)
		"mine":_mine(id)
		_:_item(id)
	UI.touch_back(canvas,font,close,"关闭")
	call_deferred("_arm")

func _arm() -> void:
	await get_tree().process_frame
	_armed=true

func _input(event:InputEvent) -> void:
	if _closed or canvas==null or not canvas.is_visible_in_tree():return
	if event is InputEventMouse or event is InputEventKey:get_viewport().set_input_as_handled()
	if UI.touch_mode(self) and event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:close();return
	if _opening_release.consumes(event) or not _armed:return
	var release:bool=(event is InputEventKey and not event.pressed) or (event is InputEventMouseButton and not event.pressed and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT])
	if release:
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and UI.native_wait_left_blocked and not UI.touch_mode(self):
			UI.native_wait_left_blocked=false
			return
		close()

func close() -> void:
	if _closed:return
	_closed=true;closed.emit();queue_free()

func label_(value:Variant,x:int,y:int,width:=160,color:=INK) -> void:
	var text=UI.label(str(value),font,16,color)
	text.position=Vector2(x,y);text.size=Vector2(width,16)
	canvas.add_child(text)

func icon(path:String,x:int,y:int,w:=48,h:=48) -> void:
	var texture:Texture2D=UI.first_frame(path) if w==48 else (load(path) if ResourceLoader.exists(path) else null)
	if texture==null:return
	var image=TextureRect.new();image.texture=texture;image.position=Vector2(x,y);image.size=Vector2(w,h)
	image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;image.mouse_filter=Control.MOUSE_FILTER_IGNORE;canvas.add_child(image)

func record(key:String,id:int) -> Dictionary:
	var collection:Variant=tables.get(key,{})
	if collection is Array:return collection[id] if id>=0 and id<collection.size() else {}
	return collection.get(str(id),{})

func item_icon(it:Dictionary) -> String:
	return str(it.get("icon","res://assets/goods/goods_%03d.png"%int(it.get("goods",0))))

func grid(apply:int,x:int,y:int,active_color:=Color("#fc0000")) -> void:
	var ranges:Dictionary=tables.get("apply_ranges",{})
	var matrix:Array=ranges.get(str(apply),[])
	for row in range(mini(7,matrix.size())):
		for col in range(7):label_("*" if int(matrix[row][col])>0 else "o",x+col*20,y+row*20,20,active_color if int(matrix[row][col])>0 else INK)

func _item(id:int) -> void:
	var it:=record("items",id)
	icon(item_icon(it),120,84);label_("名称：",184,84);label_(it.get("name",""),240,84,128)
	label_("价值：",376,84);label_(it.get("price",0),440,84,100)
	label_("特性：",184,120)
	var category:="装备"
	if id<=30:category="恢复系物品"
	elif id<=32:category="自动恢复"
	elif id<=40:category="增强属性"
	elif id<=60:category="伤害系物品"
	elif id<=67:category="转职物品"
	elif id<=80:category="升级物品"
	label_(category,240,120)
	if id<=30 or (id>=41 and id<=60):
		label_("体力加：" if id<=30 else "体力减：",184,156);label_(it.get("para1",0),252,156)
		label_("士气加：" if id<=30 else "士气减：",184,192);label_(it.get("para2",0),252,192)
		label_("范围：",184,264);grid(int(it.get("apply_fw",0)),240,264)
	elif id<=32:
		label_("体力恢复：",184,156);label_(it.get("para1",0),268,156,16);label_("%",284,156,16)
		label_("士气恢复：",184,192);label_(it.get("para2",0),268,192)
	elif id<=40:
		label_("武力加：",184,156);label_(it.get("para1",0),252,156)
		label_("智力加：",184,192);label_(it.get("para2",0),252,192)
	elif id<=67:
		label_("转职为：",184,156)
		label_(record("units",int(it.get("para1",0))).get("name",""),252,156)
	elif id<=80:
		var source:Dictionary={}
		for unit in range(1,23):
			var cls:=record("units",unit)
			if int(cls.get("zhuanzhidaoju",-1))==id:source=cls;break
		label_("从",184,156,20);label_(source.get("name",""),204,156,52)
		label_("升级到",256,156,52)
		label_(record("units",int(source.get("zhuanzhi",it.get("para1",0)))).get("name",""),308,156,128)
		label_("升级等级：",184,264,80);label_(30 if id>=75 and id<=78 else 15,264,264,40)
	else:
		for row in range(3):
			label_(["行动力加：","攻击加：","防御加："][row],184,156+row*36)
			label_(it.get(["para1","para3","para4"][row],0),268,156+row*36)
	var base_y:=132 if id>=61 and id<=80 else (168 if id<=32 or (id>=41 and id<=60) else 200)
	label_("适用兵种：",184,base_y+60,80)
	if id<61:
		label_("所有兵种",264,base_y+60,160)
	else:
		var valid:Array=tables.get("item_valid",[])
		var names:Array=[]
		if id<valid.size():
			for unit in range(1,23):
				if unit<valid[id].size() and int(valid[id][unit])!=0:names.append(record("units",unit).get("name",""))
		for index in range(mini(20,names.size())):label_(names[index],184+80*(index%4),base_y+96+36*(index/4),80)

func _mine(id:int) -> void:
	var mine:=record("mines",id%10)
	icon("res://assets/mine/mine_%03d.png"%id,120,84)
	label_("名称：",184,84);label_(mine.get("name",""),240,84,128)
	label_("价值：",376,84);label_(mine.get("price",0),440,84,100)
	label_("特性：",184,120);label_(["普通","引发","定时","遥控"][clampi(id/10,0,3)],240,120)
	label_("威力：",184,156);label_(mine.get("weili",0),240,156)
	label_("范围：",184,192);grid(int(mine.get("apply_fw",0)),240,192,Color("#fc0000") if int(mine.get("shiqi_or_tili",0))==0 else Color("#809840"))
	label_("材料：",184,342)
	var recipe:Array=mine.get("recipe",[])
	var shown:=0
	for index in range(recipe.size()):
		if int(recipe[index])==0:continue
		label_(record("materials",index).get("name",""),240+64*shown,342,64)
		label_(recipe[index],248+64*shown,378,64);shown+=1

func _person(person:Dictionary) -> void:
	InventorySlots.compact(person.get("item_slots",[]))
	InventorySlots.compact(person.get("mine_slots",[]))
	var cls:=record("units",int(person.get("bingzhong",0)))
	if cls.is_empty():cls=record("unit_types",int(person.get("bingzhong",0)))
	icon(str(person.get("face_png","res://assets/face/face_%03d.png"%int(person.get("face",0)))),104,84,80,100)
	label_(person.get("name",person.get("unit_name","")),208,84)
	label_("武力：%d"%int(person.get("wuli",0)),208,104)
	label_("智力：%d"%int(person.get("zhili",0)),208,124)
	label_(cls.get("name",""),208,144)
	label_("等级：%d"%int(person.get("level",1)),208,164)
	var count:=int(person.get("attack_count",0))
	var morale:=int(person.get("morale",100))
	var attack_bonus:=0;var defense_bonus:=0;var movement_bonus:=0
	var valid:Array=tables.get("item_valid",[])
	var unit_id:=int(person.get("bingzhong",0))
	for raw in person.get("item_slots",[]):
		var iid:=int(raw)-1
		if iid<81 or iid>=valid.size() or unit_id>=valid[iid].size() or int(valid[iid][unit_id])==0:continue
		var item:=record("items",iid)
		attack_bonus=maxi(attack_bonus,int(item.get("para3",0)))
		defense_bonus=maxi(defense_bonus,int(item.get("para4",0)))
		movement_bonus=maxi(movement_bonus,int(item.get("para1",0)))
	var atk:=Rules.attack_power(person,cls,morale,int(person.get("integrity",100)),count,attack_bonus)
	var df:=Rules.defense_power(person,cls,morale,int(person.get("terrain_bonus",0)),defense_bonus,int(person.get("defense_integrity",100)))
	label_("攻击力 %d"%atk,104,184,104);label_("攻击等级 %d"%Rules.skill_level(count),208,184,112)
	label_("防御力 %d"%df,104,204,104);label_("移动力 %d"%(int(cls.get("yidong",0))+movement_bonus),208,204,112)
	var maxhp:=maxi(1,int(cls.get("tili",50))+(int(person.get("level",1))-1)*int(cls.get("tili_plus",0)))
	label_("体力 %d/%d"%[int(person.get("hp",maxhp)),maxhp],104,224,204)
	label_("士气 %d/100"%morale,104,244,204)
	var skills:Dictionary=person.get("skill_counts",person.get("skills",{}))
	for index in range(16):
		var level:=Rules.skill_level(int(skills.get(KEYS[index],0)))
		var skill:=record("skills",index)
		label_(skill.get("name",""),104+54*(index%4),280+32*(index/4),40,INK if level else Color("#949498"))
		label_(level,140+54*(index%4),280+32*(index/4),18)
	var bag:Array=person.get("item_slots",[]).filter(func(raw):return int(raw)>0)
	for index in range(mini(8,bag.size())):
		var iid:=int(bag[index])-1
		var it:=record("items",iid)
		var compatible:bool=iid<valid.size() and unit_id<valid[iid].size() and int(valid[iid][unit_id])!=0
		var color:=INK if compatible else Color("#fc8c00")
		icon(item_icon(it),320+56*(index%4),94+80*(index/4))
		var name_:String=str(it.get("name","")).replace("　","").replace(" ","")
		label_(name_.substr(0,3),320+56*(index%4),142+80*(index/4),56,color)
		label_(name_.substr(3,3),320+56*(index%4),158+80*(index/4),56,color)
	var mines:Array=person.get("mine_slots",[]).filter(func(raw):return int(raw)>0)
	for index in range(mini(8,mines.size())):
		var id:=int(mines[index])-1
		icon("res://assets/mine/mine_%03d.png"%id,320+56*(index%4),264+64*(index/4))
		label_(record("mines",id%10).get("name",""),320+56*(index%4),312+64*(index/4),56)
