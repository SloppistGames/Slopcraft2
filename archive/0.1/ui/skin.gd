class_name SlopSkin
extends RefCounted

static var font: Font = preload("res://assets/pixel.ttf")
static var theme_cache: Theme
const CREAM = Color("eee9d8")
const MUTED = Color("b1b7a7")
const ACCENT = Color("c3db8a")

static func theme() -> Theme:
	if theme_cache: return theme_cache
	var t = Theme.new()
	t.default_font = font
	t.default_font_size = 17
	t.set_color("font_color", "Label", CREAM)
	t.set_color("font_shadow_color", "Label", Color(0,0,0,0.65))
	t.set_constant("shadow_offset_x", "Label", 2)
	t.set_constant("shadow_offset_y", "Label", 2)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var col = Color("61665d")
		if state == "hover": col = Color("7e896b")
		if state == "pressed": col = Color("3e4937")
		if state == "disabled": col = Color("333830")
		t.set_stylebox(state, "Button", stone(col, state == "hover" or state == "focus"))
	t.set_color("font_color", "Button", CREAM)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", Color("767a6f"))
	t.set_color("font_shadow_color", "Button", Color(0,0,0,.8))
	t.set_constant("shadow_offset_x", "Button", 2)
	t.set_constant("shadow_offset_y", "Button", 2)
	t.set_stylebox("normal", "LineEdit", panel(Color("171e19")))
	t.set_stylebox("focus", "LineEdit", panel(Color("243124"), ACCENT))
	t.set_color("font_color", "LineEdit", CREAM)
	t.set_color("font_placeholder_color", "LineEdit", Color("798573"))
	t.set_stylebox("panel", "PanelContainer", panel())
	t.set_stylebox("background", "ProgressBar", panel(Color("101810")))
	t.set_stylebox("fill", "ProgressBar", panel(ACCENT))
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	t.set_constant("h_separation", "GridContainer", 6)
	t.set_constant("v_separation", "GridContainer", 6)
	theme_cache = t
	return t

static func panel(color: Color = Color("202820"), edge: Color = Color("59624d")) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = edge
	s.set_border_width_all(2)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 16
	s.content_margin_bottom = 16
	s.shadow_color = Color(0,0,0,0.35)
	s.shadow_size = 6
	return s

static func stone(color: Color, highlight: bool = false) -> StyleBoxTexture:
	var img = Image.create(64,32,false,Image.FORMAT_RGBA8)
	var rng = RandomNumberGenerator.new()
	rng.seed = 24
	for y in 32:
		for x in 64:
			var c = color * rng.randf_range(0.91,1.09)
			c.a = 1
			if y < 2 or x < 2: c = color.lightened(.28)
			if y >= 30 or x >= 62: c = color.darkened(.5)
			if y == 0 or x == 0 or y == 31 or x == 63: c = Color("151a13")
			if highlight and (y == 1 or x == 1 or y == 30 or x == 62): c = ACCENT
			img.set_pixel(x,y,c)
	var s = StyleBoxTexture.new()
	s.texture = ImageTexture.create_from_image(img)
	s.axis_stretch_horizontal=StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	s.axis_stretch_vertical=StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		s.set_texture_margin(side,4)
		s.set_content_margin(side,9)
	return s

static func label(text: String, size: int = 18, color: Color = CREAM) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size",size)
	l.add_theme_color_override("font_color",color)
	return l

static func button(text: String, fn: Callable, width: float = 0) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width,46)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(fn)
	return b

static func inventory_slot(selected: bool = false) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color("303a32") if not selected else Color("46523a")
	style.border_color = Color("64715f") if not selected else ACCENT
	style.set_border_width_all(3)
	style.set_content_margin_all(3)
	style.shadow_color = Color(0,0,0,.28)
	style.shadow_size = 2
	return style

static func style_slot(button_node: Button, selected: bool = false) -> void:
	button_node.add_theme_stylebox_override("normal",inventory_slot(selected))
	button_node.add_theme_stylebox_override("hover",inventory_slot(true))
	button_node.add_theme_stylebox_override("pressed",inventory_slot(true))
	button_node.add_theme_stylebox_override("focus",inventory_slot(true))
