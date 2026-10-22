class_name OriginalUI
extends RefCounted

## M3 原味 UI 工具箱。
## 只做表现：原版贴图 + HZK16 + 640×480；不碰 M4 关卡逻辑。

const FONT := "res://assets/font/hzk16.fnt"
const CURSOR := "res://assets/ui/cursor.png"

const GOLD := Color("#e8ba4c")
const GOLD_LIGHT := Color("#ffe7a3")
const GOLD_DARK := Color("#7a5420")
const INK := Color("#f2ead6")
const MUTED := Color("#b9a98b")
const RED := Color("#a31d1d")
const GREEN := Color("#78c46a")
const BLUE := Color("#7db7e8")
const BLACK := Color("#090707")

const PANEL_RED := "res://assets/ui/panel_red.png"
const PANEL_BLUE := "res://assets/ui/panel_blue.png"
const PANEL_DARK := "res://assets/ui/panel_dark.png"
const PANEL_STONE := "res://assets/ui/panel_stone.png"
const HEADER := "res://assets/ui/header.png"
const SLOT := "res://assets/ui/slot.png"
const TARGET := "res://assets/ui/target.png"
const GLOW := "res://assets/ui/glow.png"
const CHEST := "res://assets/ui/chest_sheet.png"
const DIALOG := "res://assets/ui/dialog_panel.png"

static var _theme: Theme
static var _sfx: AudioStreamPlayer
static var _hover_sfx: AudioStreamPlayer


static func make_theme(font: Font) -> Theme:
	if _theme != null and _theme.default_font == font:
		return _theme
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 16
	t.set_color("font_color", "Label", INK)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.85))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)

	t.set_stylebox("normal", "Button", _style("button_normal.png"))
	t.set_stylebox("hover", "Button", _style("button_hover.png"))
	t.set_stylebox("pressed", "Button", _style("button_pressed.png"))
	t.set_stylebox("disabled", "Button", _style("button_disabled.png"))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", GOLD_LIGHT)
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", Color("#b0a28a"))
	t.set_color("font_hover_pressed_color", "Button", GOLD)
	t.set_constant("outline_size", "Button", 0)
	t.set_font_size("font_size", "Button", 16)

	t.set_stylebox("panel", "PanelContainer", _style("panel_red.png"))
	t.set_stylebox("panel", "Panel", _style("panel_red.png"))
	t.set_color("font_color", "RichTextLabel", INK)
	t.set_font_size("normal_font_size", "RichTextLabel", 16)

	t.set_stylebox("background", "ProgressBar", _style("slot.png"))
	t.set_stylebox("fill", "ProgressBar", StyleBoxFlat.new())
	t.set_color("font_color", "ProgressBar", INK)
	t.set_font_size("font_size", "ProgressBar", 12)
	return t


static func _style(name: String) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	var path := "res://assets/ui/" + name
	if ResourceLoader.exists(path):
		sb.texture = load(path)
	sb.texture_margin_left = 8
	sb.texture_margin_right = 8
	sb.texture_margin_top = 7
	sb.texture_margin_bottom = 7
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb


static func apply_cursor() -> void:
	if ResourceLoader.exists(CURSOR):
		var tex: Texture2D = load(CURSOR)
		if tex != null:
			Input.set_custom_mouse_cursor(tex, Input.CURSOR_ARROW, Vector2(2, 2))


static func label(text: String, font: Font, size: int = 16,
		color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func title(text: String, font: Font, size: int = 32,
		color: Color = GOLD) -> Label:
	var l := label(text, font, size, color)
	l.add_theme_color_override("font_outline_color", Color(66, 22, 8, 1))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func button(text: String, font: Font, size: Vector2 = Vector2(160, 34),
		cb: Callable = Callable(), fs: int = 16) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.size = size
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", fs)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var style_name := "button_normal.png"
	if size.x <= 84 and size.y <= 28:
		style_name = "button_small_normal.png"
	elif size.x >= 200:
		style_name = "button_wide_normal.png"
	var normal := _style(style_name)
	var hover := _style(style_name.replace("_normal", "_hover"))
	var pressed := _style(style_name.replace("_normal", "_pressed"))
	var disabled := _style(style_name.replace("_normal", "_disabled"))
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if cb.is_valid():
		b.pressed.connect(cb)
	b.pressed.connect(_click)
	b.mouse_entered.connect(_hover)
	return b


static func panel(path: String = PANEL_RED, rect: Rect2 = Rect2(0, 0, 100, 100)) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = load(path) if ResourceLoader.exists(path) else null
	tr.position = rect.position
	tr.size = rect.size
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


static func nine_patch(path: String, rect: Rect2, margin: int = 8) -> NinePatchRect:
	var n := NinePatchRect.new()
	if ResourceLoader.exists(path):
		n.texture = load(path)
	n.position = rect.position
	n.size = rect.size
	n.patch_margin_left = margin
	n.patch_margin_right = margin
	n.patch_margin_top = margin
	n.patch_margin_bottom = margin
	n.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return n


static func header(text: String, font: Font, rect: Rect2 = Rect2(0, 0, 640, 30)) -> Control:
	var root := Control.new()
	root.position = rect.position
	root.size = rect.size
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := panel(HEADER, Rect2(0, 0, rect.size.x, rect.size.y))
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	root.add_child(bg)
	var l := label(text, font, 16, GOLD_LIGHT)
	l.position = Vector2(10, 5)
	l.size = Vector2(rect.size.x - 20, 22)
	root.add_child(l)
	return root


static func frame(rect: Rect2, title_text: String, font: Font,
		body: Control = null) -> Control:
	var root := Control.new()
	root.position = rect.position
	root.size = rect.size
	var bg := nine_patch(PANEL_RED, Rect2(Vector2.ZERO, rect.size), 10)
	root.add_child(bg)
	var bar := header(title_text, font, Rect2(0, 0, rect.size.x, 30))
	root.add_child(bar)
	if body != null:
		body.position = Vector2(12, 40)
		body.size = Vector2(rect.size.x - 24, rect.size.y - 52)
		root.add_child(body)
	return root


static func slot(rect: Rect2) -> Control:
	var root := Control.new()
	root.position = rect.position
	root.size = rect.size
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel(SLOT, Rect2(0, 0, rect.size.x, rect.size.y)))
	return root


static func emblem(index: int) -> TextureRect:
	var tr := TextureRect.new()
	var p := "res://assets/ui/medal_%d.png" % clampi(index, 0, 4)
	if ResourceLoader.exists(p):
		tr.texture = load(p)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


static func grade(index: int) -> TextureRect:
	var tr := TextureRect.new()
	var p := "res://assets/ui/grade_%d.png" % clampi(index, 0, 4)
	if ResourceLoader.exists(p):
		tr.texture = load(p)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


static func chest_atlas() -> AtlasTexture:
	var at := AtlasTexture.new()
	if ResourceLoader.exists(CHEST):
		at.atlas = load(CHEST)
		at.region = Rect2(0, 0, 48, 48)
	return at


static func target_texture() -> Texture2D:
	return load(TARGET) if ResourceLoader.exists(TARGET) else null


static func glow_texture() -> Texture2D:
	return load(GLOW) if ResourceLoader.exists(GLOW) else null


static func make_sfx(parent: Node) -> void:
	if _sfx != null and is_instance_valid(_sfx):
		return
	_sfx = AudioStreamPlayer.new()
	_sfx.volume_db = -8.0
	parent.add_child(_sfx)
	if ResourceLoader.exists("res://assets/ui/sfx_click.wav"):
		_sfx.stream = load("res://assets/ui/sfx_click.wav")
	_hover_sfx = AudioStreamPlayer.new()
	_hover_sfx.volume_db = -18.0
	parent.add_child(_hover_sfx)
	if ResourceLoader.exists("res://assets/ui/sfx_open.wav"):
		_hover_sfx.stream = load("res://assets/ui/sfx_open.wav")


static func _click() -> void:
	if _sfx != null and is_instance_valid(_sfx):
		_sfx.play()


static func _hover() -> void:
	if _hover_sfx != null and is_instance_valid(_hover_sfx):
		_hover_sfx.play()


static func play_sfx(name: String) -> void:
	var path := "res://assets/ui/sfx_%s.wav" % name
	if not ResourceLoader.exists(path):
		return
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.volume_db = -6.0
	var root: Node = (Engine.get_main_loop() as SceneTree).root
	root.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
