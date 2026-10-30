extends Control
# 42C620 / 42C7D4. BG03 owns the normal labels; MENU50..54 are opaque
# selected strips. Do not redraw the text, tint the background or use Buttons.
signal new_game
signal continue_game
signal high_scores
signal supporters
signal quit_game
const ROW_Y=[60,132,204,270,336]
const LABELS=["初出茅庐","继往开来","战斗英雄","支前模范","部队休整"]
const DESTINATIONS=[4,5,2,6,3]
var font:Font
var selected:=0
var counter:=0
var elapsed:=0.0
var done:=false
var background:Texture2D
var highlights:Array[Texture2D]=[]
var indicator:Texture2D

func setup(f:Font) -> void:
	font=f;theme=OriginalUI.make_theme(f)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP;texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	background=load("res://assets/ui/title_bg.png")
	for i in range(5):highlights.append(load("res://assets/ui/title_selected_%d.png"%i))
	indicator=load("res://assets/ui/title_mine02.png")
	OriginalUI.touch_back(self,font,_touch_exit,"退出")
	queue_redraw()

func row_at(point:Vector2) -> int:
	for row in range(5):
		if Rect2(315,ROW_Y[row],232,56).has_point(point):return row
	return -1

func _draw() -> void:
	if background==null:return
	draw_texture(background,Vector2.ZERO)
	draw_texture(highlights[selected],Vector2(315,ROW_Y[selected]))
	draw_texture_rect_region(indicator,Rect2(250,ROW_Y[selected],56,48),Rect2(0,counter*48,56,48))

func tick() -> void:
	counter=(counter+1)%30;queue_redraw()

func _process(delta:float) -> void:
	if done or not is_visible_in_tree():return
	elapsed+=delta
	while elapsed>=0.055:elapsed-=0.055;tick()

func _input(event:InputEvent) -> void:
	if done or not is_visible_in_tree():return
	if event is InputEventMouse or event is InputEventKey:get_viewport().set_input_as_handled()
	if OriginalUI.touch_mode(self) and event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:_touch_exit();return
	if event is InputEventMouseMotion:
		var row:=row_at(event.position)
		if row>=0 and row!=selected:selected=row;queue_redraw()
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
		var row:=row_at(event.position)
		if row<0:return
		done=true
		OriginalUI.play_native_sfx(5)
		match row:
			0:new_game.emit()
			1:continue_game.emit()
			2:high_scores.emit()
			3:supporters.emit()
			4:quit_game.emit()

func _touch_exit() -> void:
	if done:return
	done=true;quit_game.emit() # Main opens the existing confirmation, never direct quit.
