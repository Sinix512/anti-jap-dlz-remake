extends SceneTree
const Mix=preload("res://scripts/battle/OriginalDeathMix.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("DEATH_MIX_FAIL "+label)
func lookup(color:Vector3i,palette:Array) -> int:
	var best:=20000;var found:=-1
	for i in range(256):
		var distance:=0
		for c in range(3):distance+=(int(palette[i*3+c])-color[c])**2
		if distance<1152:return i
		if distance<best:best=distance;found=i
	return found
func run() -> void:
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json"))
	var palette:Array=data.meta.battle_palette
	var source:Dictionary=Mix.sources("res://assets/map/map_00_index.png")
	check(source.lut.size()==33*65536 and source.army.size()==91*19*2304,"lossless generated source dimensions")
	check(source.box.size()==6*2304 and source.mine.size()==256,"native BOX and16px MINE indexed resources")
	check(PackedByteArray(data.meta.map_dark_lut).hex_encode()==FileAccess.get_file_as_bytes("res://../extract/research_death_cell_highlight_lut_20261025.bin").hex_encode(),"generated dark LUT matches independent RE421D10 vector")
	check(PackedByteArray(data.meta.luan_glyph)==FileAccess.get_file_as_bytes("res://../extract/research_death_cell_luan_glyph_20261025.bin"),"HZK16 C2D2 glyph exact source")
	for s in range(4):
		for d in range(4):
			for p in range(6):
				var expected:=d%2
				if s==1:expected=2+2*d+p%2
				if s==2:expected=10+2*d+p%2
				if s==3:expected=18
				check(Mix.army_frame(s,d,p)==expected,"native s%d d%d p%d frame"%[s,d,p])
	cell_layers(data)
	var synthetic:Array=[];synthetic.resize(768);synthetic.fill(255)
	for c in range(3):synthetic[c]=0;synthetic[3+c]=0
	synthetic[0]=33
	check(lookup(Vector3i.ZERO,synthetic)==0,"first acceptable, not mathematical nearest")
	synthetic[0]=24;synthetic[1]=24
	check(lookup(Vector3i.ZERO,synthetic)==1,"distance1152 not early match")
	synthetic.fill(255);synthetic[0]=60;synthetic[1]=0;synthetic[2]=0;synthetic[3]=140;synthetic[4]=0;synthetic[5]=0
	check(lookup(Vector3i(100,0,0),synthetic)==0,"fallback strict tie retains first")
	synthetic.fill(255)
	check(lookup(Vector3i.ZERO,synthetic)==-1,"undefined original boundary is not invented")
	var pairs:Array=[Vector2i(0,1),Vector2i(20,23),Vector2i(255,3),Vector2i(31,255),Vector2i(15,0),Vector2i(31,31),Vector2i(0,0),Vector2i(255,255)]
	var old:=PackedByteArray();var next:=PackedByteArray()
	for pair in pairs:old.append(pair.x);next.append(pair.y)
	var original:=old.duplicate();var background:=next.duplicate()
	var last:=PackedByteArray()
	for frame in range(33):
		var result:PackedByteArray=Mix.frame_indices(old,next,frame,source.lut)
		for p in range(pairs.size()):
			var a:int=old[p];var z:int=next[p];var expected:=a
			if a!=z:
				var color:=Vector3i.ZERO
				for c in range(3):color[c]=(int(palette[a*3+c])*(256-frame*8)+int(palette[(a if z==255 else z)*3+c])*frame*8)>>8
				expected=lookup(color,palette)
			check(result[p]==expected,"native LUT weight%d old%d new%d"%[frame*8,a,z])
		last=result
	check(old==original and next==background,"33 steps reread immutable original buffers, not cumulative lerp")
	var final:PackedByteArray=Mix.final_indices(last,next)
	for p in range(pairs.size()):check(final[p]==(last[p] if next[p]==0 else next[p]),"final key0 only;255 still written, pixel%d"%p)
	var rgba:Image=Mix.rgba(PackedByteArray([0,255]),palette,2,1)
	check(rgba.get_pixel(0,0).a==1 and rgba.get_pixel(1,0).a==1,"intermediate indices0/255 opaque, no alpha shortcut")
	# Integrate synchronous mix into the real death transaction without waiting
	# 33 process frames or allowing an input/next-action opportunity between blits.
	var b=load("res://scripts/Battle.gd").new();root.add_child(b);b.fast_sim=true
	b.setup(data,data.levels[0],load("res://assets/font/hzk16.fnt"),{})
	b.set_process(false);b.fast_sim=false;b.presentation_in_headless=true;b.animations_enabled=true
	var hero=b.units[0]
	check(hero.display_counter==0 and hero.display_state==1,"battle initial p0/s1")
	for direction in range(4):
		hero.direction=direction;hero.acted=false;hero.refresh()
		check(not hero.sprite.flip_h and hero.sprite.modulate==Color.WHITE and hero.sprite.region_rect.position.x==Mix.army_frame(1,direction,0)*48,"native ready direction%d no flip/tint"%direction)
		hero.acted=true
		check(hero.display_state==0 and hero.sprite.region_rect.position.x==(direction%2)*48 and hero.sprite.modulate==Color.WHITE,"native wait direction%d uses dedicated0/1 frame"%direction)
	hero.acted=false
	b.busy=false;b.finished_flag=false;b.display_timer_elapsed=0;b.display_timer_count=0
	b._advance_display_timer(0.275001)
	check(b.display_timer_count==5 and hero.display_counter==0,"idle five55ms ticks do not advance")
	b._advance_display_timer(0.055)
	check(b.display_timer_count==6 and hero.display_counter==1,"idle sixth tick advances ready p")
	hero.acted=true;b._advance_display_timer(0.33)
	check(hero.display_counter==1,"idle does not advance s0")
	b.busy=true;b._advance_display_timer(2.0);b.busy=false
	check(b.display_timer_count==12 and hero.display_counter==1,"blocking actions do not run idle callbacks")
	var position_before:Vector2=hero.position
	for parity in [0,1]:
		hero.display_counter=parity
		await hero.play_attack(false)
		check(hero.display_counter==parity+5 and hero.display_state==2 and hero.position==position_before,"five attack pairs, no counter reset or lunge parity%d"%parity)
	hero.display_state=1;hero.acted=false
	var old_tile:=Vector2i(hero.x,hero.y)
	var old_counter:int=hero.display_counter
	b.fast_sim=true
	await hero.move_visual(hero.x+1,hero.y)
	check(hero.display_counter==old_counter+4 and hero.display_state==1 and hero.direction==3,"move four12px steps advances p4, retains s")
	hero.set_tile(old_tile.x,old_tile.y);b.fast_sim=false
	for state in [0,1]:
		hero.display_state=state
		hero.take_damage(1)
		check(hero.display_state==3 and hero.native_frame()==18,"damage temporary s3 from%d"%state)
		hero.restore_damage_display()
		check(hero.display_state==state,"damage restores saved s%d before death"%state)
	hero.take_damage(1);hero.acted=true;hero.restore_damage_display()
	check(hero.display_state==0,"state0 command is not rolled back by damage restoration")
	var state_record:Dictionary=hero.state_record()
	check(state_record.display_counter==hero.display_counter and state_record.display_state==0,"JSON retains native display fields")
	hero.acted=false
	for i in b.chest_nodes:
		var marker=b.chest_nodes[i]
		var box:Dictionary=b.chests[i]
		check(marker.texture.region.position.y==int(box.appearance)*96 and marker.modulate==Color.WHITE and marker.z_index<hero.z_index,"scene native closed box frame/layer%d"%i)
	var test_mine:Dictionary={"tile":Vector2i(hero.x,hero.y),"mine":data.mines[0]}
	b._draw_mine(test_mine)
	var mine=b.mine_nodes[test_mine.tile]
	check(mine.texture.get_size()==Vector2(16,16) and mine.scale==Vector2.ONE and mine.z_index<hero.z_index,"scene native16px mine below unit")
	var c:Dictionary=b.chests[0]
	c.opened=true;b.chest_nodes[0].texture=b._chest_texture(c)
	check(b.chest_nodes[0].texture.region.position.y==int(c.appearance)*96+48,"scene opened box uses second frame, no translucent tint")
	b.camera_follow=false;b.camera.position=b._focus_position(hero.position);b.camera.force_update_scroll()
	var steps:Array=[]
	b.presentation_step.connect(func(kind:String,payload:Dictionary):
		if kind.begins_with("death_mix"):steps.append({"kind":kind,"weight":payload.get("weight",-1)})
	)
	var scene_frame:=Engine.get_process_frames()
	b._play_death_mix(hero)
	check(steps.size()==35 and steps[0].kind=="death_mix_start" and steps[-1].kind=="death_mix_end","one synchronous35-event mix transaction")
	check(steps.filter(func(e):return e.kind=="death_mix_frame").map(func(e):return e.weight)==range(0,257,8),"exact33 weights0..256")
	check(Engine.get_process_frames()==scene_frame and hero.sprite.scale==Vector2.ONE and not hero.visible,"no frame waits or shrink, unit hidden at completed blit")
	b.queue_free();await process_frame
	print("ORIGINAL_DEATH_MIX checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func cell_layers(data:Dictionary) -> void:
	var map:=PackedByteArray();map.resize(2304);map.fill(7)
	var army:=PackedByteArray();army.resize(912*48);army.fill(0)
	# Asymmetrical points ensure no accidental horizontal flip; frame1 only.
	army[48]=31;army[48+47]=32;army[16*912+48+16]=33
	var boxes:=PackedByteArray();boxes.resize(6*2304)
	for f in range(6):
		boxes[f*2304]=10+f;boxes[f*2304+100]=20+f
	var mine:=PackedByteArray();mine.resize(256);mine.fill(0);mine[0]=40;mine[255]=41
	var dark:=PackedByteArray();dark.resize(256)
	for i in range(256):dark[i]=i/2
	var glyph:=PackedByteArray();glyph.resize(32);glyph.fill(0);glyph[0]=128
	var layers:Dictionary={"box":boxes,"mine":mine,"chests":[],"dark":true,"dark_lut":dark,"luan_glyph":glyph}
	var result:Dictionary=Mix.tile_buffers(map,1,Vector2i.ZERO,army,0,1,layers)
	check(result.new[2]==3 and result.old[2]==3,"only map passes dark LUT")
	check(result.old[0]==31 and result.old[47]==32 and result.new[0]==3,"unit original orientation, zero-only transparency")
	for appearance in range(3):
		for empty in [false,true]:
			layers.chests=[{"x":0,"y":0,"appearance":appearance,"wupin":-1 if empty else 5}]
			result=Mix.tile_buffers(map,1,Vector2i.ZERO,army,0,1,layers)
			var frame:int=appearance*2+(1 if empty else 0)
			check(result.new[0]==10+frame and result.new[100]==20+frame and result.old[0]==31,"box%d empty%s before unit, not darkened"%[appearance,empty])
	layers.chests=[{"x":0,"y":0,"appearance":1,"wupin":4,"opened":true},{"x":0,"y":0,"appearance":2,"wupin":4}]
	layers.mine_present=true
	result=Mix.tile_buffers(map,1,Vector2i.ZERO,army,0,1,layers)
	check(result.new[0]==13,"first coordinate match only; opened state keeps native empty frame")
	check(result.new[16*48+16]==40 and result.new[31*48+31]==41 and result.new[16*48+15]==3,"mine16px at16,16 only; not darkened")
	check(result.old[16*48+16]==33,"unit covers map mine")
	layers.behavior=11
	result=Mix.tile_buffers(map,1,Vector2i.ZERO,army,0,1,layers)
	check(result.old[16*48+16]==0xB7 and result.new[16*48+16]==40,"behavior11 foregroundB7 glyph only in old")
	layers.behavior=10
	result=Mix.tile_buffers(map,1,Vector2i.ZERO,army,0,1,layers)
	check(result.old[16*48+16]==33,"other behaviors do not show luan glyph")
	check(map[0]==7 and army[48]==31 and boxes[0]==10 and mine[0]==40,"composition never modifies source buffers")
