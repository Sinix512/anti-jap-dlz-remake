extends Control
# 40E709 END group: fade-in1 -> D(1000) -> records -> W, except END03
# whose record404 is followed by another D, not W. END04/05 return without
# fading; the following chapter entry owns that fade (40EA97..9D).
signal confirmed
const Fade=preload("res://scripts/ui/OriginalPaletteFade.gd")
var stage:="hold_pre"
var elapsed:=0.0
var done:=false
var image_index:=0
var record_ids:Array=[]
var context:Dictionary={}
var font:Font
var data:Dictionary={}
var player_name:=""
var story:Control
var release_wait:Control
var fade_events:Array=[]
func setup(f:Font,m5:Dictionary,index:int,records:Array,name_text:String,story_context:Dictionary) -> void:
	font=f;data=m5;image_index=index;record_ids=records.duplicate();player_name=name_text
	context=story_context.duplicate(true);context.erase("backdrop")
	context["native_palette_key"]="KUANG04";context["battle_profile"]=false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_STOP
	var picture:=TextureRect.new();picture.texture=load("res://assets/ui/end_%02d.png"%index);picture.size=Vector2(640,480)
	picture.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(picture)
	fade_events.append({"entering":true,"increment":1});Fade.play(self,true,1,false,picture.texture)
func _process(delta:float) -> void:_advance(delta)
func _advance(delta:float) -> void:
	if stage not in ["hold_pre","hold_post"]:return
	elapsed+=delta
	# 4259CC loops while elapsed<=1000. Ignore clicks during this delay.
	if elapsed<=1.0:return
	if stage=="hold_post":_finish()
	else:_begin_text()
func _input(event:InputEvent) -> void:
	if stage in ["hold_pre","hold_post","done"] and (event is InputEventMouse or event is InputEventKey):get_viewport().set_input_as_handled()
func _begin_text() -> void:
	stage="text"
	story=preload("res://scripts/m5/StoryPlayer.gd").new();add_child(story)
	story.setup(font,data,record_ids,player_name,_text_finished,context)
func _text_finished() -> void:
	story=null;elapsed=0.0
	if image_index==3:stage="hold_post"
	else:
		stage="extra_wait"
		release_wait=preload("res://scripts/ui/OriginalReleaseWait.gd").new();add_child(release_wait)
		release_wait.confirmed.connect(_finish);release_wait.begin_wait()
func _finish() -> void:
	if done:return
	done=true;stage="done"
	if image_index not in [4,5]:
		fade_events.append({"entering":false,"increment":4});Fade.play(self,false,4,true)
	confirmed.emit()
