extends SceneTree
const Quantity=preload("res://scripts/ui/OriginalQuantity.gd")
var c
var manifest:Dictionary={}
var fade_state:Dictionary={}
func _initialize() -> void:call_deferred("run")
func shot(name:String) -> void:
	c.service_screen.set_process(false)
	# These are static rendering fixtures, not desktop interaction tests.
	# Do not let an unrelated scaled OS motion move the held icon during shot.
	var input_nodes:Array=[c.service_screen]
	if is_instance_valid(c.panel_root):input_nodes.append(c.panel_root)
	var input_before:Array=input_nodes.map(func(n):return n.is_processing_input())
	for n in input_nodes:n.set_process_input(false)
	for i in range(3):await process_frame
	RenderingServer.force_sync();RenderingServer.force_draw()
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../out/ui_services/"+name+".png"))
	var screen=c.service_screen
	var e:Dictionary={"kind":screen.kind,"pressed":screen.pressed,"drag":screen.drag.duplicate(),"drag_point":[screen.drag_point.x,screen.drag_point.y],"money":c.state.money,"members":c._shop_roster().duplicate(true),"items":c.state.items.duplicate(),"mines":c.state.mines.duplicate(),"materials":c.state.materials.duplicate(),"mode":c.shop_mode,"shop_kind":c.shop_kind,"shop_person":c.shop_person,"people_page":c.shop_people_page,"item_page":c.shop_item_page,"stock":c._shop_stock().duplicate(true),"fuse":c.forge_fuse,"type":c.forge_kind,"q":c.forge_quantity,"fuse_flags":[],"type_flags":[],"mine_person":c.k04_person,"mine_page":c.k04_page}
	for i in range(4):e.fuse_flags.append(int(c.state.script_globals.get("0x%x"%(0x95eaf8+4*i),0)))
	for i in range(10):e.type_flags.append(int(c.state.script_globals.get("0x%x"%(0x95eb08+4*i),0)))
	if is_instance_valid(c.panel_root):
		if c.panel_root is Quantity:e["quantity"]={"q":c.panel_root.quantity,"max":c.panel_root.maximum,"id":int(c._shop_stock()[0].id)}
		else:e["confirm"]="全卖掉吗" if name=="bulk_confirm" else "不能用，保留吗"
	if not fade_state.is_empty():e["fade"]=fade_state.duplicate()
	manifest[name]=e;print("SERVICE_SHOT ",name)
	for i in range(input_nodes.size()):
		if is_instance_valid(input_nodes[i]):input_nodes[i].set_process_input(input_before[i])
func down(point:Vector2) -> void:
	var e:=InputEventMouseButton.new();e.position=point;e.global_position=point;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=true;root.push_input(e,true)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../out/ui_services"))
	c=load("res://scripts/m4/Campaign.gd").new();root.add_child(c);c.qa_mode=true;c.setup(load("res://assets/font/hzk16.fnt"));c.set_process(false)
	# Explicit legacy rendering oracle, not a claim about the modern shop UI.
	c.shop_convenience_enabled=false
	for i in range(22):c.state.set_person_side(i,0)
	c.state.money=12345;c.selected_town=1
	c.state.protagonist.item_slots=[82,132,1,2,3,4,5,0];c.state.protagonist.mine_slots=[1,11,21,31,2,12,22,32]
	c.state.person(1).item_slots=[10,40,70,0,0,0,0,0];c.state.person(1).mine_slots=[10,20,30,40,0,0,0,0]
	for i in range(80,105):c.state.add_item(i,i-75)
	for i in range(10):c.state.add_material(i,12+i*31)
	for i in range(40):c.state.add_mine(i,i*7+1)
	c._open_shop("junxie");await shot("shop_buy")
	c.service_screen.pressed="back";c.service_screen.queue_redraw();await shot("shop_back_down");c.service_screen.pressed=""
	down(Vector2(48,80));c.service_screen.drag_point=Vector2(250,270);c.service_screen.queue_redraw();await shot("shop_drag");c.service_screen.drag.clear();c.shop_pending.clear()
	c.shop_people_page=1;c._render_shop();await shot("shop_people1")
	c._shop_mode(1);await shot("shop_exchange")
	c._shop_mode(2);await shot("shop_warehouse0");c._shop_page(1,false);await shot("shop_warehouse1")
	c._service_confirm("全卖掉吗",func(_yes):pass);await shot("bulk_confirm");c._close_panel()
	c._open_shop("zahuo");await shot("grocery_buy");c._shop_mode(1);await shot("grocery_exchange")
	c._service_confirm("不能用，保留吗",func(_yes):pass);await shot("incompatible_confirm");c._close_panel()
	c._open_shop("material");await shot("material")
	c._shop_material(int(c._shop_stock()[0].id));await shot("quantity0")
	c.panel_root.quantity=c.panel_root.maximum/2;c.panel_root.queue_redraw();await shot("quantity_half")
	c.panel_root.quantity=c.panel_root.maximum;c.panel_root.queue_redraw();await shot("quantity_max");c._close_panel()
	for i in range(4):c.state.script_globals["0x%x"%(0x95eaf8+4*i)]=1 if i==0 else 0
	for i in range(10):c.state.script_globals["0x%x"%(0x95eb08+4*i)]=1 if i==0 else 0
	c._open_forge();await shot("forge_locked")
	for i in range(4):c.state.script_globals["0x%x"%(0x95eaf8+4*i)]=1
	for i in range(10):c.state.script_globals["0x%x"%(0x95eb08+4*i)]=1
	c.service_screen.queue_redraw();await shot("forge0")
	var fade=preload("res://scripts/ui/OriginalPaletteFade.gd")
	var overlay=fade.capture(c.ui_root);fade.phase(overlay,32,false);fade_state={"step":32,"enter":false};await shot("fade_out32");overlay.free()
	overlay=fade.capture(c.ui_root);fade.phase(overlay,32,true);fade_state={"step":32,"enter":true};await shot("fade_in32")
	fade.phase(overlay,64,true);fade_state={"step":64,"enter":true};await shot("fade_in64");overlay.free();fade_state.clear()
	c._set_forge_kind(6);c._set_forge_fuse(3);c._forge_adjust(5);await shot("forge_packed3")
	c.service_screen.pressed="plus";c.service_screen.queue_redraw();await shot("forge_plus_down");c.service_screen.pressed=""
	c._forge_set_max();await shot("forge_max")
	c._show_k04_status();await shot("mines0");c._k04_fuse(2);await shot("mines2");c._k04_fuse(1);await shot("mines3")
	c._k04_switch();await shot("mines_person0");c._k04_target(1);await shot("mines_person1")
	down(Vector2(30,50));c.service_screen.drag_point=Vector2(470,260);c.service_screen.queue_redraw();await shot("mines_drag");c.service_screen.drag.clear();c.k04_held=-1;c.k04_source=-1
	c.service_screen.pressed="switch";c.service_screen.queue_redraw();await shot("mines_switch_down")
	var file:=FileAccess.open("res://../out/ui_services/manifest.json",FileAccess.WRITE);file.store_string(JSON.stringify(manifest));file.close()
	c.queue_free();await process_frame;root.get_node("Music").release_playback();OriginalUI.release_native_sfx();await create_timer(.2).timeout
	print("ORIGINAL_SERVICES_QA_COMPLETE");quit()
