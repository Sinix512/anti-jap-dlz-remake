extends SceneTree
const Mask=preload("res://scripts/battle/OriginalRangeMask.gd")
const Codec=preload("res://scripts/battle/StateCodec.gd")
class Observer extends RefCounted:
	var status_text:=""
	func on_tick() -> void:pass
	func on_unit_moved(_u) -> void:pass
	func on_unit_died(_u) -> void:pass
	func check_end() -> bool:return false
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("RANGE_MASK_FAIL "+label)
func run() -> void:
	var data:Dictionary=Codec.integers(JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json")))
	var fixtures:Dictionary=Codec.integers(JSON.parse_string(FileAccess.get_file_as_string("res://../extract/research_range_mask_20261025.fixtures.json")))
	var b=load("res://scripts/Battle.gd").new();root.add_child(b)
	b.setup(data,data.levels[0].duplicate(true),load("res://assets/font/hzk16.fnt"),{})
	b.set_process(false);b.sfx_enabled=false;b.fast_sim=true;b.scenario=Observer.new();b.finished_flag=false;b._finishing=false;b.busy=false;b.phase="player"
	check(b.selected==null and b.native_range_phase=="idle" and b.native_dark_mask.count(0)==b.map_w*b.map_h,"41B53C initial全亮未选中")
	check(b.native_range_layer.z_index>b.map_sprite.z_index and b.native_range_layer.z_index< -2,"dark map between map and markers")
	check(b.native_range_layer.texture!=null,"generated indexed dark map loaded")
	var hero=b.units[0]
	hero.slot=0;hero.data.faction=0;hero.side="player";hero.control=true;hero.auto=false
	b.enemy_units.erase(hero);b.player_units.append(hero)
	for u in b.units.duplicate():
		if u==hero:continue
		b.units.erase(u);b.player_units.erase(u);b.enemy_units.erase(u);u.free()
	var original_w:int=b.map_w;var original_h:int=b.map_h
	for vector in fixtures.vectors:
		var result:=PackedByteArray()
		var center:=Vector2i(vector.center[0],vector.center[1])
		if vector.kind=="selection":
			result=Mask.selection(vector.width,vector.height,center,data.select_ranges[str(vector.range_id)],vector.force_center_zero)
		else:
			b.map_w=vector.width;b.map_h=vector.height;b.terrain=[];b.terrain.resize(vector.width*vector.height);b.terrain.fill(0)
			hero.set_tile(center.x,center.y);hero.move=vector.budget
			b.data.unit_move[str(hero.bingzhong)][0]=1
			var others:Array=[]
			for x in range(vector.width):
				if x==center.x or vector.occupancy[x]==0:continue
				var d:Dictionary=hero.state_record()
				d.merge({"slot":40+x,"x":x,"y":0,"faction":vector.occupancy[x]-1,"side":"enemy" if vector.occupancy[x]==2 else "player"},true)
				others.append(b._spawn_unit(d))
			result=Mask.movement(vector.width,vector.height,center,b.compute_reachable(hero))
			for other in others:
				b.units.erase(other);b.player_units.erase(other);b.enemy_units.erase(other);other.free()
		var expected:=PackedByteArray()
		for row in vector.expected_mask_rows:expected.append_array(PackedByteArray(row))
		check(result==expected,"all world bytes "+str(vector.name))
		check(not Mask.allows(result,vector.width,vector.height,Vector2i(-1,0)),"outside map rejected "+str(vector.name))
	# Original byte inversion, not truthiness:2 becomes255, not a legal zero.
	var odd:Array=[]
	for y in range(9):odd.append([0,0,0,0,0,0,0,0,0])
	odd[4][4]=2
	var odd_mask:=Mask.selection(1,1,Vector2i.ZERO,odd)
	check(odd_mask[0]==255 and not Mask.allows(odd_mask,1,1,Vector2i.ZERO),"nonbinary matrix byte inversion")
	b.map_w=original_w;b.map_h=original_h;b.terrain=[];b.terrain.resize(original_w*original_h);b.terrain.fill(0);b.chests.clear();b.mines.clear()
	hero.set_tile(5,15);hero.direction=2;hero.moved=false;hero.acted=false;hero.move=4
	b._select_unit(hero)
	var original_mask:PackedByteArray=b.native_dark_mask.duplicate()
	var origin:=Vector2i(hero.x,hero.y)
	var target:Vector2i=b.move_tiles.keys()[0]
	b.fast_sim=false;b.animations_enabled=true;b.animation_speed=2
	b._player_move(target)
	var samples:=0
	var move_preserved:=true
	for tick in range(120):
		if not b.busy:break
		if b.native_range_phase=="move":
			move_preserved=move_preserved and b.native_dark_mask==original_mask
			samples+=1
		await create_timer(0.02).timeout
	check(move_preserved,"move subframes preserve original map mask")
	check(samples>=2,"movement really yielded multiple displayed substeps")
	check(Vector2i(hero.x,hero.y)==target and b.native_range_phase=="menu" and b.native_dark_mask.count(0)==b.map_w*b.map_h,"move returns -> clear -> full-bright menu")
	b._on_attack()
	check(b.mode=="attack" and b.native_range_phase=="attack-target" and not b.attack_tiles.is_empty(),"attack has legal cells even with no enemies")
	var target_mask:PackedByteArray=b.native_dark_mask.duplicate()
	b._on_map_click(Vector2i(0,0))
	check(b.mode=="attack" and b.native_dark_mask==target_mask,"invalid dark click keeps target mode/mask")
	b._cancel()
	check(b.mode=="idle" and b.native_range_phase=="menu" and is_instance_valid(b.context_menu) and b.native_dark_mask.count(0)==b.map_w*b.map_h,"target cancel -> clear -> action menu, not move mask")
	b._cancel()
	check(b.selected==null and Vector2i(hero.x,hero.y)==origin and hero.direction==2 and not hero.moved,"menu cancel restores pre-move position/direction/action")
	b._select_unit(hero);b._cancel()
	check(b.selected==null and b.native_dark_mask.count(0)==b.map_w*b.map_h,"movement cancel clears selection/mask")
	b.fast_sim=true
	var violations:Array=[]
	b.presentation_step.connect(func(kind:String,_payload:Dictionary):
		if kind in ["numbers_start","numbers_end","inactive","death_end"] and b.native_dark_mask.count(0)!=b.map_w*b.map_h:violations.append(kind)
	)
	for kind in ["attack","skill","item"]:
		hero.acted=false;hero.moved=false;hero.item_slots=[2,0,0,0,0,0,0,0]
		hero.skill_counts.buji=1;b._select_unit(hero);b._open_context_menu();b._close_context_menu()
		if kind=="attack":
			b._on_attack()
			var empty:Vector2i=b.attack_tiles.keys()[0]
			await b._perform_attack_at(hero,empty)
		elif kind=="skill":
			b._choose_skill(0);await b._execute_skill_at(Vector2i(hero.x,hero.y))
		else:
			b._choose_item(1);await b._execute_item_at(Vector2i(hero.x,hero.y))
		check(hero.acted and b.native_dark_mask.count(0)==b.map_w*b.map_h,kind+" consumes action and clears range before effect")
	check(violations.is_empty(),"all numeric/death stages use cleared mask")
	await mine_ranges(b,hero)
	# Actual generated map pixels equal the RE LUT, not a generic50% tint.
	var index:Image=(load(str(b.level.map.png).replace(".png","_index.png")) as Texture2D).get_image()
	index.convert(Image.FORMAT_L8)
	var indices:PackedByteArray=index.get_data()
	var dark:Image=b.native_range_layer.texture.get_image()
	for pixel in [0,1,48,777,4096,indices.size()-1]:
		var pal:int=int(data.meta.map_dark_lut[indices[pixel]])*3
		var color:=Color8(data.meta.battle_palette[pal],data.meta.battle_palette[pal+1],data.meta.battle_palette[pal+2])
		check(dark.get_pixel(pixel%index.get_width(),pixel/index.get_width()).is_equal_approx(color),"generated LUT pixel%d"%pixel)
	b.free();await process_frame
	print("ORIGINAL_RANGE_MASK checks=",checks," failures=",failures)
	print("ORIGINAL_RANGE_MASK_OK" if failures==0 else "ORIGINAL_RANGE_MASK_FAIL")
	quit(1 if failures else 0)

func mine_ranges(b,hero) -> void:
	var fixtures:Dictionary=Codec.integers(JSON.parse_string(FileAccess.get_file_as_string("res://../extract/research_mine_ui_mask_20261025.fixtures.json")))
	var width:int=b.map_w;var height:int=b.map_h;var saved_terrain:Array=b.terrain;var saved_index:int=b.level.index
	for vector in fixtures.mask_vectors:
		b.map_w=vector.width;b.map_h=vector.height
		var center:=Vector2i(vector.center[0],vector.center[1])
		var result:=PackedByteArray()
		if int(vector.get("mode",0))==2:
			b.level.index=2;b.mines.clear();hero.set_tile(center.x,center.y)
			b.terrain=[];b.terrain.resize(b.map_w*b.map_h);b.terrain.fill(0)
			var code:int=vector.get("selected_code",0)
			var row:Array=b.data.mine_terrain[code/4]
			row.fill(1);row[1]=0
			for cell in vector.get("terrain_disallowed",[]):b.terrain[int(cell[1])*b.map_w+int(cell[0])]=1
			for cell in vector.get("mines_present",[]):b.mines.append({"tile":Vector2i(cell[0],cell[1]),"code":0,"low":1})
			var others:Array=[]
			for cell in vector.get("occupied",[]):
				var tile:=Vector2i(cell[0],cell[1])
				if tile==center:continue
				var d:Dictionary=hero.state_record();d.merge({"slot":127,"x":tile.x,"y":tile.y},true)
				others.append(b._spawn_unit(d))
			for idx in vector.get("level_indexes",[2]):
				b.level.index=idx
				result=Mask.from_cells(b.map_w,b.map_h,b._mine_place_tiles(hero,code).keys())
				var expected:=PackedByteArray()
				for line in vector.expected_rows:expected.append_array(PackedByteArray(line))
				check(result==expected,"native place filter all bytes "+str(vector.name)+" L"+str(idx))
			for other in others:
				b.units.erase(other);b.player_units.erase(other);b.enemy_units.erase(other);other.free()
		else:
			result=Mask.mine_geometry(b.map_w,b.map_h,center,int(vector.get("mode",0))==7)
			var expected:=PackedByteArray()
			for line in vector.expected_rows:expected.append_array(PackedByteArray(line))
			check(result==expected,"pure mine geometry all bytes "+str(vector.name))
	b.map_w=width;b.map_h=height;b.terrain=saved_terrain;b.level.index=saved_index;b.mines.clear()
	for vector in fixtures.qualification_vectors:
		hero.set_tile(5,15);hero.acted=false;hero.moved=false;hero.hp=500;hero.max_hp=500;hero.mine_slots=[31,0,0,0,0,0,0,0]
		var target:=Vector2i(6 if vector.mask==0 else 11,15)
		var other=null
		if int(vector.occupancy_presence)>0:
			var d:Dictionary=hero.state_record();d.merge({"slot":127,"x":target.x,"y":target.y,"faction":int(vector.occupancy_presence)-1,"side":"enemy" if vector.occupancy_presence==2 else "player"},true)
			other=b._spawn_unit(d)
		if int(vector.mine_low)>0:b.mines.append({"tile":target,"code":vector.mine_code,"mine_id":int(vector.mine_code)%10,"mine":b.data.mines[int(vector.mine_code)%10],"low":vector.mine_low})
		b._select_unit(hero)
		if vector.kind=="give":b._choose_mine_transfer(30)
		else:b._mine_command(vector.kind)
		var mask:PackedByteArray=b.native_dark_mask.duplicate()
		await b._mine_click(target)
		var accepted:bool=is_instance_valid(b.action_panel) if vector.kind=="timer" else hero.acted
		check(accepted==bool(vector.target_qualified),"native mine qualification "+str(vector))
		if not accepted:check(b.native_dark_mask==mask and not hero.acted,"invalid mine click keeps range and action")
		b._close_action_panel();b._clear_selection();b.mines.clear()
		if other!=null:
			b.units.erase(other);b.player_units.erase(other);b.enemy_units.erase(other);other.free()
	# Cancelling the rounds popup is NOT cancelling its target mode.
	hero.acted=false;hero.moved=false;hero.mine_slots=[21,0,0,0,0,0,0,0];hero.set_tile(5,15)
	b.data.mine_terrain[5].fill(1);b._select_unit(hero);b._open_context_menu();b._close_context_menu();b.mine_kind=20;b._place_mine()
	var mask:PackedByteArray=b.native_dark_mask.duplicate()
	b._mine_click(Vector2i(6,15))
	check(is_instance_valid(b.action_panel) and b.mode=="mine_place","timed place opens rounds popup")
	b._cancel()
	check(not is_instance_valid(b.action_panel) and b.mode=="mine_place" and b.native_dark_mask==mask and hero.mine_slots[0]==21 and not hero.acted,"rounds cancel preserves original target range and inventory")
	b._cancel()
	check(b.native_range_phase=="menu" and b.native_dark_mask.count(0)==b.map_w*b.map_h,"mine target right cancel clears into action menu")
	b._cancel()
	check(b.selected==null and b.native_range_phase=="idle","mine action menu cancel ends selection")
