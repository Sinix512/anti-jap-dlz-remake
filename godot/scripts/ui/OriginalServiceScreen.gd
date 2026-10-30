extends Control
# 4325E4 / 4350D1 / 437D09 / 439541: native service surfaces and events.
# timer113 is supplied by a 55ms Godot adapter, not a Win32 message-pump claim.
const Palette=preload("res://scripts/ui/OriginalPalette.gd")
const GBK=preload("res://scripts/m2/GBK.gd")
var campaign
var kind:=""
var palette:Array=[]
var background:Texture2D
var buttons:Array=[]
var banks:Dictionary={}
var textures:Dictionary={}
var pressed:=""
var drag:Dictionary={}
var drag_point:=Vector2.ZERO
var timer_count:int:
	get:return campaign.native_service_timer_count if campaign!=null else 0
	set(value):
		if campaign!=null:campaign.native_service_timer_count=value
var elapsed:=0.0
var enabled:=true
# The original path below stays intact. These fields belong only to the
# opt-in-by-default click/drag adapter, not to native fixture state.
const SHOP_DRAG_THRESHOLD:=6.0
var shop_pointer_active:=false
var shop_down_point:=Vector2.ZERO
var shop_down_item:Dictionary={}
var shop_down_target:Dictionary={}
var shop_dragging:=false
var shop_swallow_release:=false

func setup(owner_campaign,screen:String) -> void:
	campaign=owner_campaign;kind=screen
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP;texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var key:String={"shop":"K01","forge":"K03","mines":"K04"}[kind]
	palette=Palette.colors(key)
	background=Palette.asset("service_"+key.to_lower(),640,480,palette)
	for i in range(14):
		var s:=Vector2i(50,25) if i<2 else (Vector2i(48,44) if i<10 else Vector2i(35,19))
		buttons.append(Palette.asset("service_button%d"%i,s.x,s.y,palette,0 if i in range(2,10) else -1))
	for bank in ["army","goods","material","mine"]:banks[bank]=FileAccess.get_file_as_bytes("res://assets/ui/service_"+bank+"_indices.bin")
	OriginalUI.native_text_index=0x48
	OriginalUI.touch_back(self,campaign.font,_touch_back)
	queue_redraw()

func refresh() -> void:queue_redraw()
func _text(value:String,x:int,y:int,ink:=0x48) -> void:
	draw_string(campaign.font,Vector2(x,y+campaign.font.get_ascent(16)),value.replace("\\u3000","　"),HORIZONTAL_ALIGNMENT_LEFT,-1,16,Palette.color_at(palette,ink))
func _sprite(bank:String,index:int,key:=0) -> Texture2D:
	var cache:="%s:%d:%d"%[bank,index,key]
	if not textures.has(cache):textures[cache]=Palette.texture((banks[bank] as PackedByteArray).slice(index*2304,(index+1)*2304),48,48,palette,key)
	return textures[cache]
func _army(member:Dictionary) -> Texture2D:
	return _sprite("army",int(campaign.state.data.units[str(member.get("bingzhong",0))].img_index))
func _button(id:String,at:Vector2,label:String,selected:=false,arrow:=-1) -> void:
	var texture:Texture2D=buttons[(0 if arrow<0 else arrow)+(1 if pressed==id or selected else 0)]
	if OriginalUI.touch_mode(self):
		var control:Array=_controls()[id];var bounds:=Vector2(control[2],control[3])
		draw_rect(Rect2(at,bounds),Color("#39485b") if pressed==id or selected else Color("#1f2c3b"))
		draw_rect(Rect2(at,bounds),Color("#bd9b62"),false,1)
		if label.is_empty():draw_texture(texture,at+(bounds-texture.get_size())/2)
		else:_text(label,int(at.x)+8,int(at.y)+(int(bounds.y)-16)/2)
	else:
		draw_texture(texture,at)
		if not label.is_empty():_text(label,int(at.x)+8,int(at.y)+4)
func _outline(at:Vector2,size_:Vector2=Vector2(48,48)) -> void:
	# Pixel endpoints inclusive, like the original 4267xx frame.
	var c:=Palette.color_at(palette,0xB7)
	draw_rect(Rect2(at,Vector2(size_.x,1)),c);draw_rect(Rect2(at,Vector2(1,size_.y)),c)
	draw_rect(Rect2(at+Vector2(size_.x-1,0),Vector2(1,size_.y)),c);draw_rect(Rect2(at+Vector2(0,size_.y-1),Vector2(size_.x,1)),c)
func _capacity(member:Dictionary,at:Vector2,items:bool) -> void:
	var n:=0
	for value in member.get("item_slots" if items else "mine_slots",[]):
		if int(value)<=0:continue
		var ink:int=0xBF if items else [0xBF,0xB7,0xCF,0xEE][(int(value)-1)/10]
		draw_rect(Rect2(at+Vector2(0,-6*n),Vector2(4,4)),Palette.color_at(palette,ink));n+=1
func _draw() -> void:
	if background==null:return
	draw_texture(background,Vector2.ZERO)
	match kind:
		"shop":_draw_shop()
		"forge":_draw_forge()
		"mines":_draw_mines()
	if not drag.is_empty():draw_texture(_sprite(str(drag.bank),int(drag.icon)),drag_point)
	if kind=="mines" and OriginalUI.touch_mode(self):
		_text("点地雷→人物/库房/卖出；长按看详情",18,454)
		if campaign.k04_held>=0:
			var x:int=22+56*campaign.k04_source
			_outline(Vector2(x,34))

func shop_stock_at(point:Vector2) -> Dictionary:
	var mode:int=campaign.shop_mode
	var columns:=5 if mode==3 else (4 if mode==1 else 6)
	var y:=28 if mode==2 else 32
	var step:=64 if mode==3 else 56
	if not Rect2(24,y,columns*step,240).has_point(point):return {}
	var index:int=int((point.y-y)/120)*columns+int((point.x-24)/step)
	if mode==2:index+=campaign.shop_item_page*12
	var stock:Array=campaign._shop_stock()
	return stock[index] if index<stock.size() and int(stock[index].id)>=0 else {}
func shop_person_at(point:Vector2) -> int:
	if not Rect2(24,304,512,128).has_point(point):return -999
	var index:int=int((point.y-304)/64)*8+int((point.x-24)/64)+campaign.shop_people_page*8
	var roster:Array=campaign._shop_roster()
	return int(roster[index].pid) if index<roster.size() else -999
func _draw_shop() -> void:
	var mode:int=campaign.shop_mode
	var controls:=_controls()
	for id in controls:
		var c:Array=controls[id]
		_button(id,Vector2(c[0],c[1]),str(c[4]),int(c[5])==mode if c.size()>5 else false,10 if str(id).ends_with("up") else (12 if str(id).ends_with("down") else -1))
	_text("资金：",520,48);_text(str(campaign.state.money),572,48)
	_text("上",520,134);_text("交",520,172);_text("库",520,204);_text("房",520,242)
	var stock:Array=campaign._shop_stock()
	var start:int=campaign.shop_item_page*12 if mode==2 else 0
	var columns:=5 if mode==3 else (4 if mode==1 else 6)
	for offset in range(mini(columns*2,stock.size()-start)):
		var entry:Dictionary=stock[start+offset]
		if int(entry.id)<0:continue
		var rec:Dictionary=entry.record
		var x:int=24+(64 if mode==3 else 56)*(offset%columns)
		var y:int=(28 if mode==2 else 32)+120*(offset/columns)
		var ink:=0x48
		if mode==1 and not campaign.state.item_compatible(campaign.state.deploy_member(campaign.shop_person),int(entry.id)):ink=0xBF
		var raw:=GBK.encode(str(rec.get("name","")).replace("\\u3000","　"),13)
		_text(GBK.decode(raw.slice(0,6)),x,y,ink);_text(GBK.decode(raw.slice(6,12)),x,y+16,ink)
		draw_texture(_sprite("material" if mode==3 else "goods",int(entry.id) if mode==3 else int(rec.goods),-1),Vector2(x,y+32))
		if mode in [2,3]:
			_text(str(campaign.state.material_count(int(entry.id)) if mode==3 else campaign.state.item_count(int(entry.id))),x,y+80)
		_text(str(rec.get("price",0)),x,y+(96 if mode in [2,3] else 80))
		if campaign.shop_convenience_enabled and not campaign.shop_pending.is_empty() and int(campaign.shop_pending.get("id",-1))==int(entry.id) and int(campaign.shop_pending.get("slot",-1))==int(entry.slot):
			_outline(Vector2(x-2,y-2),Vector2(52,114 if mode==2 else 98))
	var people:Array=campaign._shop_roster()
	for offset in range(mini(16,people.size()-campaign.shop_people_page*8)):
		var member:Dictionary=people[campaign.shop_people_page*8+offset]
		var x:int=24+64*(offset%8);var y:int=304+64*(offset/8)
		draw_texture(_army(member),Vector2(x,y))
		_text("LV  "+str(member.level),x,y+32);_text(str(member.name),x,y+48)
		_capacity(member,Vector2(x+52,y+44),true)
		if mode==1 and int(member.pid)==campaign.shop_person:_outline(Vector2(x,y))
	if campaign.shop_convenience_enabled:_draw_shop_help()

func _shop_footer_text(value:String,y:int,color:Color) -> void:
	var text:=value.replace("\\u3000","　")
	while text.length()>0 and campaign.font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x>(530 if OriginalUI.touch_mode(self) else 600):text=text.left(text.length()-1)
	draw_string(campaign.font,Vector2(20,y+campaign.font.get_ascent(16)),text,HORIZONTAL_ALIGNMENT_LEFT,530 if OriginalUI.touch_mode(self) else 600,16,color)

func _draw_shop_help() -> void:
	# This unused footer is below every person cell, not over shop controls.
	draw_rect(Rect2(0,434,640,46),Color("#192632"))
	var hint:String={0:"点选商品→点人物/库房；双击商品快速买入库房",1:"点选随身物品→人物/库房；可重复点上交，每次1件",2:"点选库房物品→人物；可重复点上交每次1件；滚轮翻页",3:"点击材料选择数量；确认后才扣款"}.get(campaign.shop_mode,"")
	if OriginalUI.touch_mode(self):
		hint={0:"点商品→人物/库房；长按商品或人物看详情",1:"点物品→人物/库房；重复点上交，每次1件",2:"点物品→人物/上交；重复点上交每次1件",3:"点材料选择数量；点击购买才扣款"}.get(campaign.shop_mode,"")
	_shop_footer_text(hint,438,Color("#f2d78a"))
	var detail:="右键：详情/取消　Esc：取消/返回　人物区滚轮：翻页"
	if not campaign.shop_pending.is_empty():
		var record:Dictionary=campaign.shop_pending.get("record",{})
		var price:=int(campaign.state.item(int(campaign.shop_pending.id)).get("price",0))
		var label:="买入价" if campaign.shop_mode==0 else "上交价"
		var amount:int=price if campaign.shop_mode==0 else price*(7-campaign.state.difficulty)/10
		detail="已选：%s　%s：%d　右键/Esc取消"%[str(record.get("name","")).replace("\\u3000","　"),label,amount]
	if OriginalUI.touch_mode(self):detail="长按详情；箭头翻页；右下返回先取消选择" if campaign.shop_pending.is_empty() else detail.replace("右键/Esc取消","返回取消")
	_shop_footer_text(detail,460,Color("#e5edf4"))

func _draw_forge() -> void:
	draw_rect(Rect2(22,34,600,66),Palette.color_at(palette,0xFF))
	for i in range(10):
		_text(str(campaign.state.mine(i).name),22+60*i,16)
		var tex:=_sprite("mine",campaign.forge_fuse*10+i,-1)
		draw_texture(tex,Vector2(22+60*i,34))
		if not _unlocked(false,i):_stripe(Rect2i(22+60*i,34,48,48))
		_text(str(campaign.state.mine_count(campaign.forge_fuse*10+i)),30+60*i,84)
	_outline(Vector2(22+60*campaign.forge_kind,34))
	for i in range(4):
		var p:=Vector2(34+78*(i%2),127+96*(i/2))
		draw_texture(buttons[2+i*2+(1 if i==campaign.forge_fuse else 0)],p)
		if not _unlocked(true,i):_stripe(Rect2i(p,Vector2i(48,44)))
		_text(["普通","引爆","定时","遥控"][i],40+78*(i%2),175 if i<2 else 205)
	for id in _controls():
		var c:Array=_controls()[id]
		_button(id,Vector2(c[0],c[1]),str(c[4]),false,10 if id=="plus" else (12 if id=="minus" else -1))
	_text(str(campaign.forge_quantity),438,161)
	_text("所需资金:",187,226);_text(str([0,0,80,300][campaign.forge_fuse]*campaign.forge_quantity),267,226)
	_text("当前资金:",187,253);_text(str(campaign.state.money),267,253)
	var column:=0
	var recipe:Array=campaign.state.mine(campaign.forge_kind).recipe
	for i in range(recipe.size()):
		if int(recipe[i])<=0:continue
		var x:=122+60*column
		_text(str(campaign.state.material(i).name),x,298);draw_texture(_sprite("material",i,-1),Vector2(x,316))
		_text(str(campaign.state.material_count(i)),x+8,364);_text(str(recipe[i]),x+8,384);_text(str(int(recipe[i])*campaign.forge_quantity),x+8,404);column+=1
	_text("现有数量",30,364);_text("配   方",30,384);_text("所需数量",30,404)
func _stripe(rect:Rect2i) -> void:
	for x in range(0,rect.size.x,2):draw_rect(Rect2(rect.position+Vector2i(x,0),Vector2(1,rect.size.y)),Palette.color_at(palette,0xFF))
func _unlocked(fuse:bool,index:int) -> bool:return int(campaign.state.script_globals.get("0x%x"%((0x95eaf8 if fuse else 0x95eb08)+index*4),0))!=0

func mine_at(point:Vector2) -> Dictionary:
	var person=campaign.state.deploy_member(campaign.k04_person)
	var columns:=10 if person==null else 8
	if not Rect2(22,34,columns*56,48).has_point(point):return {}
	var index:=int((point.x-22)/56)
	var packed:int=campaign.k04_page*10+index if person==null else int(person.mine_slots[index])-1
	if packed<0:return {}
	return {"index":index,"packed":packed}
func mine_person_at(point:Vector2) -> int:
	if not Rect2(22,113,448,320).has_point(point):return -999
	var index:int=int((point.y-113)/64)*7+int((point.x-22)/64)
	var people:Array=campaign._shop_roster()
	return int(people[index].pid) if index<people.size() else -999
func _draw_mines() -> void:
	draw_rect(Rect2(22,16,560,84),Palette.color_at(palette,0xFF))
	var person=campaign.state.deploy_member(campaign.k04_person)
	for i in range(10 if person==null else 8):
		var packed:int=campaign.k04_page*10+i if person==null else int(person.mine_slots[i])-1
		if packed<0:continue
		_text(str(campaign.state.mine(packed%10).name),22+56*i,16)
		draw_texture(_sprite("mine",packed,-1),Vector2(22+56*i,34))
		if person==null:_text(str(campaign.state.mine_count(packed)),30+56*i,84)
	var people:Array=campaign._shop_roster()
	for i in range(people.size()):
		var m:Dictionary=people[i];var x:=22+64*(i%7);var y:=113+64*(i/7)
		draw_texture(_army(m),Vector2(x,y));_text("LV  "+str(m.level),x,y+32);_text(str(m.name),x,y+48);_capacity(m,Vector2(x+52,y+44),false)
		if person!=null and int(m.pid)==campaign.k04_person:_outline(Vector2(x-1,y-1),Vector2(50,50))
	for id in _controls():
		var c:Array=_controls()[id];var label:=str(c[4])
		if id=="switch":label="分配" if person!=null or pressed=="switch" else "交换"
		_button(id,Vector2(c[0],c[1]),label,false,10 if id=="up" else (12 if id=="down" else -1))
	if person!=null:draw_rect(Rect2(588,38,35,38),Palette.color_at(palette,0xFF))
	_text("资金：",508,154);_text(str(campaign.state.money),556,154)
	for row in [["卖",502,312],["出",502,342],["库",502,376],["房",502,406]]:_text(str(row[0]),int(row[1]),int(row[2]))

func _native_controls() -> Dictionary:
	if kind=="forge":return {"equip":[439,233,50,25,"装备"],"back":[522,233,50,25,"返回"],"reset":[542,132,50,25,"取消"],"max":[542,160,50,25,"最大"],"make":[542,188,50,25,"制造"],"plus":[496,151,35,19,""],"minus":[496,170,35,19,""]}
	if kind=="mines":
		var c:Dictionary={"switch":[533,178,50,25,"交换"],"back":[533,220,50,25,"返回"]}
		if campaign.k04_person==-999:c.merge({"up":[588,38,35,19,""],"down":[588,57,35,19,""]})
		return c
	var c:Dictionary={}
	var military:bool=campaign.shop_kind=="junxie"
	var modes:Array=[0,1,2] if military else [0,3,1,2]
	var labels:Array=["买入","交换","分配"] if military else ["物品","材料","交换","分配"]
	for i in range(modes.size()):c["mode%d"%modes[i]]=[440,(58+50*i) if military else (42+42*i),50,25,labels[i],modes[i]]
	c.back=[440,208 if military else 210,50,25,"返回"]
	if campaign.shop_mode==2:c.merge({"stock_up":[367,202,35,19,""],"stock_down":[367,221,35,19,""]})
	c.merge({"people_up":[574,372,35,19,""],"people_down":[574,391,35,19,""]})
	return c
func _controls() -> Dictionary:
	var controls:=_native_controls()
	if not OriginalUI.touch_mode(self):return controls
	for id in controls:
		var rect:Array=controls[id];rect[3]=40
	if kind=="shop":
		controls.people_up=[574,340,50,40,""]
		controls.people_down=[574,386,50,40,""]
		if campaign.shop_mode==2:
			controls.stock_up=[367,166,48,40,""]
			controls.stock_down=[367,214,48,40,""]
		# Grocery modes are42px apart, so40px targets do not overlap.
	elif kind=="forge":
		controls.plus=[496,132,40,40,""];controls.minus=[496,180,40,40,""]
		controls.reset=[542,108,50,36,"取消"];controls.max=[542,150,50,36,"最大"];controls.make=[542,192,50,36,"制造"]
	elif kind=="mines" and campaign.k04_person==-999:
		controls.up=[588,16,48,40,""];controls.down=[588,62,48,40,""]
	return controls

func _control_at(point:Vector2) -> String:
	for id in _controls():
		var c:Array=_controls()[id]
		if Rect2(c[0],c[1],c[2],c[3]).has_point(point):return id
	return ""
func _input(event:InputEvent) -> void:
	if not enabled or not is_visible_in_tree() or campaign._service_input_blocked():return
	if event is InputEventMouse or event is InputEventKey:get_viewport().set_input_as_handled()
	if OriginalUI.touch_mode(self) and event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:_touch_back();return
	if kind=="shop" and campaign.shop_convenience_enabled:
		_shop_convenience_input(event)
		return
	if event is InputEventMouseMotion:
		if not drag.is_empty():drag_point=_drag_origin(event.position);queue_redraw()
		return
	if not event is InputEventMouseButton:return
	var point:Vector2=event.position
	if kind=="mines" and OriginalUI.touch_mode(self) and event.button_index==MOUSE_BUTTON_LEFT:
		if not event.pressed:_touch_mine_tap(point)
		return
	if event.button_index==MOUSE_BUTTON_RIGHT:
		if kind=="shop" and event.pressed and event.double_click and campaign.shop_mode==2 and Rect2(536,134,64,54).has_point(point):campaign._shop_bulk_input(event)
		elif not event.pressed and pressed.is_empty():_right_up(point)
		return
	if event.button_index!=MOUSE_BUTTON_LEFT:return
	var control:=_control_at(point)
	if event.pressed:
		if not drag.is_empty():return
		if kind=="shop" and control.begins_with("mode"):
			campaign._shop_mode(control.trim_prefix("mode").to_int());queue_redraw();return
		if not control.is_empty():
			pressed=control
			if kind=="forge" and control=="reset":OriginalUI.play_native_sfx(7)
			queue_redraw();return
		_down_source(point)
	else:
		if kind=="forge":timer_count=0
		if not drag.is_empty():_drop(point);return
		if not pressed.is_empty():
			var old:=pressed;pressed="";queue_redraw()
			if old==control:_activate(old)
			return
		_release_selection(point)

func clear_shop_interaction() -> void:
	pressed="";drag.clear();shop_pointer_active=false
	shop_down_item.clear();shop_down_target.clear();shop_dragging=false
	shop_swallow_release=false
	queue_redraw()

func _shop_destination_at(point:Vector2) -> Dictionary:
	var pid:=shop_person_at(point)
	if pid!=-999:return {"destination":"person","pid":pid}
	if Rect2(536,134,64,54).has_point(point) and campaign.shop_mode in [1,2]:return {"destination":"sell","pid":-1}
	if Rect2(536,204,64,54).has_point(point) and campaign.shop_mode in [0,1]:return {"destination":"store","pid":-1}
	return {}

func _shop_same_source(first:Dictionary,second:Dictionary) -> bool:
	return not first.is_empty() and not second.is_empty() and int(first.id)==int(second.id) and int(first.slot)==int(second.slot)

func _shop_convenience_input(event:InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
			if not campaign.shop_pending.is_empty() or shop_pointer_active or not drag.is_empty():campaign._shop_cancel_selection()
			else:campaign._service_return_town()
		return
	if event is InputEventMouseMotion:
		if shop_pointer_active and not shop_down_item.is_empty() and campaign.shop_mode!=3:
			if event.position.distance_to(shop_down_point)>SHOP_DRAG_THRESHOLD:shop_dragging=true
			if shop_dragging:
				drag={"bank":"goods","icon":int(shop_down_item.record.goods)}
				drag_point=_drag_origin(event.position);queue_redraw()
		return
	if not event is InputEventMouseButton:return
	var point:Vector2=event.position
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		if event.pressed:
			var delta:=-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1
			if Rect2(24,304,512,128).has_point(point):campaign._shop_page(delta,true)
			elif campaign.shop_mode==2 and Rect2(24,28,384,240).has_point(point):campaign._shop_page(delta,false)
		return
	if event.button_index==MOUSE_BUTTON_RIGHT:
		if event.pressed:
			campaign._shop_cancel_selection()
			if event.double_click and campaign.shop_mode==2 and Rect2(536,134,64,54).has_point(point):campaign._shop_bulk_input(event)
		else:_right_up(point)
		return
	if event.button_index!=MOUSE_BUTTON_LEFT:return
	if not event.pressed and shop_swallow_release:
		shop_swallow_release=false
		return
	var control:=_control_at(point)
	if event.pressed:
		# A release swallowed by a modal cannot suppress a later fresh gesture.
		shop_swallow_release=false
		if shop_pointer_active:return
		if not control.is_empty():
			campaign._shop_clear_interaction()
			if control.begins_with("mode"):campaign._shop_mode(control.trim_prefix("mode").to_int())
			else:pressed=control
			queue_redraw();return
		var item:=shop_stock_at(point)
		if not item.is_empty():
			campaign._shop_clear_interaction()
			if campaign.shop_mode==0 and event.double_click:
				campaign._shop_pick(item);campaign._shop_commit("store",-1,false)
				shop_swallow_release=true
				return
			shop_pointer_active=true;shop_down_point=point;shop_down_item=item.duplicate(true)
			if campaign.shop_mode!=3:campaign._shop_pick(item)
			queue_redraw();return
		var target:=_shop_destination_at(point)
		if not campaign.shop_pending.is_empty() and not target.is_empty():
			shop_pointer_active=true;shop_down_point=point;shop_down_target=target
		elif campaign.shop_mode==1 and not target.is_empty() and target.destination=="person":
			campaign._shop_clear_interaction();campaign.shop_person=int(target.pid);campaign._render_shop()
		else:campaign._shop_cancel_selection()
		return
	if not pressed.is_empty():
		var old:=pressed;pressed="";queue_redraw()
		if old==control:_activate(old)
		return
	if not shop_pointer_active:return
	var source:=shop_down_item.duplicate(true)
	var target:=shop_down_target.duplicate(true)
	var click:=not shop_dragging and point.distance_to(shop_down_point)<=SHOP_DRAG_THRESHOLD
	clear_shop_interaction()
	if not source.is_empty():
		if click and _shop_same_source(source,shop_stock_at(point)):
			if campaign.shop_mode==3:campaign._shop_material(int(source.id))
			else:campaign._render_shop()
		elif campaign.shop_mode==3:campaign._shop_cancel_selection()
		else:_drop(point)
	elif click and not target.is_empty() and target==_shop_destination_at(point):campaign._shop_commit(str(target.destination),int(target.pid),false)
	else:campaign._shop_cancel_selection()
func _down_source(point:Vector2) -> void:
	if kind=="shop":
		if campaign.shop_mode==3:return
		var item:=shop_stock_at(point)
		if not item.is_empty():
			campaign._shop_pick(item);drag={"bank":"goods","icon":int(item.record.goods)}
		elif campaign.shop_mode==1:
			var pid:=shop_person_at(point)
			if pid!=-999:campaign.shop_person=pid
	elif kind=="mines":
		var source:=mine_at(point)
		if not source.is_empty() and (campaign.k04_person!=-999 or campaign.state.mine_count(int(source.packed))>0):
			campaign._k04_pick(int(source.index),int(source.packed));drag={"bank":"mine","icon":int(source.packed)}
	if not drag.is_empty():drag_point=_drag_origin(point)
	queue_redraw()
func _drag_origin(point:Vector2) -> Vector2:
	# Native mouse/display coordinates are integer pixels. High-DPI window
	# scaling can supply half-pixels in Godot; never sample the icon between rows.
	return (point-Vector2(24,24)).floor().clamp(Vector2.ZERO,Vector2(591,431))
func _drop(point:Vector2) -> void:
	drag.clear()
	if kind=="shop":
		var pid:=shop_person_at(point)
		if pid!=-999:campaign._shop_commit("person",pid,false)
		elif Rect2(536,134,64,54).has_point(point) and campaign.shop_mode in [1,2]:campaign._shop_commit("sell",-1,false)
		elif Rect2(536,204,64,54).has_point(point) and campaign.shop_mode in [0,1]:campaign._shop_commit("store",-1,false)
		else:campaign.shop_pending.clear()
	else:
		var pid:=mine_person_at(point)
		if pid!=-999:campaign._k04_target(pid)
		elif Rect2(525,308,64,54).has_point(point):campaign._k04_sell()
		elif Rect2(525,372,64,54).has_point(point):campaign._k04_store()
		campaign.k04_source=-1;campaign.k04_held=-1
	queue_redraw()
func _release_selection(point:Vector2) -> void:
	if kind=="forge":
		if Rect2(22,34,600,48).has_point(point):campaign._set_forge_kind(int((point.x-22)/60))
		else:
			for i in range(4):
				if Rect2(34+78*(i%2),127+96*(i/2),48,44).has_point(point):campaign._set_forge_fuse(i);break
	elif kind=="shop" and campaign.shop_mode==3:
		var item:=shop_stock_at(point)
		if not item.is_empty():campaign._shop_material(int(item.id))
	elif kind=="mines" and campaign.k04_person!=-999:
		var pid:=mine_person_at(point)
		if pid!=-999:campaign._k04_target(pid)
	queue_redraw()
func _right_up(point:Vector2) -> void:
	if kind=="shop":
		var item:=shop_stock_at(point)
		if not item.is_empty() and campaign.shop_mode!=3:campaign._open_original_info("item",int(item.id));return
		var pid:=shop_person_at(point)
		if pid!=-999:campaign._open_original_info("person",pid)
	elif kind=="forge":
		if Rect2(22,34,600,48).has_point(point):campaign._open_original_info("mine",campaign.forge_fuse*10+int((point.x-22)/60))
	else:
		var source:=mine_at(point)
		if not source.is_empty():campaign._open_original_info("mine",int(source.packed))
func _activate(id:String) -> void:
	if kind=="forge":
		match id:
			"plus":campaign._forge_adjust(1)
			"minus":campaign._forge_adjust(-1)
			"reset":campaign._forge_reset()
			"max":campaign._forge_set_max()
			"make":campaign._forge_batch()
			"equip","back":_delayed_leave(id)
	elif kind=="mines":
		match id:
			"switch":campaign._k04_switch()
			"up":campaign._k04_fuse(-1)
			"down":campaign._k04_fuse(1)
			"back":campaign._open_forge()
	else:
		match id:
			"back":OriginalUI.play_native_sfx(8);campaign._service_return_town()
			"stock_up":campaign._shop_page(-1,false)
			"stock_down":campaign._shop_page(1,false)
			"people_up":campaign._shop_page(-1,true)
			"people_down":campaign._shop_page(1,true)
func _delayed_leave(id:String) -> void:
	enabled=false
	if id=="back":OriginalUI.play_native_sfx(8)
	await get_tree().create_timer(0.2).timeout
	if not is_visible_in_tree():return
	if id=="equip":campaign._show_k04_status()
	else:campaign._service_return_town()
func timer113() -> void:
	timer_count+=1
	if timer_count>30 and timer_count%2==0:
		if pressed=="plus":campaign._forge_adjust(1)
		elif pressed=="minus":campaign._forge_adjust(-1)
func _process(delta:float) -> void:
	if kind!="forge" or not enabled or not is_visible_in_tree() or campaign._service_input_blocked():return
	elapsed+=delta
	while elapsed>=0.055:elapsed-=0.055;timer113()

# Preserve palette INDEX identity when 428B8F captures its local background.
# RGB readback would lose aliases that the fixed KUANG04 LUT maps differently.
func quantity_backdrop() -> PackedByteArray:
	var full:=FileAccess.get_file_as_bytes("res://assets/ui/service_k01_indices.bin")
	var out:=PackedByteArray();out.resize(160*100)
	for y in range(100):
		for x in range(160):out[y*160+x]=full[(160+y)*640+240+x]
	var stock:Array=campaign._shop_stock()
	for i in range(mini(stock.size(),10)):
		var entry:Dictionary=stock[i];var rec:Dictionary=entry.record
		var x:int=24+64*(i%5);var y:int=32+120*(i/5)
		var name_:=GBK.encode(str(rec.name).replace("\\u3000","　"),13)
		_index_text(out,GBK.decode(name_.slice(0,6)),x,y);_index_text(out,GBK.decode(name_.slice(6,12)),x,y+16)
		var raw:PackedByteArray=(banks.material as PackedByteArray).slice(int(entry.id)*2304,(int(entry.id)+1)*2304)
		for yy in range(48):
			for xx in range(48):_index_pixel(out,x+xx,y+32+yy,raw[yy*48+xx])
		_index_text(out,str(campaign.state.material_count(int(entry.id))),x,y+80);_index_text(out,str(rec.price),x,y+96)
	return out
func _index_pixel(raw:PackedByteArray,x:int,y:int,value:int) -> void:
	if x>=240 and x<400 and y>=160 and y<260:raw[(y-160)*160+x-240]=value
func _index_text(raw:PackedByteArray,text:String,x:int,y:int) -> void:
	var asc:=FileAccess.get_file_as_bytes("res://assets/ui/service_asc16.bin")
	var hzk:=FileAccess.get_file_as_bytes("res://assets/ui/service_hzk16.bin")
	var bytes:=GBK.encode(text,256);var i:=0
	while i<bytes.size() and bytes[i]!=0:
		var stride:=1;var at:int=bytes[i]*16;var source:PackedByteArray=asc
		if bytes[i]>=128:
			if i+1>=bytes.size():break
			stride=2;at=((int(bytes[i])-0xA1)*94+int(bytes[i+1])-0xA1)*32;source=hzk
		for yy in range(16):
			for xx in range(stride*8):
				if at+yy*stride+xx/8<source.size() and source[at+yy*stride+xx/8]&(0x80>>(xx%8)):_index_pixel(raw,x+xx,y+yy,0x48)
		x+=stride*8;i+=stride

func _touch_back() -> void:
	if not enabled or campaign._service_input_blocked():return
	if kind=="shop":
		if not campaign.shop_pending.is_empty():campaign._shop_cancel_selection()
		else:_activate("back")
	elif kind=="mines" and campaign.k04_held>=0:
		campaign.k04_held=-1;campaign.k04_source=-1;drag.clear();queue_redraw()
	else:pressed="";drag.clear();_activate("back")

func _touch_mine_tap(point:Vector2) -> void:
	var control:=_control_at(point)
	if not control.is_empty():_activate(control);return
	var source:=mine_at(point)
	if not source.is_empty() and (campaign.k04_person!=-999 or campaign.state.mine_count(int(source.packed))>0):
		campaign._k04_pick(int(source.index),int(source.packed));queue_redraw();return
	var pid:=mine_person_at(point)
	if pid!=-999:campaign._k04_target(pid)
	elif Rect2(525,308,64,54).has_point(point):campaign._k04_sell()
	elif Rect2(525,372,64,54).has_point(point):campaign._k04_store()
