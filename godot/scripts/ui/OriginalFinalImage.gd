extends "res://scripts/ui/OriginalReleaseWait.gd"
# JZ uses its own palette, fade-in step1, then W without any1000ms delay.
# The final JZ-2 fade-out also has step1; the first page uses step4.
const Fade=preload("res://scripts/ui/OriginalPaletteFade.gd")
var exit_increment:=4
var fade_events:Array=[]
func setup(image:Texture2D,last_page:=false) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	var picture:=TextureRect.new();picture.texture=image;picture.size=Vector2(640,480)
	picture.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(picture)
	exit_increment=1 if last_page else 4
	fade_events.append({"entering":true,"increment":1});Fade.play(self,true,1,false,image)
	begin_wait()
func _accept() -> void:
	if done:return
	fade_events.append({"entering":false,"increment":exit_increment});Fade.play(self,false,exit_increment,true)
	super._accept()
