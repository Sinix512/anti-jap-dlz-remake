extends Control

# 41DF85: negative results never enter the blue victory report.
# 43D454 notice -> 42738A MENU03 yes/no; no portrait or mandatory OK.
signal retry_requested
signal title_requested

const ROWS := [Rect2(304,232,120,24), Rect2(304,256,120,24)]
const NORMAL := Color("#a4fcfc")
const SELECTED := Color("#fc8c00")
var stage := "notice"
var elapsed := 0.0
var choice := 0
var notice: Control
var prompt: Control
var options: Array[Label] = []
var selected_row: TextureRect


func setup(font: Font) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	notice=preload("res://scripts/ui/OriginalStoryPage.gd").new()
	add_child(notice)
	var pages:=preload("res://scripts/ui/OriginalStoryLayout.gd").pages("战斗失败！","",46)
	notice.setup(font,pages[0],-1,"KUANG04",46)
	notice.confirmed.connect(_open_retry)
	prompt = Control.new()
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt.visible = false
	add_child(prompt)
	prompt.add_child(OriginalUI.panel("res://assets/ui/retry_original.png",Rect2(300,200,128,88)))
	selected_row = TextureRect.new()
	selected_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt.add_child(selected_row)
	prompt.add_child(_label("重来吗？",font,Vector2(332,204),Vector2(64,16)))
	for row in range(2):
		var label := _label("是" if row == 0 else "否",font,Vector2(356,236+24*row),Vector2(16,16))
		options.append(label)
		prompt.add_child(label)
	_select(0)


func _label(text: String, font: Font, at: Vector2, bounds: Vector2) -> Label:
	var label := OriginalUI.label(text,font,16,NORMAL)
	label.position = at
	label.size = bounds
	label.add_theme_color_override("font_shadow_color",Color.TRANSPARENT)
	return label


func _advance(delta:float) -> void:
	# QA clock injection follows exactly the same child state machine.
	if stage=="notice":notice._advance(delta)

func _open_retry() -> void:
	if stage!="notice":return
	stage="retry";notice.hide();notice.set_process_input(false);notice.set_process(false);prompt.show()
	if DisplayServer.get_name()!="headless":get_viewport().warp_mouse(Vector2(364,244))

func _input(event:InputEvent) -> void:
	if stage!="retry":return
	if event is InputEventMouse or event is InputEventKey:get_viewport().set_input_as_handled()
	_on_gui_input(event)


func _select(row: int) -> void:
	choice = row
	selected_row.texture = load("res://assets/ui/retry_selected_%d.png" % row)
	selected_row.position = ROWS[row].position
	for i in range(options.size()):
		options[i].add_theme_color_override("font_color",SELECTED if i == row else NORMAL)


func _choose(retry: bool) -> void:
	if stage != "retry": return
	stage = "done" # one physical click cannot dispatch twice
	if retry: retry_requested.emit()
	else: title_requested.emit()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if stage == "retry" and event.pressed:
			# 42738A confirms its current hover row on DOWN, even outside
			# the panel. It does not reselect from the click coordinates.
			if event.button_index == MOUSE_BUTTON_RIGHT:_choose(false)
			elif event.button_index == MOUSE_BUTTON_LEFT:_choose(choice==0)
	elif event is InputEventMouseMotion and stage == "retry":
		if event.position.x>=0 and event.position.x<640 and event.position.y>=232 and event.position.y<280:
			_select(int((event.position.y-232)/24))
