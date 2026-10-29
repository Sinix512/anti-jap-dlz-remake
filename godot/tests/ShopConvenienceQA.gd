extends SceneTree
## Modern-default rendering fixtures, separate from the legacy pixel oracle.
## Hidden window/offscreen viewport. No saves, OS pointer changes or live game.
var c
var viewport:SubViewport
var output:String
var manifest:Dictionary={}
func _initialize() -> void:
	root.unfocusable=true;root.hide();call_deferred("run")
func settle() -> void:
	for i in range(4):await process_frame
func shot(name:String) -> void:
	await settle()
	RenderingServer.force_sync();RenderingServer.force_draw()
	var pixels:Image=viewport.get_texture().get_image()
	if pixels==null or pixels.is_empty():push_error("SHOP_QA missing framebuffer");quit(1);return
	pixels.save_png(output+"/"+name+".png")
	var panel=c.panel_root if is_instance_valid(c.panel_root) else null
	manifest[name]={"mode":c.shop_mode,"money":c.state.money,"pending":c.shop_pending.duplicate(true),"modern":c.shop_convenience_enabled,"modal":panel!=null,"warehouse_iid0":c.state.item_count(0)}
	if panel!=null and panel.get_script()==load("res://scripts/ui/ShopQuantity.gd"):
		manifest[name]["quantity"]={"value":panel.quantity,"maximum":panel.maximum,"price":panel.unit_price,"buy_disabled":panel.buy_button.disabled,"total":panel.total_label.text,"balance":panel.balance_label.text,"size":[panel.size.x,panel.size.y],"dimmer_size":[panel.get_child(0).size.x,panel.get_child(0).size.y]}
		var fits:=true
		for child in panel.get_children():
			if child is Label or child is Button or child is LineEdit:
				fits=fits and panel.CARD_RECT.encloses(child.get_rect())
				if child is Label:fits=fits and child.get_minimum_size().x<=child.size.x
		manifest[name].quantity["contents_fit"]=fits
	print("SHOP_QA_SHOT ",name)
func click(point:Vector2) -> void:
	var move=InputEventMouseMotion.new();move.position=point;move.global_position=point
	viewport.push_input(move,true)
	for down in [true,false]:
		var e=InputEventMouseButton.new();e.position=point;e.global_position=point
		e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;viewport.push_input(e,true)
		await process_frame;await process_frame
func run() -> void:
	var evidence:=OS.get_environment("DLZ_SHOP_EVIDENCE_DIR")
	if evidence.is_empty():evidence="res://../out/evidence/shop_convenience295_20261029"
	output=ProjectSettings.globalize_path(evidence.path_join("visual"))
	DirAccess.make_dir_recursive_absolute(output)
	viewport=SubViewport.new();viewport.size=Vector2i(640,480)
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	c=load("res://scripts/m4/Campaign.gd").new();c.qa_mode=true;viewport.add_child(c)
	c.setup(load("res://assets/font/hzk16.fnt"));c.set_process(false)
	if not c.shop_convenience_enabled:push_error("SHOP_QA modern UI must be default");quit(1);return
	for i in range(22):c.state.set_person_side(i,0)
	c.state.money=12345;c.selected_town=1
	c.state.protagonist.item_slots=[2,3,0,0,0,0,0,0]
	await settle()
	c._open_shop("zahuo");await shot("shop_ready")
	await click(Vector2(48,88));await shot("shop_selected")
	if c.shop_pending.is_empty():push_error("SHOP_QA click failed to persist selection");quit(1);return
	# Build a multiple-page warehouse without spending or touching player saves.
	for iid in range(25):c.state.add_item(iid,3)
	c._shop_mode(2);await settle();await click(Vector2(48,88));await shot("warehouse_selected")
	await click(Vector2(566,160));await shot("warehouse_after_sale")
	if c.state.item_count(0)!=2 or int(c.shop_pending.get("id",-1))!=0:
		push_error("SHOP_QA first sale must preserve same source");quit(1);return
	await click(Vector2(566,160));await click(Vector2(566,160));await shot("warehouse_sold_out")
	if c.state.item_count(0)!=0 or not c.shop_pending.is_empty():
		push_error("SHOP_QA sold out must clear source");quit(1);return
	c._shop_page(1,false);await shot("warehouse_page2")
	c._open_shop("material");await shot("material_ready");await click(Vector2(48,88))
	if not is_instance_valid(c.panel_root) or c.panel_root.get_script()!=load("res://scripts/ui/ShopQuantity.gd"):
		push_error("SHOP_QA modern material dialog did not open");quit(1);return
	await shot("material_quantity")
	c._close_panel();c.state.money=0;c._open_shop("material")
	await settle();await click(Vector2(48,88));await shot("material_no_funds")
	var f=FileAccess.open(output+"/manifest.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest,"\t")+"\n");f.close()
	c.queue_free();await settle();viewport.queue_free();await process_frame
	root.get_node("Music").release_playback();OriginalUI.release_native_sfx();await create_timer(.2).timeout
	print("SHOP_CONVENIENCE_QA_OK fixtures=",manifest.size());quit()
